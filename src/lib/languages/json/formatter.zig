const std = @import("std");
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;
const LineBuilder = @import("../../parsing/formatter.zig").LineBuilder;

/// Format JSON source code
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