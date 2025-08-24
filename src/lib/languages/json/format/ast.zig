/// JSON AST Formatter - Direct AST traversal formatting
///
/// Formats JSON by traversing the AST directly, enabling features like key sorting
/// Performance target: <0.5ms for 10KB JSON
const std = @import("std");
const unpackSpan = @import("../../../span/mod.zig").unpackSpan;

// For compatibility with existing interface
const json_ast = @import("../ast/mod.zig");
const AST = json_ast.AST;

/// High-performance JSON formatter with AST traversal
pub const Formatter = struct {
    allocator: std.mem.Allocator,
    options: FormatOptions,
    output: std.ArrayList(u8),
    source: []const u8,
    indent_level: u32,
    line_position: u32,

    const Self = @This();

    pub const FormatOptions = struct {
        // Basic formatting
        indent_size: u32 = 2,
        indent_style: IndentStyle = .space,
        line_width: u32 = 80,
        preserve_newlines: bool = false,

        // JSON-specific options
        compact_objects: bool = false,
        compact_arrays: bool = false,
        sort_keys: bool = false,
        trailing_comma: bool = false,
        quote_style: QuoteStyle = .double,
        space_after_colon: bool = true,
        space_after_comma: bool = true,

        // Compact mode overrides
        force_compact: bool = false,
        force_multiline: bool = false,

        pub const IndentStyle = enum { space, tab };
        pub const QuoteStyle = enum { single, double, preserve };
    };

    pub fn init(allocator: std.mem.Allocator, options: FormatOptions) Formatter {
        return Formatter{
            .allocator = allocator,
            .options = options,
            .output = std.ArrayList(u8).init(allocator),
            .source = "",
            .indent_level = 0,
            .line_position = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.output.deinit();
    }

    /// Format JSON AST (direct AST traversal)
    pub fn format(self: *Self, ast: AST) ![]const u8 {
        self.source = ast.source;

        // Format from AST directly (no re-tokenization)
        try self.formatNode(ast.root);

        // Add final newline if not compact
        if (!self.options.force_compact) {
            try self.output.append('\n');
        }

        return self.output.toOwnedSlice();
    }

    /// Format JSON from source string directly (INTERNAL - use format(ast) instead)
    /// This method is package-internal to prevent inefficient double-parsing from external callers.
    /// Developers should parse once to get AST, then format that AST.
    /// Only used internally by formatJsonString convenience function.
    pub fn formatSource(self: *Self, source: []const u8) ![]const u8 {
        // Parse source to AST first, then format AST (avoids double tokenization)
        const json_mod = @import("../mod.zig");
        var ast = try json_mod.parse(self.allocator, source);
        defer ast.deinit();
        return self.format(ast);
    }

    /// Format a JSON AST node directly
    fn formatNode(self: *Self, node: *const json_ast.Node) anyerror!void {
        switch (node.*) {
            .string => |string_node| {
                const span = string_node.span;
                const text = self.source[span.start..span.end];
                try self.output.appendSlice(text);
                self.updateLinePosition(text.len);
            },
            .number => |number_node| {
                try self.output.appendSlice(number_node.raw);
                self.updateLinePosition(number_node.raw.len);
            },
            .boolean => |bool_node| {
                const text = if (bool_node.value) "true" else "false";
                try self.output.appendSlice(text);
                self.updateLinePosition(text.len);
            },
            .null => {
                try self.output.appendSlice("null");
                self.updateLinePosition(4);
            },
            .object => |object_node| {
                try self.formatObjectNode(object_node);
            },
            .array => |array_node| {
                try self.formatArrayNode(array_node);
            },
            .root => |root_node| {
                try self.formatNode(root_node.value);
            },
            else => {}, // Skip other node types
        }
    }

    /// Format an object node with optional key sorting
    fn formatObjectNode(self: *Self, object_node: json_ast.ObjectNode) !void {
        try self.output.append('{');
        self.updateLinePosition(1);

        // Check if object should be compact
        const should_compact = self.options.force_compact or
            (self.options.compact_objects and object_node.properties.len <= 3);

        if (!should_compact) {
            self.indent_level += 1;
        }

        // Extract property nodes and sort if requested
        const property_indices = try self.allocator.alloc(usize, object_node.properties.len);
        defer self.allocator.free(property_indices);

        // Initialize indices
        for (property_indices, 0..) |*idx, i| {
            idx.* = i;
        }

        // Sort indices by property key if requested
        if (self.options.sort_keys) {
            const SortContext = struct {
                properties: []json_ast.Node,

                pub fn lessThan(ctx: @This(), a_idx: usize, b_idx: usize) bool {
                    if (ctx.properties[a_idx] != .property or ctx.properties[b_idx] != .property) {
                        return false;
                    }
                    const a_prop = ctx.properties[a_idx].property;
                    const b_prop = ctx.properties[b_idx].property;

                    const key_a = a_prop.getKeyString() orelse return false;
                    const key_b = b_prop.getKeyString() orelse return true;
                    return std.mem.lessThan(u8, key_a, key_b);
                }
            };

            std.sort.pdq(usize, property_indices, SortContext{ .properties = object_node.properties }, SortContext.lessThan);
        }

        for (property_indices, 0..) |prop_idx, i| {
            const property_node = &object_node.properties[prop_idx];
            if (property_node.* != .property) continue; // Skip non-property nodes

            const property = property_node.property;

            // Handle property separator
            if (i > 0) {
                try self.output.append(',');
                if (self.options.space_after_comma and should_compact) {
                    try self.output.append(' ');
                    self.updateLinePosition(2);
                } else {
                    self.updateLinePosition(1);
                }
            }

            // Add newline and indent for multiline
            if (!should_compact) {
                try self.output.append('\n');
                try self.writeIndent();
                self.line_position = self.indent_level * self.options.indent_size;
            }

            // Format property key
            try self.formatNode(property.key);

            // Add colon separator
            try self.output.append(':');
            if (self.options.space_after_colon) {
                try self.output.append(' ');
                self.updateLinePosition(2);
            } else {
                self.updateLinePosition(1);
            }

            // Format property value
            try self.formatNode(property.value);
        }

        // Close object
        if (!should_compact and property_indices.len > 0) {
            self.indent_level -= 1;
            try self.output.append('\n');
            try self.writeIndent();
            self.line_position = self.indent_level * self.options.indent_size;
        }

        try self.output.append('}');
        self.updateLinePosition(1);
    }

    /// Format an array node
    fn formatArrayNode(self: *Self, array_node: json_ast.ArrayNode) !void {
        try self.output.append('[');
        self.updateLinePosition(1);

        // Check if array should be compact
        const should_compact = self.options.force_compact or
            (self.options.compact_arrays and array_node.elements.len <= 5);

        if (!should_compact) {
            self.indent_level += 1;
        }

        for (array_node.elements, 0..) |element, i| {
            // Handle element separator
            if (i > 0) {
                try self.output.append(',');
                if (self.options.space_after_comma and should_compact) {
                    try self.output.append(' ');
                    self.updateLinePosition(2);
                } else {
                    self.updateLinePosition(1);
                }
            }

            // Add newline and indent for multiline
            if (!should_compact) {
                try self.output.append('\n');
                try self.writeIndent();
                self.line_position = self.indent_level * self.options.indent_size;
            }

            // Format array element
            try self.formatNode(&element);
        }

        // Close array
        if (!should_compact and array_node.elements.len > 0) {
            self.indent_level -= 1;
            try self.output.append('\n');
            try self.writeIndent();
            self.line_position = self.indent_level * self.options.indent_size;
        }

        try self.output.append(']');
        self.updateLinePosition(1);
    }

    fn writeIndent(self: *Self) !void {
        const count = self.indent_level * self.options.indent_size;

        if (self.options.indent_style == .tab) {
            var i: u32 = 0;
            while (i < count) : (i += 1) {
                try self.output.append('\t');
            }
        } else {
            var i: u32 = 0;
            while (i < count) : (i += 1) {
                try self.output.append(' ');
            }
        }
    }

    fn updateLinePosition(self: *Self, len: usize) void {
        self.line_position += @intCast(len);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "JSON streaming formatter - simple values" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const inputs = [_][]const u8{
        "\"hello\"",
        "123",
        "true",
        "false",
        "null",
    };

    const expected = [_][]const u8{
        "\"hello\"\n",
        "123\n",
        "true\n",
        "false\n",
        "null\n",
    };

    for (inputs, expected) |input, expect| {
        var formatter = Formatter.init(allocator, .{});
        defer formatter.deinit();

        const output = try formatter.formatSource(input);
        defer allocator.free(output);

        try testing.expectEqualStrings(expect, output);
    }
}

test "JSON streaming formatter - compact object" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const input = "{\"name\":\"test\",\"value\":42}";

    var formatter = Formatter.init(allocator, .{ .force_compact = true });
    defer formatter.deinit();

    const output = try formatter.formatSource(input);
    defer allocator.free(output);

    try testing.expect(std.mem.indexOf(u8, output, "\n") == null or
        std.mem.lastIndexOf(u8, output, "\n").? == output.len - 1);
}
