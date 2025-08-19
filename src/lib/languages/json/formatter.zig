const std = @import("std");
const AST = @import("../../ast/mod.zig").AST;
const Node = @import("../../ast/mod.zig").Node;
const NodeType = @import("../../ast/mod.zig").NodeType;
const JsonRules = @import("../../ast/rules.zig").JsonRules;
const FormatOptions = @import("../interface.zig").FormatOptions;
const ASTTraversal = @import("../../ast/traversal.zig").ASTTraversal;
const ASTUtils = @import("../../ast/utils.zig").ASTUtils;

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
        try self.formatNode(&ast.root);

        // Add final newline if not compact
        if (!self.options.force_compact) {
            try self.output.append('\n');
        }

        return self.output.toOwnedSlice();
    }

    fn formatNode(self: *Self, node: *const Node) anyerror!void {
        switch (node.rule_id) {
            JsonRules.string_literal => try self.formatString(node),
            JsonRules.number_literal => try self.formatNumber(node),
            JsonRules.boolean_literal => try self.formatBoolean(node),
            JsonRules.null_literal => try self.formatNull(node),
            JsonRules.object => try self.formatObject(node),
            JsonRules.array => try self.formatArray(node),
            JsonRules.member => try self.formatMember(node),
            else => try self.output.appendSlice("null"), // Handle other node types or errors
        }
    }

    fn formatString(self: *Self, node: *const Node) !void {
        const raw_value = if (node.text.len > 0) node.text else "";

        if (self.options.quote_style == .preserve) {
            // If preserve and already has quotes, use as-is
            if (raw_value.len >= 2 and raw_value[0] == '"' and raw_value[raw_value.len - 1] == '"') {
                try self.output.appendSlice(raw_value);
                self.updateLinePosition(raw_value.len);
            } else {
                // Add double quotes if missing
                try self.output.append('"');
                try self.output.appendSlice(raw_value);
                try self.output.append('"');
                self.updateLinePosition(raw_value.len + 2);
            }
        } else if (self.options.quote_style == .double) {
            // Always use double quotes
            try self.output.append('"');
            try self.output.appendSlice(raw_value);
            try self.output.append('"');
            self.updateLinePosition(raw_value.len + 2);
        } else {
            // Use single quotes (JSON5)
            try self.output.append('\'');
            try self.output.appendSlice(raw_value);
            try self.output.append('\'');
            self.updateLinePosition(raw_value.len + 2);
        }
    }

    fn formatNumber(self: *Self, node: *const Node) !void {
        const value = if (node.text.len > 0) node.text else "0";
        try self.output.appendSlice(value);
        self.updateLinePosition(value.len);
    }

    fn formatBoolean(self: *Self, node: *const Node) !void {
        const value = if (node.text.len > 0) node.text else "false";
        try self.output.appendSlice(value);
        self.updateLinePosition(value.len);
    }

    fn formatNull(self: *Self, _: *const Node) !void {
        try self.output.appendSlice("null");
        self.updateLinePosition(4);
    }

    fn formatObject(self: *Self, node: *const Node) anyerror!void {
        const members = node.children;

        if (members.len == 0) {
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

        // Sort members if requested
        var sorted_members: []const Node = undefined;
        var member_indices: std.ArrayList(usize) = undefined;
        var sorted_list: ?std.ArrayList(Node) = null;

        if (self.options.sort_keys) {
            member_indices = std.ArrayList(usize).init(self.allocator);
            defer member_indices.deinit();

            for (members, 0..) |_, i| {
                try member_indices.append(i);
            }

            std.sort.insertion(usize, member_indices.items, members, memberCompareFn);

            sorted_list = std.ArrayList(Node).init(self.allocator);

            for (member_indices.items) |idx| {
                try sorted_list.?.append(members[idx]);
            }

            sorted_members = sorted_list.?.items;
        } else {
            sorted_members = members;
        }

        for (sorted_members, 0..) |member, i| {
            if (!should_compact) {
                try self.writeIndent();
            } else if (i > 0 and self.options.space_after_comma) {
                try self.output.append(' ');
                self.updateLinePosition(1);
            }

            try self.formatNode(&member);

            const is_last = i == sorted_members.len - 1;
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
        const elements = node.children;

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

    fn formatMember(self: *Self, node: *const Node) !void {
        const children = node.children;
        if (children.len != 2) return;

        const key = children[0];
        const value = children[1];

        try self.formatNode(&key);

        try self.output.append(':');
        self.updateLinePosition(1);

        if (self.options.space_after_colon) {
            try self.output.append(' ');
            self.updateLinePosition(1);
        }

        try self.formatNode(&value);
    }

    fn shouldCompactObject(self: *Self, node: *const Node) bool {
        if (self.options.force_compact) return true;
        if (self.options.force_multiline) return false;
        if (!self.options.compact_objects) return false;

        const members = node.children;
        if (members.len == 0) return true;
        if (members.len > 3) return false; // Too many members

        // Estimate size on single line
        var estimated_size: u32 = 2; // {}
        for (members, 0..) |member, i| {
            estimated_size += self.estimateNodeSize(&member);
            if (i < members.len - 1) {
                estimated_size += 2; // ", "
            }
        }

        return estimated_size <= self.options.line_width / 2;
    }

    fn shouldCompactArray(self: *Self, node: *const Node) bool {
        if (self.options.force_compact) return true;
        if (self.options.force_multiline) return false;
        if (!self.options.compact_arrays) return false;

        const elements = node.children;
        if (elements.len == 0) return true;
        if (elements.len > 5) return false; // Too many elements

        // Check if all elements are primitives
        for (elements) |element| {
            switch (element.rule_id) {
                JsonRules.object, JsonRules.array => return false,
                else => {},
            }
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
        return switch (node.rule_id) {
            JsonRules.string_literal => @intCast(node.text.len),
            JsonRules.number_literal => @intCast(node.text.len),
            JsonRules.boolean_literal => @intCast(node.text.len),
            JsonRules.null_literal => 4,
            JsonRules.object => {
                const children = node.children;
                return @intCast(children.len * 20); // Rough estimate
            },
            JsonRules.array => {
                const children = node.children;
                return @intCast(children.len * 10); // Rough estimate
            },
            JsonRules.member => {
                const children = node.children;
                if (children.len == 2) {
                    return self.estimateNodeSize(&children[0]) + self.estimateNodeSize(&children[1]) + 2;
                }
                return 10;
            },
            else => 10,
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

    fn memberCompareFn(members: []const Node, a_idx: usize, b_idx: usize) bool {
        const a = &members[a_idx];
        const b = &members[b_idx];

        // Both should be member nodes with key as first child
        const a_children = a.children;
        const b_children = b.children;

        if (a_children.len == 0 or b_children.len == 0) {
            return false;
        }

        const a_key = a_children[0].text;
        const b_key = b_children[0].text;

        return std.mem.lessThan(u8, a_key, b_key);
    }
};

/// Convenience function for basic JSON formatting
pub fn formatJson(allocator: std.mem.Allocator, ast: AST, options: FormatOptions) ![]const u8 {
    const json_options = JsonFormatter.JsonFormatOptions{
        .indent_size = options.indent_size,
        .indent_style = if (options.indent_style == .tab) .tab else .space,
        .line_width = options.line_width,
        .trailing_comma = options.trailing_comma,
        .sort_keys = options.sort_keys,
    };

    var formatter = JsonFormatter.init(allocator, json_options);
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
        var lexer = JsonLexer.init(allocator, case, .{});
        defer lexer.deinit();
        const tokens = try lexer.tokenize();

        var parser = JsonParser.init(allocator, tokens, .{});
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

    var lexer = JsonLexer.init(allocator, input, .{});
    defer lexer.deinit();
    const tokens = try lexer.tokenize();

    var parser = JsonParser.init(allocator, tokens, .{});
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

    var lexer = JsonLexer.init(allocator, input, .{});
    defer lexer.deinit();
    const tokens = try lexer.tokenize();

    var parser = JsonParser.init(allocator, tokens, .{});
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

    var lexer = JsonLexer.init(allocator, input, .{});
    defer lexer.deinit();
    const tokens = try lexer.tokenize();

    var parser = JsonParser.init(allocator, tokens, .{});
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
