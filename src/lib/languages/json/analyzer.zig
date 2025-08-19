const std = @import("std");
const AST = @import("../../ast/mod.zig").AST;
const Node = @import("../../ast/mod.zig").Node;
const NodeType = @import("../../ast/mod.zig").NodeType;
const JsonRules = @import("../../ast/rules.zig").JsonRules;
const ASTTraversal = @import("../../ast/traversal.zig").ASTTraversal;
const ASTUtils = @import("../../ast/utils.zig").ASTUtils;
const Symbol = @import("../interface.zig").Symbol;
const Span = @import("../../parser/foundation/types/span.zig").Span;

/// JSON analyzer for schema extraction and structure analysis
///
/// Features:
/// - Extract schema information from JSON data
/// - Generate TypeScript interfaces from JSON structure
/// - Identify patterns (arrays vs objects, nullable fields)
/// - Provide statistics (depth, key count, value types)
/// - Type inference and structure analysis
/// - Performance metrics and optimization suggestions
pub const JsonAnalyzer = struct {
    allocator: std.mem.Allocator,
    options: AnalyzerOptions,

    const Self = @This();

    pub const AnalyzerOptions = struct {
        infer_array_types: bool = true,
        detect_nullable_fields: bool = true,
        suggest_optimizations: bool = true,
        max_schema_depth: u32 = 20,
        min_samples_for_inference: u32 = 2,
    };

    pub const JsonSchema = struct {
        schema_type: SchemaType,
        properties: ?std.HashMap([]const u8, JsonSchema, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
        items: ?*JsonSchema,
        nullable: bool = false,
        examples: std.ArrayList([]const u8),

        pub const SchemaType = enum {
            string,
            number,
            boolean,
            null,
            object,
            array,
            any,
        };

        pub fn deinit(self: *JsonSchema, allocator: std.mem.Allocator) void {
            if (self.properties) |*props| {
                var iter = props.iterator();
                while (iter.next()) |entry| {
                    allocator.free(entry.key_ptr.*);
                    entry.value_ptr.deinit(allocator);
                }
                props.deinit();
            }

            if (self.items) |items| {
                items.deinit(allocator);
                allocator.destroy(items);
            }

            for (self.examples.items) |example| {
                allocator.free(example);
            }
            self.examples.deinit();
        }

        pub fn init(allocator: std.mem.Allocator, schema_type: SchemaType) JsonSchema {
            return JsonSchema{
                .schema_type = schema_type,
                .properties = null,
                .items = null,
                .nullable = false,
                .examples = std.ArrayList([]const u8).init(allocator),
            };
        }
    };

    pub const JsonStatistics = struct {
        max_depth: u32,
        total_keys: u32,
        total_values: u32,
        type_counts: TypeCounts,
        size_bytes: u32,
        complexity_score: f32,

        pub const TypeCounts = struct {
            strings: u32 = 0,
            numbers: u32 = 0,
            booleans: u32 = 0,
            nulls: u32 = 0,
            objects: u32 = 0,
            arrays: u32 = 0,
        };
    };

    pub const TypeScriptInterface = struct {
        name: []const u8,
        fields: std.ArrayList(Field),
        nested_interfaces: std.ArrayList(TypeScriptInterface),

        pub const Field = struct {
            name: []const u8,
            type_name: []const u8,
            optional: bool,
            description: ?[]const u8,
        };

        pub fn deinit(self: *TypeScriptInterface, allocator: std.mem.Allocator) void {
            allocator.free(self.name);

            for (self.fields.items) |field| {
                allocator.free(field.name);
                allocator.free(field.type_name);
                if (field.description) |desc| {
                    allocator.free(desc);
                }
            }
            self.fields.deinit();

            for (self.nested_interfaces.items) |*nested| {
                nested.deinit(allocator);
            }
            self.nested_interfaces.deinit();
        }
    };

    pub fn init(allocator: std.mem.Allocator, options: AnalyzerOptions) JsonAnalyzer {
        return JsonAnalyzer{
            .allocator = allocator,
            .options = options,
        };
    }

    /// Extract schema from JSON AST
    pub fn extractSchema(self: *Self, ast: AST) !JsonSchema {
        const root = &ast.root;
        return self.analyzeNode(root, 0);
    }

    /// Generate statistics about JSON structure
    pub fn generateStatistics(self: *Self, ast: AST) !JsonStatistics {
        var stats = JsonStatistics{
            .max_depth = 0,
            .total_keys = 0,
            .total_values = 0,
            .type_counts = .{},
            .size_bytes = 0,
            .complexity_score = 0.0,
        };

        const root = &ast.root;
        self.calculateStatistics(root, 0, &stats);

        // Calculate complexity score
        stats.complexity_score = self.calculateComplexity(&stats);

        return stats;
    }

    /// Generate TypeScript interface from JSON structure
    pub fn generateTypeScriptInterface(self: *Self, ast: AST, interface_name: []const u8) !TypeScriptInterface {
        const schema = try self.extractSchema(ast);
        defer {
            var mutable_schema = schema;
            mutable_schema.deinit(self.allocator);
        }

        return self.schemaToTypeScript(schema, interface_name);
    }

    /// Extract symbols from JSON structure
    pub fn extractSymbols(self: *Self, ast: AST) ![]Symbol {
        var symbols = std.ArrayList(Symbol).init(self.allocator);
        defer symbols.deinit();

        var root = ast.root;
        try self.extractSymbolsFromNode(&root, &symbols, "");

        return symbols.toOwnedSlice();
    }

    fn analyzeNode(self: *Self, node: *const Node, depth: u32) anyerror!JsonSchema {
        if (depth > self.options.max_schema_depth) {
            return JsonSchema.init(self.allocator, .any);
        }

        return switch (node.rule_id) {
            JsonRules.string_literal => blk: {
                var schema = JsonSchema.init(self.allocator, .string);
                if (node.text.len > 0) {
                    try schema.examples.append(try self.allocator.dupe(u8, node.text));
                }
                break :blk schema;
            },
            JsonRules.number_literal => blk: {
                var schema = JsonSchema.init(self.allocator, .number);
                if (node.text.len > 0) {
                    try schema.examples.append(try self.allocator.dupe(u8, node.text));
                }
                break :blk schema;
            },
            JsonRules.boolean_literal => blk: {
                var schema = JsonSchema.init(self.allocator, .boolean);
                if (node.text.len > 0) {
                    try schema.examples.append(try self.allocator.dupe(u8, node.text));
                }
                break :blk schema;
            },
            JsonRules.null_literal => JsonSchema.init(self.allocator, .null),
            JsonRules.object => self.analyzeObject(node, depth),
            JsonRules.array => self.analyzeArray(node, depth),
            else => JsonSchema.init(self.allocator, .any),
        };
    }

    fn analyzeObject(self: *Self, node: *const Node, depth: u32) !JsonSchema {
        var schema = JsonSchema.init(self.allocator, .object);
        schema.properties = std.HashMap([]const u8, JsonSchema, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(self.allocator);

        const members = node.children;
        if (members.len == 0) return schema;

        for (members) |member| {
            if (member.rule_id != JsonRules.member) continue;
            const member_children = member.children;
            if (member_children.len < 2) continue;

            const key_node = member_children[0];
            const value_node = member_children[1];

            // Extract key name
            const key_value = key_node.text;
            const key_name = if (key_value.len >= 2 and key_value[0] == '"' and key_value[key_value.len - 1] == '"')
                key_value[1 .. key_value.len - 1]
            else
                key_value;

            const owned_key = try self.allocator.dupe(u8, key_name);
            const value_schema = try self.analyzeNode(&value_node, depth + 1);

            try schema.properties.?.put(owned_key, value_schema);
        }

        return schema;
    }

    fn analyzeArray(self: *Self, node: *const Node, depth: u32) !JsonSchema {
        var schema = JsonSchema.init(self.allocator, .array);

        const elements = node.children;
        if (elements.len == 0) return schema;

        if (elements.len == 0) {
            // Empty array - infer as any[]
            schema.items = try self.allocator.create(JsonSchema);
            schema.items.?.* = JsonSchema.init(self.allocator, .any);
            return schema;
        }

        if (self.options.infer_array_types) {
            // Analyze first element to determine array type
            const first_element_schema = try self.analyzeNode(&elements[0], depth + 1);

            // Check if all elements have the same type
            var uniform_type = true;
            for (elements[1..]) |element| {
                const element_schema = try self.analyzeNode(&element, depth + 1);
                if (element_schema.schema_type != first_element_schema.schema_type) {
                    uniform_type = false;
                    var mutable_element_schema = element_schema;
                    mutable_element_schema.deinit(self.allocator);
                    break;
                }
                var mutable_element_schema = element_schema;
                mutable_element_schema.deinit(self.allocator);
            }

            if (uniform_type) {
                schema.items = try self.allocator.create(JsonSchema);
                schema.items.?.* = first_element_schema;
            } else {
                // Mixed types - use any
                var mutable_first_schema = first_element_schema;
                mutable_first_schema.deinit(self.allocator);
                schema.items = try self.allocator.create(JsonSchema);
                schema.items.?.* = JsonSchema.init(self.allocator, .any);
            }
        } else {
            schema.items = try self.allocator.create(JsonSchema);
            schema.items.?.* = JsonSchema.init(self.allocator, .any);
        }

        return schema;
    }

    fn calculateStatistics(self: *Self, node: *const Node, _: u32, stats: *JsonStatistics) void {
        // TODO: Implement proper statistics collection
        stats.total_values = 1; // Placeholder

        // Calculate statistics manually for now
        _ = self;
        
        // Calculate max depth
        stats.max_depth = calculateDepth(node, 0);
    }

    fn calculateDepth(node: *const Node, current_depth: u32) u32 {
        var max = current_depth;
        for (node.children) |child| {
            const child_depth = calculateDepth(&child, current_depth + 1);
            max = @max(max, child_depth);
        }
        return max;
    }

    fn calculateComplexity(_: *Self, stats: *JsonStatistics) f32 {
        // Simple complexity metric based on various factors
        var complexity: f32 = 0.0;

        // Depth contributes to complexity
        complexity += @as(f32, @floatFromInt(stats.max_depth)) * 2.0;

        // Number of objects and arrays contribute
        complexity += @as(f32, @floatFromInt(stats.type_counts.objects)) * 1.5;
        complexity += @as(f32, @floatFromInt(stats.type_counts.arrays)) * 1.2;

        // Total keys contribute
        complexity += @as(f32, @floatFromInt(stats.total_keys)) * 0.5;

        // Size contributes logarithmically
        if (stats.size_bytes > 0) {
            complexity += std.math.log(f32, std.math.e, @as(f32, @floatFromInt(stats.size_bytes)));
        }

        return complexity;
    }

    fn schemaToTypeScript(self: *Self, schema: JsonSchema, interface_name: []const u8) !TypeScriptInterface {
        var interface = TypeScriptInterface{
            .name = try self.allocator.dupe(u8, interface_name),
            .fields = std.ArrayList(TypeScriptInterface.Field).init(self.allocator),
            .nested_interfaces = std.ArrayList(TypeScriptInterface).init(self.allocator),
        };

        if (schema.schema_type == .object and schema.properties != null) {
            var prop_iter = schema.properties.?.iterator();
            while (prop_iter.next()) |entry| {
                const field_name = entry.key_ptr.*;
                const field_schema = entry.value_ptr.*;

                const type_name = try self.schemaTypeToTypeScript(field_schema);

                try interface.fields.append(TypeScriptInterface.Field{
                    .name = try self.allocator.dupe(u8, field_name),
                    .type_name = type_name,
                    .optional = field_schema.nullable,
                    .description = null,
                });
            }
        }

        return interface;
    }

    fn schemaTypeToTypeScript(self: *Self, schema: JsonSchema) ![]const u8 {
        return switch (schema.schema_type) {
            .string => try self.allocator.dupe(u8, "string"),
            .number => try self.allocator.dupe(u8, "number"),
            .boolean => try self.allocator.dupe(u8, "boolean"),
            .null => try self.allocator.dupe(u8, "null"),
            .object => try self.allocator.dupe(u8, "object"), // Could be more specific
            .array => {
                if (schema.items) |items| {
                    const item_type = try self.schemaTypeToTypeScript(items.*);
                    defer self.allocator.free(item_type);
                    return try std.fmt.allocPrint(self.allocator, "{s}[]", .{item_type});
                }
                return try self.allocator.dupe(u8, "any[]");
            },
            .any => try self.allocator.dupe(u8, "any"),
        };
    }

    fn extractSymbolsFromNode(self: *Self, node: *Node, symbols: *std.ArrayList(Symbol), path: []const u8) !void {
        // Create visitor context with path tracking
        const VisitorContext = struct {
            allocator: std.mem.Allocator,
            symbols: *std.ArrayList(Symbol),
            current_path: []const u8,
        };

        var context = VisitorContext{
            .allocator = self.allocator,
            .symbols = symbols,
            .current_path = path,
        };

        const visitor = struct {
            fn visit(n: *const Node, ctx: ?*anyopaque) anyerror!bool {
                const vis_ctx = @as(*VisitorContext, @ptrCast(@alignCast(ctx.?)));

                // Check rule_name instead of node_type enum
                switch (n.rule_id) {
                    JsonRules.object => {
                        try vis_ctx.symbols.append(Symbol{
                            .name = try vis_ctx.allocator.dupe(u8, if (vis_ctx.current_path.len == 0) "root" else vis_ctx.current_path),
                            .kind = .struct_,
                            .range = Span.init(n.start_position, n.end_position),
                            .signature = null,
                            .documentation = null,
                        });

                        // Process members using ASTUtils for field extraction
                        for (n.children) |member| {
                            if (member.rule_id != JsonRules.member) continue;
                            if (member.children.len < 2) continue;

                            const key_node = member.children[0];
                            const value_node = member.children[1];

                            const key_value = key_node.text;
                            const key_name = if (key_value.len >= 2 and key_value[0] == '"' and key_value[key_value.len - 1] == '"')
                                key_value[1 .. key_value.len - 1]
                            else
                                key_value;

                            const new_path = if (vis_ctx.current_path.len == 0)
                                try vis_ctx.allocator.dupe(u8, key_name)
                            else
                                try std.fmt.allocPrint(vis_ctx.allocator, "{s}.{s}", .{ vis_ctx.current_path, key_name });
                            
                            // Update context for recursion
                            var child_context = VisitorContext{
                                .allocator = vis_ctx.allocator,
                                .symbols = vis_ctx.symbols,
                                .current_path = new_path,
                            };
                            
                            // Recursively visit value node with new path
                            var traversal = ASTTraversal.init(vis_ctx.allocator);
                            try traversal.walk(&value_node, visit, &child_context, .depth_first_pre);
                            
                            vis_ctx.allocator.free(new_path);
                        }
                        return false; // Don't continue automatic traversal, we handled children
                    },
                    JsonRules.array => {
                    try vis_ctx.symbols.append(Symbol{
                        .name = try vis_ctx.allocator.dupe(u8, if (vis_ctx.current_path.len == 0) "root" else vis_ctx.current_path),
                        .kind = .variable,
                        .range = Span.init(n.start_position, n.end_position),
                        .signature = try vis_ctx.allocator.dupe(u8, "array"),
                        .documentation = null,
                    });
                        return true; // Continue traversal for array elements
                    },
                    JsonRules.string_literal,
                    JsonRules.number_literal,
                    JsonRules.boolean_literal,
                    JsonRules.null_literal => {
                        const type_name = switch (n.rule_id) {
                            JsonRules.string_literal => "string",
                            JsonRules.number_literal => "number",
                            JsonRules.boolean_literal => "boolean",
                            JsonRules.null_literal => "null",
                            else => unreachable,
                        };

                        try vis_ctx.symbols.append(Symbol{
                            .name = try vis_ctx.allocator.dupe(u8, if (vis_ctx.current_path.len == 0) "root" else vis_ctx.current_path),
                            .kind = .property,
                            .range = Span.init(n.start_position, n.end_position),
                            .signature = try vis_ctx.allocator.dupe(u8, type_name),
                            .documentation = null,
                        });
                        return true;
                    },
                    else => return true, // Continue for other node types
                }
            }
        }.visit;

        // Use traversal to walk the tree
        var traversal = ASTTraversal.init(self.allocator);
        try traversal.walk(node, visitor, &context, .depth_first_pre);
    }
};

// Tests
const testing = std.testing;
const JsonLexer = @import("lexer.zig").JsonLexer;
const JsonParser = @import("parser.zig").JsonParser;

test "JSON analyzer - schema extraction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = "{\"name\": \"Alice\", \"age\": 30, \"active\": true}";

    var lexer = JsonLexer.init(allocator, input, .{});
    defer lexer.deinit();
    const tokens = try lexer.tokenize();

    var parser = JsonParser.init(allocator, tokens, .{});
    defer parser.deinit();
    var ast = try parser.parse();
    defer ast.deinit();

    var analyzer = JsonAnalyzer.init(allocator, .{});
    var schema = try analyzer.extractSchema(ast);
    defer schema.deinit(allocator);

    // Should be object type with properties
    try testing.expectEqual(JsonAnalyzer.JsonSchema.SchemaType.object, schema.schema_type);
    try testing.expect(schema.properties != null);
    try testing.expectEqual(@as(usize, 3), schema.properties.?.count());
}

test "JSON analyzer - statistics" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = "[1, 2, {\"nested\": true}]";

    var lexer = JsonLexer.init(allocator, input, .{});
    defer lexer.deinit();
    const tokens = try lexer.tokenize();

    var parser = JsonParser.init(allocator, tokens, .{});
    defer parser.deinit();
    var ast = try parser.parse();
    defer ast.deinit();

    var analyzer = JsonAnalyzer.init(allocator, .{});
    const stats = try analyzer.generateStatistics(ast);

    // Should have correct type counts
    try testing.expectEqual(@as(u32, 2), stats.type_counts.numbers);
    try testing.expectEqual(@as(u32, 1), stats.type_counts.booleans);
    try testing.expectEqual(@as(u32, 1), stats.type_counts.objects);
    try testing.expectEqual(@as(u32, 1), stats.type_counts.arrays);
}

test "JSON analyzer - TypeScript interface generation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = "{\"name\": \"Alice\", \"age\": 30}";

    var lexer = JsonLexer.init(allocator, input, .{});
    defer lexer.deinit();
    const tokens = try lexer.tokenize();

    var parser = JsonParser.init(allocator, tokens, .{});
    defer parser.deinit();
    var ast = try parser.parse();
    defer ast.deinit();

    var analyzer = JsonAnalyzer.init(allocator, .{});
    var interface = try analyzer.generateTypeScriptInterface(ast, "User");
    defer interface.deinit(allocator);

    // Should have interface name and fields
    try testing.expectEqualStrings("User", interface.name);
    try testing.expectEqual(@as(usize, 2), interface.fields.items.len);
}
