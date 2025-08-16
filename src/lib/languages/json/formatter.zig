const std = @import("std");
const ts = @import("tree-sitter");
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;


// Formatting implementation
fn formatValue(builder: *LineBuilder, value: std.json.Value, options: FormatterOptions) anyerror!void {
    switch (value) {
        .null => try builder.append("null"),
        .bool => |b| try builder.append(if (b) "true" else "false"),
        .integer => |i| {
            var buf: [32]u8 = undefined;
            const str = try std.fmt.bufPrint(&buf, "{d}", .{i});
            try builder.append(str);
        },
        .float => |f| {
            var buf: [32]u8 = undefined;
            const str = try std.fmt.bufPrint(&buf, "{d}", .{f});
            try builder.append(str);
        },
        .number_string => |s| try builder.append(s),
        .string => |s| {
            try builder.append("\"");
            try writeEscapedString(builder, s);
            try builder.append("\"");
        },
        .array => |arr| try formatArray(builder, arr, options),
        .object => |obj| try formatObject(builder, obj, options),
    }
}

fn formatArray(builder: *LineBuilder, array: std.json.Array, options: FormatterOptions) !void {
    if (array.items.len == 0) {
        try builder.append("[]");
        return;
    }

    // Check if array should be single-line
    const is_simple = isSimpleArray(array);
    const single_line = is_simple and !wouldExceedLineWidth(builder, array, options);

    try builder.append("[");

    if (!single_line) {
        try builder.newline();
        builder.indent();
    }

    for (array.items, 0..) |item, i| {
        if (!single_line) {
            try builder.appendIndent();
        } else if (i > 0) {
            try builder.append(" ");
        }

        try formatValue(builder, item, options);

        if (i < array.items.len - 1) {
            try builder.append(",");
        } else if (options.trailing_comma and !single_line) {
            try builder.append(",");
        }

        if (!single_line and i < array.items.len - 1) {
            try builder.newline();
        }
    }

    if (!single_line) {
        builder.dedent();
        try builder.newline();
        try builder.appendIndent();
    }

    try builder.append("]");
}

fn formatObject(builder: *LineBuilder, object: std.json.ObjectMap, options: FormatterOptions) !void {
    if (object.count() == 0) {
        try builder.append("{}");
        return;
    }

    // Collect and optionally sort keys
    var keys = std.ArrayList([]const u8).init(builder.allocator);
    defer keys.deinit();

    var iterator = object.iterator();
    while (iterator.next()) |entry| {
        try keys.append(entry.key_ptr.*);
    }

    if (options.sort_keys) {
        std.mem.sort([]const u8, keys.items, {}, struct {
            fn lessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
                return std.mem.lessThan(u8, lhs, rhs);
            }
        }.lessThan);
    }

    try builder.append("{");
    try builder.newline();
    builder.indent();

    for (keys.items, 0..) |key, i| {
        try builder.appendIndent();

        // Format key
        try builder.append("\"");
        try writeEscapedString(builder, key);
        try builder.append("\": ");

        // Format value
        const value = object.get(key).?;
        try formatValue(builder, value, options);

        if (i < keys.items.len - 1) {
            try builder.append(",");
        } else if (options.trailing_comma) {
            try builder.append(",");
        }

        try builder.newline();
    }

    builder.dedent();
    try builder.appendIndent();
    try builder.append("}");
}

// Helper functions for formatting
fn isSimpleArray(array: std.json.Array) bool {
    if (array.items.len > 3) return false;

    for (array.items) |item| {
        switch (item) {
            .object, .array => return false,
            else => {},
        }
    }
    return true;
}

fn wouldExceedLineWidth(builder: *LineBuilder, array: std.json.Array, options: FormatterOptions) bool {
    _ = builder;
    _ = array;
    _ = options;
    // TODO: Implement line width calculation
    return false;
}

fn writeEscapedString(builder: *LineBuilder, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '"' => try builder.append("\\\""),
            '\\' => try builder.append("\\\\"),
            '\n' => try builder.append("\\n"),
            '\r' => try builder.append("\\r"),
            '\t' => try builder.append("\\t"),
            '\x08' => try builder.append("\\b"),
            '\x0C' => try builder.append("\\f"),
            else => try builder.append(&[_]u8{c}),
        }
    }
}

// AST-based JSON formatting

/// Format JSON using AST-based approach
pub fn formatAst(allocator: std.mem.Allocator, node: ts.Node, source: []const u8, builder: *LineBuilder, options: FormatterOptions) !void {
    _ = allocator;
    try formatJsonNode(node, source, builder, 0, options);
}

/// JSON node formatting with controlled recursion
fn formatJsonNode(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) std.mem.Allocator.Error!void {
    const node_type = node.kind();

    if (std.mem.eql(u8, node_type, "object")) {
        try formatJsonObject(node, source, builder, depth, options);
    } else if (std.mem.eql(u8, node_type, "array")) {
        try formatJsonArray(node, source, builder, depth, options);
    } else if (std.mem.eql(u8, node_type, "pair")) {
        try formatJsonPair(node, source, builder, depth, options);
    } else if (std.mem.eql(u8, node_type, "document") or std.mem.eql(u8, node_type, "value")) {
        // For container nodes, recurse into children
        const child_count = node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                try formatJsonNode(child, source, builder, depth, options);
            }
        }
    } else {
        // For leaf nodes (string, number, boolean, null), just append text
        try appendNodeText(node, source, builder);
    }
}

/// Format JSON object
fn formatJsonObject(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) std.mem.Allocator.Error!void {
    try builder.append("{");

    const child_count = node.childCount();
    var pair_count: u32 = 0;
    var pairs = std.ArrayList(ts.Node).init(builder.allocator);
    defer pairs.deinit();

    // Collect all pair nodes
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        if (node.child(i)) |child| {
            const child_type = child.kind();
            if (std.mem.eql(u8, child_type, "pair")) {
                try pairs.append(child);
                pair_count += 1;
            }
        }
    }

    if (pair_count == 0) {
        try builder.append("}");
        return;
    }

    // Sort pairs if requested
    if (options.sort_keys) {
        const Context = struct {
            source: []const u8,

            fn lessThan(ctx: @This(), lhs: ts.Node, rhs: ts.Node) bool {
                const lhs_key = getJsonPairKey(lhs, ctx.source) orelse "";
                const rhs_key = getJsonPairKey(rhs, ctx.source) orelse "";
                return std.mem.lessThan(u8, lhs_key, rhs_key);
            }
        };
        std.mem.sort(ts.Node, pairs.items, Context{ .source = source }, Context.lessThan);
    }

    try builder.newline();
    builder.indent();

    for (pairs.items, 0..) |pair, j| {
        try builder.appendIndent();
        try formatJsonPair(pair, source, builder, depth + 1, options);

        if (j < pair_count - 1) {
            try builder.append(",");
        } else if (options.trailing_comma) {
            try builder.append(",");
        }

        try builder.newline();
    }

    builder.dedent();
    try builder.appendIndent();
    try builder.append("}");
}

/// Format JSON array
fn formatJsonArray(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) std.mem.Allocator.Error!void {
    try builder.append("[");

    const child_count = node.childCount();
    var value_count: u32 = 0;
    var values = std.ArrayList(ts.Node).init(builder.allocator);
    defer values.deinit();

    // Collect all value nodes
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        if (node.child(i)) |child| {
            const child_type = child.kind();
            if (!std.mem.eql(u8, child_type, ",") and !std.mem.eql(u8, child_type, "[") and !std.mem.eql(u8, child_type, "]")) {
                try values.append(child);
                value_count += 1;
            }
        }
    }

    if (value_count == 0) {
        try builder.append("]");
        return;
    }

    // Check if array should be single-line
    const is_simple = isSimpleAstArray(values.items);
    const single_line = is_simple;

    if (!single_line) {
        try builder.newline();
        builder.indent();
    }

    for (values.items, 0..) |value, j| {
        if (!single_line) {
            try builder.appendIndent();
        } else if (j > 0) {
            try builder.append(" ");
        }

        try formatJsonNode(value, source, builder, depth + 1, options);

        if (j < value_count - 1) {
            try builder.append(",");
        } else if (options.trailing_comma and !single_line) {
            try builder.append(",");
        }

        if (!single_line and j < value_count - 1) {
            try builder.newline();
        }
    }

    if (!single_line) {
        builder.dedent();
        try builder.newline();
        try builder.appendIndent();
    }

    try builder.append("]");
}

/// Format JSON key-value pair
fn formatJsonPair(node: ts.Node, source: []const u8, builder: *LineBuilder, depth: u32, options: FormatterOptions) std.mem.Allocator.Error!void {

    // Find key and value children
    const child_count = node.childCount();
    var key_node: ?ts.Node = null;
    var value_node: ?ts.Node = null;

    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        if (node.child(i)) |child| {
            const child_type = child.kind();
            if (std.mem.eql(u8, child_type, "string") and key_node == null) {
                key_node = child;
            } else if (!std.mem.eql(u8, child_type, ":") and !std.mem.eql(u8, child_type, "string") and value_node == null) {
                value_node = child;
            } else if (key_node != null and value_node == null and !std.mem.eql(u8, child_type, ":")) {
                value_node = child;
            }
        }
    }

    if (key_node) |key| {
        try appendNodeText(key, source, builder);
        try builder.append(": ");
    }

    if (value_node) |value| {
        try formatJsonNode(value, source, builder, depth + 1, options);
    }
}

/// Helper function to get node text from source
fn getNodeText(node: ts.Node, source: []const u8) []const u8 {
    const start = node.startByte();
    const end = node.endByte();
    if (end <= source.len and start <= end) {
        return source[start..end];
    }
    return "";
}

/// Helper function to append node text to builder
fn appendNodeText(node: ts.Node, source: []const u8, builder: *LineBuilder) !void {
    const text = getNodeText(node, source);
    try builder.append(text);
}

/// Get key from JSON pair node for sorting
fn getJsonPairKey(node: ts.Node, source: []const u8) ?[]const u8 {
    const child_count = node.childCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        if (node.child(i)) |child| {
            const child_type = child.kind();
            if (std.mem.eql(u8, child_type, "string")) {
                const key_text = getNodeText(child, source);
                // Remove quotes for comparison
                if (key_text.len >= 2 and key_text[0] == '"' and key_text[key_text.len - 1] == '"') {
                    return key_text[1 .. key_text.len - 1];
                }
                return key_text;
            }
        }
    }
    return null;
}

/// Check if array should be formatted as single-line (AST version)
fn isSimpleAstArray(values: []ts.Node) bool {
    if (values.len > 3) return false;

    for (values) |value| {
        const node_type = value.kind();
        if (std.mem.eql(u8, node_type, "object") or std.mem.eql(u8, node_type, "array")) {
            return false;
        }
    }
    return true;
}

/// Check if a node represents a JSON value
pub fn isJsonValue(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "string") or
        std.mem.eql(u8, node_type, "number") or
        std.mem.eql(u8, node_type, "true") or
        std.mem.eql(u8, node_type, "false") or
        std.mem.eql(u8, node_type, "null") or
        std.mem.eql(u8, node_type, "object") or
        std.mem.eql(u8, node_type, "array");
}
