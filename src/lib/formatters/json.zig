const std = @import("std");
const FormatterOptions = @import("../parsing/formatter.zig").FormatterOptions;
const LineBuilder = @import("../parsing/formatter.zig").LineBuilder;

pub fn format(allocator: std.mem.Allocator, source: []const u8, options: FormatterOptions) ![]const u8 {
    // Parse JSON
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, source, .{}) catch {
        // If parsing fails, return original source
        return allocator.dupe(u8, source);
    };
    defer parsed.deinit();

    // Pretty print with options
    var builder = LineBuilder.init(allocator, options);
    defer builder.deinit();

    try formatValue(&builder, parsed.value, options);

    return builder.toOwnedSlice();
}

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

    var it = object.iterator();
    while (it.next()) |entry| {
        try keys.append(entry.key_ptr.*);
    }

    if (options.sort_keys) {
        std.sort.heap([]const u8, keys.items, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.order(u8, a, b) == .lt;
            }
        }.lessThan);
    }

    // Check if object should be single-line
    const is_simple = isSimpleObject(object);
    const single_line = is_simple and !wouldExceedObjectLineWidth(builder, object, options);

    try builder.append("{");

    if (!single_line) {
        try builder.newline();
        builder.indent();
    }

    for (keys.items, 0..) |key, i| {
        if (!single_line) {
            try builder.appendIndent();
        } else if (i > 0) {
            try builder.append(" ");
        }

        // Write key
        try builder.append("\"");
        try writeEscapedString(builder, key);
        try builder.append("\": ");

        // Write value
        if (object.get(key)) |value| {
            try formatValue(builder, value, options);
        }

        if (i < keys.items.len - 1) {
            try builder.append(",");
        } else if (options.trailing_comma and !single_line) {
            try builder.append(",");
        }

        if (!single_line and i < keys.items.len - 1) {
            try builder.newline();
        }
    }

    if (!single_line) {
        builder.dedent();
        try builder.newline();
        try builder.appendIndent();
    }

    try builder.append("}");
}

fn writeEscapedString(builder: *LineBuilder, str: []const u8) !void {
    for (str) |char| {
        switch (char) {
            '"' => try builder.append("\\\""),
            '\\' => try builder.append("\\\\"),
            '\n' => try builder.append("\\n"),
            '\r' => try builder.append("\\r"),
            '\t' => try builder.append("\\t"),
            0x08 => try builder.append("\\b"), // backspace
            0x0C => try builder.append("\\f"), // form feed
            else => {
                if (char < 0x20) {
                    // Control character - use \uXXXX escape
                    var buf: [6]u8 = undefined;
                    const escaped = try std.fmt.bufPrint(&buf, "\\u{x:0>4}", .{char});
                    try builder.append(escaped);
                } else {
                    // Normal character
                    try builder.append(&[_]u8{char});
                }
            },
        }
    }
}

fn isSimpleArray(array: std.json.Array) bool {
    if (array.items.len > 5) return false;

    for (array.items) |item| {
        switch (item) {
            .null, .bool, .integer, .float, .number_string => {},
            .string => |s| {
                if (s.len > 20) return false;
            },
            .array, .object => return false,
        }
    }

    return true;
}

fn isSimpleObject(object: std.json.ObjectMap) bool {
    if (object.count() > 3) return false;

    var it = object.iterator();
    while (it.next()) |entry| {
        if (entry.key_ptr.*.len > 20) return false;

        switch (entry.value_ptr.*) {
            .null, .bool, .integer, .float, .number_string => {},
            .string => |s| {
                if (s.len > 20) return false;
            },
            .array, .object => return false,
        }
    }

    return true;
}

fn wouldExceedLineWidth(builder: *LineBuilder, array: std.json.Array, options: FormatterOptions) bool {
    _ = options;
    // Estimate the line width
    var estimated_width = builder.current_line_length + 2; // [ and ]

    for (array.items, 0..) |item, i| {
        if (i > 0) estimated_width += 2; // ", "

        switch (item) {
            .null => estimated_width += 4,
            .bool => |b| estimated_width += if (b) 4 else 5,
            .integer => estimated_width += 10, // rough estimate
            .float => estimated_width += 10,
            .number_string => |s| estimated_width += @intCast(s.len),
            .string => |s| estimated_width += @intCast(s.len + 2), // quotes
            else => return true, // Complex types always multi-line
        }
    }

    return estimated_width > builder.options.line_width;
}

fn wouldExceedObjectLineWidth(builder: *LineBuilder, object: std.json.ObjectMap, options: FormatterOptions) bool {
    _ = options;
    // Estimate the line width
    var estimated_width = builder.current_line_length + 2; // { and }

    var it = object.iterator();
    var i: usize = 0;
    while (it.next()) |entry| : (i += 1) {
        if (i > 0) estimated_width += 2; // ", "

        estimated_width += @intCast(entry.key_ptr.*.len + 4); // "key":

        switch (entry.value_ptr.*) {
            .null => estimated_width += 4,
            .bool => |b| estimated_width += if (b) 4 else 5,
            .integer => estimated_width += 10,
            .float => estimated_width += 10,
            .number_string => |s| estimated_width += @intCast(s.len),
            .string => |s| estimated_width += @intCast(s.len + 2),
            else => return true,
        }
    }

    return estimated_width > builder.options.line_width;
}
