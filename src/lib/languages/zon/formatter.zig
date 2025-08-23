const std = @import("std");
// Use local ZON AST
const zon_ast = @import("ast.zig");
const AST = zon_ast.AST;
const Node = zon_ast.Node;
const NodeKind = zon_ast.NodeKind;

// Import lexer and parser for formatZonString
const ZonLexer = @import("lexer.zig").ZonLexer;
const ZonParser = @import("parser.zig").ZonParser;

/// High-performance ZON formatter with configurable output
///
/// Features:
/// - Pretty-printing with configurable indentation
/// - Smart single-line vs multi-line decisions for objects/arrays
/// - ZON-specific features: field names, trailing commas, comment preservation
/// - Performance target: <0.5ms for typical config files
pub const ZonFormatter = struct {
    allocator: std.mem.Allocator,
    options: ZonFormatOptions,
    output: std.ArrayList(u8),
    indent_level: u32,

    const Self = @This();

    pub const ZonFormatOptions = struct {
        // Basic formatting
        indent_size: u8 = 4,
        indent_style: IndentStyle = .space,
        line_width: u32 = 100,
        preserve_comments: bool = true,
        trailing_comma: bool = true,

        // ZON-specific options
        compact_small_objects: bool = true,
        compact_small_arrays: bool = true,
        space_around_equals: bool = true,
        max_compact_elements: u32 = 3,
        max_compact_width: u32 = 50,

        pub const IndentStyle = enum { space, tab };
    };

    pub fn init(allocator: std.mem.Allocator, options: ZonFormatOptions) ZonFormatter {
        return ZonFormatter{
            .allocator = allocator,
            .options = options,
            .output = std.ArrayList(u8).init(allocator),
            .indent_level = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.output.deinit();
    }

    /// Format ZON AST to string
    pub fn format(self: *Self, ast: AST) ![]const u8 {
        if (ast.root) |root| {
            try self.formatNode(root.*);
        }
        return self.output.toOwnedSlice();
    }

    fn formatNode(self: *Self, node: Node) std.mem.Allocator.Error!void {
        switch (node) {
            .string => |string_node| {
                try self.output.append('"');
                try self.output.appendSlice(string_node.value);
                try self.output.append('"');
            },
            .number => |number_node| {
                try self.output.appendSlice(number_node.raw);
            },
            .boolean => |boolean_node| {
                try self.output.appendSlice(if (boolean_node.value) "true" else "false");
            },
            .null => {
                try self.output.appendSlice("null");
            },
            .field_name => |field_name_node| {
                try self.output.append('.');
                try self.output.appendSlice(field_name_node.name);
            },
            .identifier => |identifier_node| {
                if (identifier_node.is_quoted) {
                    try self.output.appendSlice("@\"");
                    try self.output.appendSlice(identifier_node.name);
                    try self.output.append('"');
                } else {
                    try self.output.appendSlice(identifier_node.name);
                }
            },
            .object => |object_node| try self.formatObject(object_node.fields),
            .array => |array_node| try self.formatArray(array_node.elements),
            .field => |field_node| {
                try self.formatNode(field_node.name.*);
                if (self.options.space_around_equals) {
                    try self.output.appendSlice(" = ");
                } else {
                    try self.output.append('=');
                }
                try self.formatNode(field_node.value.*);
            },
            .root => |root_node| {
                try self.formatNode(root_node.value.*);
            },
            .err => {
                // Skip error nodes in formatting or show placeholder
                try self.output.appendSlice("/* error */");
            },
        }
    }

    fn formatObject(self: *Self, fields: []Node) std.mem.Allocator.Error!void {
        const should_compact = self.shouldCompactObject(fields);

        try self.output.appendSlice(".{");

        if (fields.len == 0) {
            try self.output.append('}');
            return;
        }

        if (should_compact) {
            try self.formatObjectCompact(fields);
        } else {
            try self.formatObjectMultiline(fields);
        }

        try self.output.append('}');
    }

    fn formatArray(self: *Self, elements: []Node) std.mem.Allocator.Error!void {
        const should_compact = self.shouldCompactArray(elements);

        try self.output.appendSlice(".{");

        if (elements.len == 0) {
            try self.output.append('}');
            return;
        }

        if (should_compact) {
            try self.formatArrayCompact(elements);
        } else {
            try self.formatArrayMultiline(elements);
        }

        try self.output.append('}');
    }

    fn formatObjectCompact(self: *Self, fields: []Node) std.mem.Allocator.Error!void {
        for (fields, 0..) |field, i| {
            if (i > 0) {
                try self.output.appendSlice(", ");
            } else {
                try self.output.append(' ');
            }
            try self.formatNode(field);
        }
        if (fields.len > 0) {
            try self.output.append(' ');
        }
    }

    fn formatObjectMultiline(self: *Self, fields: []Node) std.mem.Allocator.Error!void {
        try self.output.append('\n');
        self.indent_level += 1;

        for (fields, 0..) |field, i| {
            try self.writeIndent();
            try self.formatNode(field);

            if (i < fields.len - 1 or self.options.trailing_comma) {
                try self.output.append(',');
            }
            try self.output.append('\n');
        }

        self.indent_level -= 1;
        try self.writeIndent();
    }

    fn formatArrayCompact(self: *Self, elements: []Node) std.mem.Allocator.Error!void {
        for (elements, 0..) |element, i| {
            if (i > 0) {
                try self.output.appendSlice(", ");
            } else {
                try self.output.append(' ');
            }
            try self.formatNode(element);
        }
        if (elements.len > 0) {
            try self.output.append(' ');
        }
    }

    fn formatArrayMultiline(self: *Self, elements: []Node) std.mem.Allocator.Error!void {
        try self.output.append('\n');
        self.indent_level += 1;

        for (elements, 0..) |element, i| {
            try self.writeIndent();
            try self.formatNode(element);

            if (i < elements.len - 1 or self.options.trailing_comma) {
                try self.output.append(',');
            }
            try self.output.append('\n');
        }

        self.indent_level -= 1;
        try self.writeIndent();
    }

    fn shouldCompactObject(self: *Self, fields: []Node) bool {
        if (!self.options.compact_small_objects) return false;
        return fields.len <= self.options.max_compact_elements;
    }

    fn shouldCompactArray(self: *Self, elements: []Node) bool {
        if (!self.options.compact_small_arrays) return false;
        return elements.len <= self.options.max_compact_elements;
    }

    fn writeIndent(self: *Self) std.mem.Allocator.Error!void {
        const indent_char: u8 = if (self.options.indent_style == .space) ' ' else '\t';
        const indent_count = if (self.options.indent_style == .space)
            self.indent_level * self.options.indent_size
        else
            self.indent_level;

        var i: u32 = 0;
        while (i < indent_count) : (i += 1) {
            try self.output.append(indent_char);
        }
    }
};

/// Convenience function for formatting
pub fn format(allocator: std.mem.Allocator, ast: AST, options: ZonFormatter.ZonFormatOptions) ![]const u8 {
    var formatter = ZonFormatter.init(allocator, options);
    defer formatter.deinit();
    return formatter.format(ast);
}

pub fn formatZonString(allocator: std.mem.Allocator, zon_content: []const u8, options: ZonFormatter.ZonFormatOptions) ![]const u8 {
    // Parse the ZON content
    var lexer = ZonLexer.init(allocator);
    defer lexer.deinit();

    const tokens = try lexer.batchTokenize(allocator, zon_content);
    defer allocator.free(tokens);

    var parser = ZonParser.init(allocator, tokens, zon_content, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    // Format the AST
    return format(allocator, ast, options);
}
