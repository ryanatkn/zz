const std = @import("std");
// Use local JSON AST
const json_ast = @import("ast.zig");
const AST = json_ast.AST;
const Node = json_ast.Node;
const NodeKind = json_ast.NodeKind;
const Span = @import("../../span/span.zig").Span;
const Walker = @import("../../ast/walker.zig").Walker(Node);

/// Symbol from semantic analysis (local to JSON)
pub const Symbol = struct {
    name: []const u8,
    kind: SymbolKind,
    range: Span,
    signature: ?[]const u8 = null,
    documentation: ?[]const u8 = null,

    pub const SymbolKind = enum {
        property,
        array_element,
        object,
        array,
        string,
        number,
        boolean,
        null_value,
    };
};

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
        const root = ast.root;
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

        const root = ast.root;
        self.calculateStatistics(root, 0, &stats);

        // Calculate size bytes by summing up text lengths
        self.calculateSizeBytes(root, &stats);

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

        try self.extractSymbolsFromNode(ast.root, &symbols, "");

        return symbols.toOwnedSlice();
    }

    fn analyzeNode(self: *Self, node: *const Node, depth: u32) anyerror!JsonSchema {
        if (depth > self.options.max_schema_depth) {
            return JsonSchema.init(self.allocator, .any);
        }

        return switch (node.*) {
            .string => |n| blk: {
                var schema = JsonSchema.init(self.allocator, .string);
                try schema.examples.append(try self.allocator.dupe(u8, n.value));
                break :blk schema;
            },
            .number => |n| blk: {
                var schema = JsonSchema.init(self.allocator, .number);
                try schema.examples.append(try self.allocator.dupe(u8, n.raw));
                break :blk schema;
            },
            .boolean => |n| blk: {
                var schema = JsonSchema.init(self.allocator, .boolean);
                try schema.examples.append(try self.allocator.dupe(u8, if (n.value) "true" else "false"));
                break :blk schema;
            },
            .null => JsonSchema.init(self.allocator, .null),
            .object => self.analyzeObject(node, depth),
            .array => self.analyzeArray(node, depth),
            else => JsonSchema.init(self.allocator, .any),
        };
    }

    fn analyzeObject(self: *Self, node: *const Node, depth: u32) !JsonSchema {
        var schema = JsonSchema.init(self.allocator, .object);
        schema.properties = std.HashMap([]const u8, JsonSchema, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(self.allocator);

        const object_node = node.object;
        const properties = object_node.properties;
        if (properties.len == 0) return schema;

        for (properties) |property| {
            if (property != .property) continue;
            const prop_node = property.property;

            // Extract key name from the key node (should be a string)
            const key_name = if (prop_node.key.* == .string)
                prop_node.key.string.value
            else
                "unknown"; // fallback

            const owned_key = try self.allocator.dupe(u8, key_name);
            const value_schema = try self.analyzeNode(prop_node.value, depth + 1);

            try schema.properties.?.put(owned_key, value_schema);
        }

        return schema;
    }

    fn analyzeArray(self: *Self, node: *const Node, depth: u32) !JsonSchema {
        var schema = JsonSchema.init(self.allocator, .array);

        const array_node = node.array;
        const elements = array_node.elements;
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

    fn calculateStatistics(self: *Self, node: *const Node, depth: u32, stats: *JsonStatistics) void {

        // Update max depth
        stats.max_depth = @max(stats.max_depth, depth);

        // Count node types based on node union
        switch (node.*) {
            .string => {
                stats.type_counts.strings += 1;
                stats.total_values += 1;
            },
            .number => {
                stats.type_counts.numbers += 1;
                stats.total_values += 1;
            },
            .boolean => {
                stats.type_counts.booleans += 1;
                stats.total_values += 1;
            },
            .null => {
                stats.type_counts.nulls += 1;
                stats.total_values += 1;
            },
            .object => {
                stats.type_counts.objects += 1;
                stats.total_values += 1;
            },
            .array => {
                stats.type_counts.arrays += 1;
                stats.total_values += 1;
            },
            .property => {
                // Property nodes contain key-value pairs, count the key
                stats.total_keys += 1;
            },
            else => {
                // Other node types (error recovery, etc.)
            },
        }

        // Recursively process all children
        for (node.children()) |child| {
            self.calculateStatistics(&child, depth + 1, stats);
        }
    }

    fn calculateSizeBytes(self: *Self, node: *const Node, stats: *JsonStatistics) void {

        // Add the size based on node span
        const span = node.span();
        stats.size_bytes += @intCast(span.end - span.start);

        // Recursively process children
        for (node.children()) |child| {
            self.calculateSizeBytes(&child, stats);
        }
    }

    fn calculateDepth(node: *const Node, current_depth: u32) u32 {
        var max = current_depth;
        for (node.children()) |child| {
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
        // Use simplified traversal for symbol extraction
        _ = path; // TODO: Use path for hierarchical symbol names
        try self.extractSymbolsBasic(node, symbols);
    }

    /// Basic symbol extraction without complex walker
    fn extractSymbolsBasic(self: *Self, node: *const Node, symbols: *std.ArrayList(Symbol)) !void {
        switch (node.*) {
            .object => |obj| {
                try symbols.append(Symbol{
                    .name = try self.allocator.dupe(u8, "object"),
                    .kind = .object,
                    .range = node.span(),
                    .signature = null,
                    .documentation = null,
                });

                // Process properties
                for (obj.properties) |property| {
                    if (property == .property) {
                        const prop_node = property.property;
                        if (prop_node.key.* == .string) {
                            const key_name = prop_node.key.string.value;
                            try symbols.append(Symbol{
                                .name = try self.allocator.dupe(u8, key_name),
                                .kind = .property,
                                .range = prop_node.key.span(),
                                .signature = null,
                                .documentation = null,
                            });
                            // Recursively process the value
                            try self.extractSymbolsBasic(prop_node.value, symbols);
                        }
                    }
                }
            },
            .array => |arr| {
                try symbols.append(Symbol{
                    .name = try self.allocator.dupe(u8, "array"),
                    .kind = .array,
                    .range = node.span(),
                    .signature = null,
                    .documentation = null,
                });

                // Process elements
                for (arr.elements) |element| {
                    try self.extractSymbolsBasic(&element, symbols);
                }
            },
            .string, .number, .boolean, .null => {
                const type_name = switch (node.*) {
                    .string => "string",
                    .number => "number",
                    .boolean => "boolean",
                    .null => "null",
                    else => unreachable,
                };

                try symbols.append(Symbol{
                    .name = try self.allocator.dupe(u8, type_name),
                    .kind = switch (node.*) {
                        .string => .string,
                        .number => .number,
                        .boolean => .boolean,
                        .null => .null_value,
                        else => unreachable,
                    },
                    .range = node.span(),
                    .signature = null,
                    .documentation = null,
                });
            },
            else => {
                // Handle other node types like root, property, error
            },
        }
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

    var lexer = JsonLexer.init(allocator);
    defer lexer.deinit();
    const tokens = try lexer.batchTokenize(allocator, input);

    var parser = JsonParser.init(allocator, tokens, input, .{});
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

    var lexer = JsonLexer.init(allocator);
    defer lexer.deinit();
    const tokens = try lexer.batchTokenize(allocator, input);

    var parser = JsonParser.init(allocator, tokens, input, .{});
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

    var lexer = JsonLexer.init(allocator);
    defer lexer.deinit();
    const tokens = try lexer.batchTokenize(allocator, input);

    var parser = JsonParser.init(allocator, tokens, input, .{});
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
