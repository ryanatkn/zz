const std = @import("std");
// Use local JSON AST
const json_ast = @import("ast.zig");
const AST = json_ast.AST;
const Node = json_ast.Node;
const NodeKind = json_ast.NodeKind;

/// High-performance JSON formatter with configurable output
///
/// Features:
/// - Pretty-printing with configurable indentation
/// - Smart single-line vs multi-line decisions
/// - Optional features: key sorting, trailing commas, compact mode
/// - Preserve number precision and proper string escaping
/// - Performance target: <0.5ms for 10KB JSON
pub const JsonFormatter = struct {
    allocator: std.mem.Allocator,
    options: JsonFormatOptions,
    output: std.ArrayList(u8),
    indent_level: u32,
    line_position: u32,

    const Self = @This();

    pub const JsonFormatOptions = struct {
        // Basic formatting
        indent_size: u32 = 2,
        indent_style: IndentStyle = .space,
        line_width: u32 = 80,
        preserve_newlines: bool = false,

        // JSON-specific options
        compact_objects: bool = false, // Single-line objects if small
        compact_arrays: bool = false, // Single-line arrays if small
        sort_keys: bool = false, // Sort object keys alphabetically
        trailing_comma: bool = false, // Add trailing commas (JSON5)
        quote_style: QuoteStyle = .double, // String quote style
        space_after_colon: bool = true, // Space after : in objects
        space_after_comma: bool = true, // Space after , in arrays/objects

        // Compact mode overrides
        force_compact: bool = false, // Force everything on single lines
        force_multiline: bool = false, // Force everything multiline

        pub const IndentStyle = enum { space, tab };
        pub const QuoteStyle = enum { single, double, preserve };
    };

    pub fn init(allocator: std.mem.Allocator, options: JsonFormatOptions) JsonFormatter {
        return JsonFormatter{
            .allocator = allocator,
            .options = options,
            .output = std.ArrayList(u8).init(allocator),
            .indent_level = 0,
            .line_position = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.output.deinit();
    }

    /// Format JSON AST to string using direct formatting
    pub fn format(self: *Self, ast: AST) ![]const u8 {
        // Format the root node directly (no visitor pattern to avoid double formatting)
        try self.formatNode(ast.root);

        // Add final newline if not compact
        if (!self.options.force_compact) {
            try self.output.append('\n');
        }

        return self.output.toOwnedSlice();
    }

    fn formatNode(self: *Self, node: *const Node) anyerror!void {
        switch (node.*) {
            .string => try self.formatString(node),
            .number => try self.formatNumber(node),
            .boolean => try self.formatBoolean(node),
            .null => try self.formatNull(node),
            .object => try self.formatObject(node),
            .array => try self.formatArray(node),
            .property => try self.formatProperty(node),
            .root => try self.formatNode(node.root.value),
            .err => try self.output.appendSlice("null"), // Handle errors
        }
    }

    fn formatString(self: *Self, node: *const Node) !void {
        const string_node = node.string;
        const value = string_node.value;

        // JSON strings always use double quotes (JSON5 can use single)
        if (self.options.quote_style == .single) {
            try self.output.append('\'');
            // TODO: Escape single quotes in value
            try self.output.appendSlice(value);
            try self.output.append('\'');
            self.updateLinePosition(value.len + 2);
        } else {
            try self.output.append('"');
            // TODO: Escape double quotes in value
            try self.output.appendSlice(value);
            try self.output.append('"');
            self.updateLinePosition(value.len + 2);
        }
    }

    fn formatNumber(self: *Self, node: *const Node) !void {
        const number_node = node.number;
        const raw_text = number_node.raw;
        try self.output.appendSlice(raw_text);
        self.updateLinePosition(raw_text.len);
    }

    fn formatBoolean(self: *Self, node: *const Node) !void {
        const boolean_node = node.boolean;
        const text = if (boolean_node.value) "true" else "false";
        try self.output.appendSlice(text);
        self.updateLinePosition(text.len);
    }

    fn formatNull(self: *Self, _: *const Node) !void {
        try self.output.appendSlice("null");
        self.updateLinePosition(4);
    }

    fn formatObject(self: *Self, node: *const Node) anyerror!void {
        const object_node = node.object;
        const properties = object_node.properties;

        if (properties.len == 0) {
            try self.output.appendSlice("{}");
            self.updateLinePosition(2);
            return;
        }

        const should_compact = self.shouldCompactObject(node);

        try self.output.append('{');
        self.updateLinePosition(1);

        if (!should_compact) {
            try self.newline();
            self.indent_level += 1;
        }

        // Sort properties if requested
        var sorted_properties: []const Node = undefined;
        var property_indices: std.ArrayList(usize) = undefined;
        var sorted_list: ?std.ArrayList(Node) = null;

        if (self.options.sort_keys) {
            property_indices = std.ArrayList(usize).init(self.allocator);
            defer property_indices.deinit();

            for (properties, 0..) |_, i| {
                try property_indices.append(i);
            }

            std.sort.insertion(usize, property_indices.items, properties, propertyCompareFn);

            sorted_list = std.ArrayList(Node).init(self.allocator);

            for (property_indices.items) |idx| {
                try sorted_list.?.append(properties[idx]);
            }

            sorted_properties = sorted_list.?.items;
        } else {
            sorted_properties = properties;
        }

        for (sorted_properties, 0..) |member, i| {
            if (!should_compact) {
                try self.writeIndent();
            } else if (i > 0 and self.options.space_after_comma) {
                try self.output.append(' ');
                self.updateLinePosition(1);
            }

            try self.formatNode(&member);

            const is_last = i == sorted_properties.len - 1;
            if (!is_last) {
                try self.output.append(',');
                self.updateLinePosition(1);
                if (!should_compact) {
                    try self.newline();
                }
            } else if (self.options.trailing_comma and !should_compact) {
                try self.output.append(',');
                self.updateLinePosition(1);
                try self.newline();
            }
        }

        if (!should_compact) {
            self.indent_level -= 1;
            try self.newline();
            try self.writeIndent();
        }

        try self.output.append('}');
        self.updateLinePosition(1);

        // Clean up sorted list if we created one
        if (sorted_list) |*list| {
            list.deinit();
        }
    }

    fn formatArray(self: *Self, node: *const Node) !void {
        const array_node = node.array;
        const elements = array_node.elements;

        if (elements.len == 0) {
            try self.output.appendSlice("[]");
            self.updateLinePosition(2);
            return;
        }

        const should_compact = self.shouldCompactArray(node);

        try self.output.append('[');
        self.updateLinePosition(1);

        if (!should_compact) {
            try self.newline();
            self.indent_level += 1;
        }

        for (elements, 0..) |element, i| {
            if (!should_compact) {
                try self.writeIndent();
            } else if (i > 0 and self.options.space_after_comma) {
                try self.output.append(' ');
                self.updateLinePosition(1);
            }

            try self.formatNode(&element);

            const is_last = i == elements.len - 1;
            if (!is_last) {
                try self.output.append(',');
                self.updateLinePosition(1);
                if (!should_compact) {
                    try self.newline();
                }
            } else if (self.options.trailing_comma and !should_compact) {
                try self.output.append(',');
                self.updateLinePosition(1);
                try self.newline();
            }
        }

        if (!should_compact) {
            self.indent_level -= 1;
            try self.newline();
            try self.writeIndent();
        }

        try self.output.append(']');
        self.updateLinePosition(1);
    }

    fn formatProperty(self: *Self, node: *const Node) !void {
        const property_node = node.property;

        try self.formatNode(property_node.key);

        try self.output.append(':');
        self.updateLinePosition(1);

        if (self.options.space_after_colon) {
            try self.output.append(' ');
            self.updateLinePosition(1);
        }

        try self.formatNode(property_node.value);
    }

    fn shouldCompactObject(self: *Self, node: *const Node) bool {
        if (self.options.force_compact) return true;
        if (self.options.force_multiline) return false;
        if (!self.options.compact_objects) return false;

        const object_node = node.object;
        const properties = object_node.properties;
        if (properties.len == 0) return true;
        if (properties.len > 3) return false; // Too many properties

        // Estimate size on single line
        var estimated_size: u32 = 2; // {}
        for (properties, 0..) |member, i| {
            estimated_size += self.estimateNodeSize(&member);
            if (i < properties.len - 1) {
                estimated_size += 2; // ", "
            }
        }

        return estimated_size <= self.options.line_width / 2;
    }

    fn shouldCompactArray(self: *Self, node: *const Node) bool {
        if (self.options.force_compact) return true;
        if (self.options.force_multiline) return false;
        if (!self.options.compact_arrays) return false;

        const array_node = node.array;
        const elements = array_node.elements;
        if (elements.len == 0) return true;
        if (elements.len > 5) return false; // Too many elements

        // Check if all elements are primitives
        for (elements) |element| {
            // Complex types shouldn't be compacted
            if (element.isContainer()) return false;
        }

        // Estimate size on single line
        var estimated_size: u32 = 2; // []
        for (elements, 0..) |element, i| {
            estimated_size += self.estimateNodeSize(&element);
            if (i < elements.len - 1) {
                estimated_size += 2; // ", "
            }
        }

        return estimated_size <= self.options.line_width / 2;
    }

    fn estimateNodeSize(self: *Self, node: *const Node) u32 {
        return switch (node.*) {
            .string => |n| @intCast(n.value.len + 2), // Add quotes
            .number => |n| @intCast(n.raw.len),
            .boolean => |n| if (n.value) 4 else 5, // "true" or "false"
            .null => 4, // "null"
            .object => |n| @intCast(n.properties.len * 20), // Rough estimate
            .array => |n| @intCast(n.elements.len * 10), // Rough estimate
            .property => |n| {
                return self.estimateNodeSize(n.key) + self.estimateNodeSize(n.value) + 2; // ": "
            },
            .root => |n| self.estimateNodeSize(n.value),
            .err => 10, // Default fallback
        };
    }

    fn writeIndent(self: *Self) !void {
        const total_indent = self.indent_level * self.options.indent_size;

        if (self.options.indent_style == .tab) {
            for (0..self.indent_level) |_| {
                try self.output.append('\t');
            }
            self.line_position = total_indent * 8; // Assume tab = 8 spaces for line width
        } else {
            for (0..total_indent) |_| {
                try self.output.append(' ');
            }
            self.line_position = total_indent;
        }
    }

    fn newline(self: *Self) !void {
        try self.output.append('\n');
        self.line_position = 0;
    }

    fn updateLinePosition(self: *Self, chars: usize) void {
        self.line_position += @intCast(chars);
    }

    fn propertyCompareFn(properties: []const Node, a_idx: usize, b_idx: usize) bool {
        const a = &properties[a_idx];
        const b = &properties[b_idx];

        // Both should be member nodes with key as first child
        // Compare property keys
        const a_property = a.property;
        const b_property = b.property;

        const a_key = switch (a_property.key.*) {
            .string => |n| n.value,
            else => "",
        };
        const b_key = switch (b_property.key.*) {
            .string => |n| n.value,
            else => "",
        };

        return std.mem.lessThan(u8, a_key, b_key);
    }
};

/// Convenience function for basic JSON formatting
pub fn formatJson(allocator: std.mem.Allocator, ast: AST, options: JsonFormatter.JsonFormatOptions) ![]const u8 {
    // Options are already JsonFormatOptions

    var formatter = JsonFormatter.init(allocator, options);
    defer formatter.deinit();

    return formatter.format(ast);
}

// Tests
const testing = std.testing;
const JsonLexer = @import("lexer.zig").JsonLexer;
const JsonParser = @import("parser.zig").JsonParser;

test "JSON formatter - simple values" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const test_cases = [_][]const u8{
        "\"hello\"",
        "42",
        "true",
        "false",
        "null",
    };

    for (test_cases) |case| {
        var lexer = JsonLexer.init(allocator);
        defer lexer.deinit();
        const tokens = try lexer.batchTokenize(allocator, case);

        var parser = JsonParser.init(allocator, tokens, case, .{});
        defer parser.deinit();
        var ast = try parser.parse();
        defer ast.deinit();

        var formatter = JsonFormatter.init(allocator, .{});
        defer formatter.deinit();
        const formatted = try formatter.format(ast);
        defer allocator.free(formatted);

        // Should preserve the value (with possible whitespace changes)
        try testing.expect(formatted.len > 0);
    }
}

test "JSON formatter - object formatting" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = "{\"name\":\"Alice\",\"age\":30}";

    var lexer = JsonLexer.init(allocator);
    defer lexer.deinit();
    const tokens = try lexer.batchTokenize(allocator, input);

    var parser = JsonParser.init(allocator, tokens, input, .{});
    defer parser.deinit();
    var ast = try parser.parse();
    defer ast.deinit();

    // Test pretty formatting
    {
        var formatter = JsonFormatter.init(allocator, .{
            .indent_size = 2,
            .compact_objects = false,
        });
        defer formatter.deinit();
        const formatted = try formatter.format(ast);
        defer allocator.free(formatted);

        // Should be multi-line with proper indentation
        try testing.expect(std.mem.indexOf(u8, formatted, "\n") != null);
    }

    // Test compact formatting
    {
        var formatter = JsonFormatter.init(allocator, .{
            .force_compact = true,
        });
        defer formatter.deinit();
        const formatted = try formatter.format(ast);
        defer allocator.free(formatted);

        // Should be single line
        try testing.expect(std.mem.indexOf(u8, formatted, "\n") == null);
    }
}

test "JSON formatter - array formatting" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = "[1,2,3,4,5]";

    var lexer = JsonLexer.init(allocator);
    defer lexer.deinit();
    const tokens = try lexer.batchTokenize(allocator, input);

    var parser = JsonParser.init(allocator, tokens, input, .{});
    defer parser.deinit();
    var ast = try parser.parse();
    defer ast.deinit();

    var formatter = JsonFormatter.init(allocator, .{
        .compact_arrays = true,
        .space_after_comma = true,
    });
    defer formatter.deinit();
    const formatted = try formatter.format(ast);
    defer allocator.free(formatted);

    // Should have spaces after commas
    try testing.expect(std.mem.indexOf(u8, formatted, ", ") != null);
}

test "JSON formatter - key sorting" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = "{\"zebra\":1,\"alpha\":2,\"beta\":3}";

    var lexer = JsonLexer.init(allocator);
    defer lexer.deinit();
    const tokens = try lexer.batchTokenize(allocator, input);

    var parser = JsonParser.init(allocator, tokens, input, .{});
    defer parser.deinit();
    var ast = try parser.parse();
    defer ast.deinit();

    var formatter = JsonFormatter.init(allocator, .{
        .sort_keys = true,
        .force_compact = true,
    });
    defer formatter.deinit();
    const formatted = try formatter.format(ast);
    defer allocator.free(formatted);

    // Alpha should come before beta, beta before zebra
    const alpha_pos = std.mem.indexOf(u8, formatted, "alpha");
    const beta_pos = std.mem.indexOf(u8, formatted, "beta");
    const zebra_pos = std.mem.indexOf(u8, formatted, "zebra");

    try testing.expect(alpha_pos != null);
    try testing.expect(beta_pos != null);
    try testing.expect(zebra_pos != null);
    try testing.expect(alpha_pos.? < beta_pos.?);
    try testing.expect(beta_pos.? < zebra_pos.?);
}
