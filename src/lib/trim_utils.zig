const std = @import("std");

/// Trimming utilities to centralize whitespace handling
/// Replaces 27+ instances of std.mem.trim patterns

/// Trim spaces and tabs (most common pattern)
pub fn trimWhitespace(text: []const u8) []const u8 {
    return std.mem.trim(u8, text, " \t");
}

/// Trim all whitespace including newlines
pub fn trimAll(text: []const u8) []const u8 {
    return std.mem.trim(u8, text, " \t\r\n");
}

/// Trim only leading whitespace
pub fn trimLeft(text: []const u8) []const u8 {
    return std.mem.trimLeft(u8, text, " \t");
}

/// Trim only trailing whitespace
pub fn trimRight(text: []const u8) []const u8 {
    return std.mem.trimRight(u8, text, " \t");
}

/// Check if line is empty after trimming
pub fn isBlank(text: []const u8) bool {
    return trimWhitespace(text).len == 0;
}

/// Trim and check if not empty
pub fn trimmedNotEmpty(text: []const u8) ?[]const u8 {
    const trimmed = trimWhitespace(text);
    return if (trimmed.len > 0) trimmed else null;
}

test "trimWhitespace basic" {
    try std.testing.expectEqualStrings("hello", trimWhitespace("  hello  "));
    try std.testing.expectEqualStrings("hello", trimWhitespace("\thello\t"));
    try std.testing.expectEqualStrings("hello world", trimWhitespace("  hello world  "));
}

test "trimAll includes newlines" {
    try std.testing.expectEqualStrings("hello", trimAll("\n  hello  \n"));
    try std.testing.expectEqualStrings("hello", trimAll("\r\n\thello\t\r\n"));
}

test "isBlank" {
    try std.testing.expect(isBlank(""));
    try std.testing.expect(isBlank("  "));
    try std.testing.expect(isBlank("\t"));
    try std.testing.expect(isBlank(" \t "));
    try std.testing.expect(!isBlank("a"));
    try std.testing.expect(!isBlank(" a "));
}

test "trimmedNotEmpty" {
    try std.testing.expect(trimmedNotEmpty("") == null);
    try std.testing.expect(trimmedNotEmpty("  ") == null);
    try std.testing.expectEqualStrings("hello", trimmedNotEmpty("  hello  ").?);
}