const std = @import("std");
const AST = @import("../../parser/ast/mod.zig").AST;
const Node = @import("../../ast/mod.zig").Node;
const Span = @import("../../parser/foundation/types/span.zig").Span;

/// ZON analyzer for schema extraction and structural analysis
///
/// Features:
/// - Schema extraction from ZON data
/// - Type inference and analysis
/// - Symbol extraction for IDE integration
/// - Dependency analysis for build.zig.zon files
/// - Configuration validation and suggestions
/// - Performance optimized for config file analysis
pub const ZonAnalyzer = struct {
    allocator: std.mem.Allocator,
    options: ZonAnalysisOptions,

    const Self = @This();

    pub const ZonAnalysisOptions = struct {
        infer_types: bool = true, // Infer types from values
        extract_dependencies: bool = true, // Extract dependency information
        analyze_structure: bool = true, // Perform structural analysis
        suggest_optimizations: bool = false, // Suggest improvements
        collect_symbols: bool = true, // Collect symbols for IDE
    };

    pub const ZonSchema = struct {
        allocator: std.mem.Allocator,
        root_type: TypeInfo,
        symbols: std.ArrayList(Symbol),
        dependencies: std.ArrayList(Dependency),
        statistics: Statistics,

        pub fn deinit(self: *ZonSchema) void {
            self.root_type.deinit(self.allocator);
            for (self.symbols.items) |symbol| {
                symbol.deinit(self.allocator);
            }
            self.symbols.deinit();
            for (self.dependencies.items) |dep| {
                dep.deinit(self.allocator);
            }
            self.dependencies.deinit();
        }
    };

    pub const TypeInfo = struct {
        kind: TypeKind,
        name: ?[]const u8,
        fields: ?std.ArrayList(FieldInfo),
        element_type: ?*TypeInfo,
        nullable: bool,

        pub const TypeKind = enum {
            object,
            array,
            string,
            number,
            boolean,
            null_type,
            undefined_type,
            identifier,
            union_type,
            any,
        };

        pub fn deinit(self: TypeInfo, allocator: std.mem.Allocator) void {
            if (self.name) |name| {
                allocator.free(name);
            }
            if (self.fields) |fields| {
                for (fields.items) |field| {
                    field.deinit(allocator);
                }
                fields.deinit();
            }
            if (self.element_type) |elem_type| {
                elem_type.deinit(allocator);
                allocator.destroy(elem_type);
            }
        }
    };

    pub const FieldInfo = struct {
        name: []const u8,
        type_info: TypeInfo,
        required: bool,
        description: ?[]const u8,
        span: Span,

        pub fn deinit(self: FieldInfo, allocator: std.mem.Allocator) void {
            allocator.free(self.name);
            self.type_info.deinit(allocator);
            if (self.description) |desc| {
                allocator.free(desc);
            }
        }
    };

    pub const Symbol = struct {
        name: []const u8,
        kind: SymbolKind,
        span: Span,
        type_info: ?TypeInfo,
        value: ?[]const u8,

        pub const SymbolKind = enum {
            field,
            value,
            type_name,
            dependency,
        };

        pub fn deinit(self: Symbol, allocator: std.mem.Allocator) void {
            allocator.free(self.name);
            if (self.type_info) |type_info| {
                type_info.deinit(allocator);
            }
            if (self.value) |value| {
                allocator.free(value);
            }
        }
    };

    pub const Dependency = struct {
        name: []const u8,
        version: ?[]const u8,
        url: ?[]const u8,
        hash: ?[]const u8,
        span: Span,

        pub fn deinit(self: Dependency, allocator: std.mem.Allocator) void {
            allocator.free(self.name);
            if (self.version) |version| {
                allocator.free(version);
            }
            if (self.url) |url| {
                allocator.free(url);
            }
            if (self.hash) |hash| {
                allocator.free(hash);
            }
        }
    };

    pub const Statistics = struct {
        total_nodes: u32,
        max_depth: u32,
        object_count: u32,
        array_count: u32,
        field_count: u32,
        string_count: u32,
        number_count: u32,
        complexity_score: u32,
    };

    pub const ZigTypeDefinition = struct {
        allocator: std.mem.Allocator,
        name: []const u8,
        definition: []const u8,

        pub fn deinit(self: *ZigTypeDefinition) void {
            self.allocator.free(self.name);
            self.allocator.free(self.definition);
        }
    };

    pub fn init(allocator: std.mem.Allocator, options: ZonAnalysisOptions) ZonAnalyzer {
        return ZonAnalyzer{
            .allocator = allocator,
            .options = options,
        };
    }

    pub fn deinit(self: *Self) void {
        // ZonAnalyzer doesn't allocate anything itself, so no cleanup needed
        _ = self;
    }

    /// Extract schema from ZON AST
    pub fn extractSchema(self: *Self, ast: AST) !ZonSchema {
        var schema = ZonSchema{
            .allocator = self.allocator,
            .root_type = TypeInfo{
                .kind = .any,
                .name = null,
                .fields = null,
                .element_type = null,
                .nullable = false,
            },
            .symbols = std.ArrayList(Symbol).init(self.allocator),
            .dependencies = std.ArrayList(Dependency).init(self.allocator),
            .statistics = Statistics{
                .total_nodes = 0,
                .max_depth = 0,
                .object_count = 0,
                .array_count = 0,
                .field_count = 0,
                .string_count = 0,
                .number_count = 0,
                .complexity_score = 0,
            },
        };

        // Analyze the root node
        schema.root_type = try self.inferType(ast.root);

        // Collect symbols
        if (self.options.collect_symbols) {
            try self.collectSymbols(ast.root, &schema.symbols);
        }

        // Extract dependencies
        if (self.options.extract_dependencies) {
            try self.extractDependencies(ast.root, &schema.dependencies);
        }

        // Generate statistics
        if (self.options.analyze_structure) {
            schema.statistics = try self.generateStatistics(ast.root, 0);
        }

        return schema;
    }

    /// Generate Zig type definition from schema
    pub fn generateZigTypeDefinition(self: *Self, schema: ZonSchema, type_name: []const u8) !ZigTypeDefinition {
        var definition = std.ArrayList(u8).init(self.allocator);
        defer definition.deinit();

        try definition.appendSlice("pub const ");
        try definition.appendSlice(type_name);
        try definition.appendSlice(" = ");

        try self.writeZigType(&definition, schema.root_type, 0);

        try definition.appendSlice(";\n");

        return ZigTypeDefinition{
            .allocator = self.allocator,
            .name = try self.allocator.dupe(u8, type_name),
            .definition = try definition.toOwnedSlice(),
        };
    }

    /// Extract symbols for IDE integration
    pub fn extractSymbols(self: *Self, ast: AST) ![]Symbol {
        var symbols = std.ArrayList(Symbol).init(self.allocator);
        try self.collectSymbols(ast.root, &symbols);
        return symbols.toOwnedSlice();
    }

    /// Free symbols returned by extractSymbols
    pub fn freeSymbols(self: *Self, symbols: []Symbol) void {
        for (symbols) |symbol| {
            self.allocator.free(symbol.name);
            if (symbol.value) |value| {
                self.allocator.free(value);
            }
        }
        self.allocator.free(symbols);
    }

    /// Get analysis statistics
    pub fn generateStatistics(self: *Self, root_node: Node, depth: u32) !Statistics {
        var stats = Statistics{
            .total_nodes = 0,
            .max_depth = depth,
            .object_count = 0,
            .array_count = 0,
            .field_count = 0,
            .string_count = 0,
            .number_count = 0,
            .complexity_score = 0,
        };

        try self.analyzeNodeStatistics(root_node, &stats, depth);

        // Calculate complexity score
        stats.complexity_score = stats.total_nodes +
            (stats.max_depth * 2) +
            (stats.object_count * 3) +
            (stats.array_count * 2);

        return stats;
    }

    fn inferType(self: *Self, node: Node) std.mem.Allocator.Error!TypeInfo {
        switch (node.node_type) {
            .list => {
                if (std.mem.eql(u8, node.rule_name, "object")) {
                    return try self.inferObjectType(node);
                } else if (std.mem.eql(u8, node.rule_name, "array")) {
                    return try self.inferArrayType(node);
                } else {
                    return TypeInfo{
                        .kind = .any,
                        .name = null,
                        .fields = null,
                        .element_type = null,
                        .nullable = false,
                    };
                }
            },
            .terminal => {
                return try self.inferTerminalType(node);
            },
            .rule => {
                if (std.mem.eql(u8, node.rule_name, "field_assignment") and node.children.len >= 2) {
                    // Return the type of the value
                    return try self.inferType(node.children[1]);
                } else {
                    return TypeInfo{
                        .kind = .any,
                        .name = null,
                        .fields = null,
                        .element_type = null,
                        .nullable = false,
                    };
                }
            },
            else => {
                return TypeInfo{
                    .kind = .any,
                    .name = null,
                    .fields = null,
                    .element_type = null,
                    .nullable = false,
                };
            },
        }
    }

    fn inferObjectType(self: *Self, object_node: Node) !TypeInfo {
        var fields = std.ArrayList(FieldInfo).init(self.allocator);

        for (object_node.children) |child| {
            if (std.mem.eql(u8, child.rule_name, "field_assignment") and child.children.len >= 2) {
                const field_name_node = child.children[0];
                const value_node = if (child.children.len >= 3)
                    child.children[2] // field_name = value (with equals token)
                else
                    child.children[1]; // field_name value (no equals token)

                // Extract field name using utils function
                const zon_utils = @import("utils.zig");
                const field_name = zon_utils.extractFieldName(field_name_node.text);

                const field_type = try self.inferType(value_node);

                const field_info = FieldInfo{
                    .name = try self.allocator.dupe(u8, field_name),
                    .type_info = field_type,
                    .required = true, // ZON fields are typically required
                    .description = null,
                    .span = Span{ .start = field_name_node.start_position, .end = field_name_node.end_position },
                };

                try fields.append(field_info);
            }
        }

        return TypeInfo{
            .kind = .object,
            .name = null,
            .fields = fields,
            .element_type = null,
            .nullable = false,
        };
    }

    fn inferArrayType(self: *Self, array_node: Node) !TypeInfo {
        if (array_node.children.len == 0) {
            // Empty array - unknown element type
            return TypeInfo{
                .kind = .array,
                .name = null,
                .fields = null,
                .element_type = null,
                .nullable = false,
            };
        }

        // Infer element type from first element
        const first_element_type = try self.inferType(array_node.children[0]);

        // TODO: Could check if all elements have the same type
        const element_type = try self.allocator.create(TypeInfo);
        element_type.* = first_element_type;

        return TypeInfo{
            .kind = .array,
            .name = null,
            .fields = null,
            .element_type = element_type,
            .nullable = false,
        };
    }

    fn inferTerminalType(self: *Self, terminal_node: Node) !TypeInfo {
        _ = self;

        if (std.mem.eql(u8, terminal_node.rule_name, "string_literal")) {
            return TypeInfo{
                .kind = .string,
                .name = null,
                .fields = null,
                .element_type = null,
                .nullable = false,
            };
        } else if (std.mem.eql(u8, terminal_node.rule_name, "number_literal")) {
            return TypeInfo{
                .kind = .number,
                .name = null,
                .fields = null,
                .element_type = null,
                .nullable = false,
            };
        } else if (std.mem.eql(u8, terminal_node.rule_name, "boolean_literal")) {
            return TypeInfo{
                .kind = .boolean,
                .name = null,
                .fields = null,
                .element_type = null,
                .nullable = false,
            };
        } else if (std.mem.eql(u8, terminal_node.rule_name, "null_literal")) {
            return TypeInfo{
                .kind = .null_type,
                .name = null,
                .fields = null,
                .element_type = null,
                .nullable = true,
            };
        } else if (std.mem.eql(u8, terminal_node.rule_name, "undefined_literal")) {
            return TypeInfo{
                .kind = .undefined_type,
                .name = null,
                .fields = null,
                .element_type = null,
                .nullable = false,
            };
        } else if (std.mem.eql(u8, terminal_node.rule_name, "identifier") or
            std.mem.eql(u8, terminal_node.rule_name, "field_name"))
        {
            return TypeInfo{
                .kind = .identifier,
                .name = null,
                .fields = null,
                .element_type = null,
                .nullable = false,
            };
        } else {
            return TypeInfo{
                .kind = .any,
                .name = null,
                .fields = null,
                .element_type = null,
                .nullable = false,
            };
        }
    }

    fn collectSymbols(self: *Self, node: Node, symbols: *std.ArrayList(Symbol)) !void {
        switch (node.node_type) {
            .rule => {
                if (std.mem.eql(u8, node.rule_name, "field_assignment") and node.children.len >= 2) {
                    const field_name_node = node.children[0];
                    const value_node = if (node.children.len >= 3)
                        node.children[2] // field_name = value (with equals token)
                    else
                        node.children[1]; // field_name value (no equals token)

                    // Extract field name using utils function
                    const zon_utils = @import("utils.zig");
                    const field_name = zon_utils.extractFieldName(field_name_node.text);

                    const symbol = Symbol{
                        .name = try self.allocator.dupe(u8, field_name),
                        .kind = .field,
                        .span = Span{ .start = field_name_node.start_position, .end = field_name_node.end_position },
                        .type_info = try self.inferType(value_node),
                        .value = if (value_node.node_type == .terminal)
                            try self.allocator.dupe(u8, value_node.text)
                        else
                            null,
                    };

                    try symbols.append(symbol);
                }
            },
            .terminal => {
                if (std.mem.eql(u8, node.rule_name, "identifier")) {
                    const symbol = Symbol{
                        .name = try self.allocator.dupe(u8, node.text),
                        .kind = .value,
                        .span = Span{ .start = node.start_position, .end = node.end_position },
                        .type_info = try self.inferType(node),
                        .value = try self.allocator.dupe(u8, node.text),
                    };

                    try symbols.append(symbol);
                }
            },
            else => {},
        }

        // Recursively collect from children
        for (node.children) |child| {
            try self.collectSymbols(child, symbols);
        }
    }

    fn extractDependencies(self: *Self, root_node: Node, dependencies: *std.ArrayList(Dependency)) !void {
        // Look for dependencies field in build.zig.zon format
        for (root_node.children) |child| {
            if (std.mem.eql(u8, child.rule_name, "field_assignment") and child.children.len >= 2) {
                const field_name_node = child.children[0];
                const value_node = if (child.children.len >= 3)
                    child.children[2] // field_name = value (with equals token)
                else
                    child.children[1]; // field_name value (no equals token)

                // Extract field name using utils function
                const zon_utils = @import("utils.zig");
                const field_name = zon_utils.extractFieldName(field_name_node.text);

                if (std.mem.eql(u8, field_name, "dependencies") and
                    std.mem.eql(u8, value_node.rule_name, "object"))
                {
                    try self.extractDependenciesFromObject(value_node, dependencies);
                }
            }
        }
    }

    fn extractDependenciesFromObject(self: *Self, deps_object: Node, dependencies: *std.ArrayList(Dependency)) !void {
        const zon_utils = @import("utils.zig");

        for (deps_object.children) |child| {
            if (std.mem.eql(u8, child.rule_name, "field_assignment") and child.children.len >= 2) {
                const dep_name_node = child.children[0];
                const dep_value_node = if (child.children.len >= 3)
                    child.children[2] // field_name = value (with equals token)
                else
                    child.children[1]; // field_name value (no equals token)

                // Extract dependency name using utils function
                const dep_name = zon_utils.extractFieldName(dep_name_node.text);

                var dependency = Dependency{
                    .name = try self.allocator.dupe(u8, dep_name),
                    .version = null,
                    .url = null,
                    .hash = null,
                    .span = Span{ .start = dep_name_node.start_position, .end = dep_name_node.end_position },
                };

                // Extract dependency details from object
                if (std.mem.eql(u8, dep_value_node.rule_name, "object")) {
                    for (dep_value_node.children) |dep_field| {
                        if (std.mem.eql(u8, dep_field.rule_name, "field_assignment") and dep_field.children.len >= 2) {
                            const prop_name_node = dep_field.children[0];
                            const prop_value_node = if (dep_field.children.len >= 3)
                                dep_field.children[2] // field_name = value (with equals token)
                            else
                                dep_field.children[1]; // field_name value (no equals token)

                            // Extract property name using utils function
                            const prop_name = zon_utils.extractFieldName(prop_name_node.text);

                            if (std.mem.eql(u8, prop_name, "url") and
                                std.mem.eql(u8, prop_value_node.rule_name, "string_literal"))
                            {
                                dependency.url = try self.allocator.dupe(u8, prop_value_node.text);
                            } else if (std.mem.eql(u8, prop_name, "hash") and
                                std.mem.eql(u8, prop_value_node.rule_name, "string_literal"))
                            {
                                dependency.hash = try self.allocator.dupe(u8, prop_value_node.text);
                            } else if (std.mem.eql(u8, prop_name, "version") and
                                std.mem.eql(u8, prop_value_node.rule_name, "string_literal"))
                            {
                                dependency.version = try self.allocator.dupe(u8, prop_value_node.text);
                            }
                        }
                    }
                }

                try dependencies.append(dependency);
            }
        }
    }

    fn analyzeNodeStatistics(self: *Self, node: Node, stats: *Statistics, depth: u32) !void {
        stats.total_nodes += 1;
        stats.max_depth = @max(stats.max_depth, depth);

        switch (node.node_type) {
            .list => {
                if (std.mem.eql(u8, node.rule_name, "object")) {
                    stats.object_count += 1;
                } else if (std.mem.eql(u8, node.rule_name, "array")) {
                    stats.array_count += 1;
                }
            },
            .rule => {
                if (std.mem.eql(u8, node.rule_name, "field_assignment")) {
                    stats.field_count += 1;
                }
            },
            .terminal => {
                if (std.mem.eql(u8, node.rule_name, "string_literal")) {
                    stats.string_count += 1;
                } else if (std.mem.eql(u8, node.rule_name, "number_literal")) {
                    stats.number_count += 1;
                }
            },
            else => {},
        }

        // Recursively analyze children
        for (node.children) |child| {
            try self.analyzeNodeStatistics(child, stats, depth + 1);
        }
    }

    fn writeZigType(self: *Self, output: *std.ArrayList(u8), type_info: TypeInfo, indent: u32) !void {
        switch (type_info.kind) {
            .object => {
                try output.appendSlice("struct {\n");

                if (type_info.fields) |fields| {
                    for (fields.items) |field| {
                        // Add indentation
                        var i: u32 = 0;
                        while (i < (indent + 1) * 4) : (i += 1) {
                            try output.append(' ');
                        }

                        try output.appendSlice(field.name);
                        try output.appendSlice(": ");

                        if (field.required) {
                            try self.writeZigType(output, field.type_info, indent + 1);
                        } else {
                            try output.append('?');
                            try self.writeZigType(output, field.type_info, indent + 1);
                        }

                        try output.appendSlice(",\n");
                    }
                }

                // Add closing brace with proper indentation
                var i: u32 = 0;
                while (i < indent * 4) : (i += 1) {
                    try output.append(' ');
                }
                try output.append('}');
            },
            .array => {
                try output.append('[');
                try output.append(']');
                if (type_info.element_type) |elem_type| {
                    try self.writeZigType(output, elem_type.*, indent);
                } else {
                    try output.appendSlice("anytype");
                }
            },
            .string => try output.appendSlice("[]const u8"),
            .number => try output.appendSlice("i64"), // Could be more specific
            .boolean => try output.appendSlice("bool"),
            .null_type => try output.appendSlice("?anytype"),
            .undefined_type => try output.appendSlice("void"),
            .identifier => try output.appendSlice("anytype"),
            .any => try output.appendSlice("anytype"),
            else => try output.appendSlice("anytype"),
        }
    }
};

/// Convenience function for extracting ZON schema
pub fn extractSchema(allocator: std.mem.Allocator, ast: AST) !ZonAnalyzer.ZonSchema {
    var analyzer = ZonAnalyzer.init(allocator, .{});
    return analyzer.extractSchema(ast);
}

/// Extract schema from ZON string directly
pub fn extractSchemaFromString(allocator: std.mem.Allocator, zon_content: []const u8) !ZonAnalyzer.ZonSchema {
    // Import our lexer and parser
    const ZonLexer = @import("lexer.zig").ZonLexer;
    const ZonParser = @import("parser.zig").ZonParser;

    // Tokenize
    var lexer = ZonLexer.init(allocator, zon_content, .{});
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);

    // Parse
    var parser = ZonParser.init(allocator, tokens, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    // Analyze
    var analyzer = ZonAnalyzer.init(allocator, .{});
    return analyzer.extractSchema(ast);
}
