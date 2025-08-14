const std = @import("std");

/// Simple append utilities to eliminate repetitive patterns
/// Replaces 100+ instances of appendSlice + append('\n')

/// Append a line with automatic newline
pub fn appendLine(list: *std.ArrayList(u8), line: []const u8) !void {
    try list.appendSlice(line);
    try list.append('\n');
}

/// Append multiple lines
pub fn appendLines(list: *std.ArrayList(u8), lines: []const []const u8) !void {
    for (lines) |line| {
        try appendLine(list, line);
    }
}

/// Append with optional newline
pub fn appendMaybe(list: *std.ArrayList(u8), text: []const u8, add_newline: bool) !void {
    try list.appendSlice(text);
    if (add_newline) {
        try list.append('\n');
    }
}

/// Append text with indent
pub fn appendIndented(list: *std.ArrayList(u8), indent: usize, text: []const u8) !void {
    for (0..indent) |_| {
        try list.append(' ');
    }
    try list.appendSlice(text);
}

/// Append line with indent
pub fn appendIndentedLine(list: *std.ArrayList(u8), indent: usize, line: []const u8) !void {
    try appendIndented(list, indent, line);
    try list.append('\n');
}

test "appendLine basic" {
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    
    try appendLine(&list, "hello");
    try appendLine(&list, "world");
    
    try std.testing.expectEqualStrings("hello\nworld\n", list.items);
}

test "appendLines multiple" {
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    
    const lines = [_][]const u8{ "line1", "line2", "line3" };
    try appendLines(&list, &lines);
    
    try std.testing.expectEqualStrings("line1\nline2\nline3\n", list.items);
}

test "appendIndentedLine" {
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    
    try appendIndentedLine(&list, 4, "indented");
    try std.testing.expectEqualStrings("    indented\n", list.items);
}