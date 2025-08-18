const std = @import("std");

/// Text pattern matching utilities for code extraction
/// Provides common patterns for matching and extracting code elements
/// Moved from text_patterns.zig for better organization
/// Check if a line starts with any of the given prefixes
pub fn startsWithAny(text: []const u8, prefixes: []const []const u8) bool {
    for (prefixes) |prefix| {
        if (std.mem.startsWith(u8, text, prefix)) {
            return true;
        }
    }
    return false;
}

/// Check if a line contains any of the given substrings
pub fn containsAny(text: []const u8, substrings: []const []const u8) bool {
    for (substrings) |substring| {
        if (std.mem.indexOf(u8, text, substring) != null) {
            return true;
        }
    }
    return false;
}

/// Count occurrences of a character in text
pub fn countChar(text: []const u8, char: u8) usize {
    var count: usize = 0;
    for (text) |c| {
        if (c == char) count += 1;
    }
    return count;
}

/// Count balance of opening and closing characters (e.g., braces)
pub fn countBalance(text: []const u8, open: u8, close: u8) i32 {
    var balance: i32 = 0;
    for (text) |c| {
        if (c == open) balance += 1;
        if (c == close) balance -= 1;
    }
    return balance;
}

/// Find closing delimiter for a given opening position
pub fn findClosingDelimiter(text: []const u8, start: usize, open: u8, close: u8) ?usize {
    if (start >= text.len) return null;

    var depth: i32 = 1;
    var i = start + 1;

    while (i < text.len) : (i += 1) {
        if (text[i] == open) {
            depth += 1;
        } else if (text[i] == close) {
            depth -= 1;
            if (depth == 0) {
                return i;
            }
        }
    }

    return null;
}

/// Extract content between delimiters (e.g., between < and >)
pub fn extractBetween(
    text: []const u8,
    open_delim: []const u8,
    close_delim: []const u8,
) ?[]const u8 {
    if (std.mem.indexOf(u8, text, open_delim)) |start| {
        const content_start = start + open_delim.len;
        if (std.mem.indexOf(u8, text[content_start..], close_delim)) |end| {
            return text[content_start .. content_start + end];
        }
    }
    return null;
}

/// Extract all occurrences between delimiters
pub fn extractAllBetween(
    allocator: std.mem.Allocator,
    text: []const u8,
    open_delim: []const u8,
    close_delim: []const u8,
) !std.ArrayList([]const u8) {
    var results = std.ArrayList([]const u8).init(allocator);
    var pos: usize = 0;

    while (pos < text.len) {
        if (std.mem.indexOf(u8, text[pos..], open_delim)) |start| {
            const abs_start = pos + start;
            const content_start = abs_start + open_delim.len;
            if (std.mem.indexOf(u8, text[content_start..], close_delim)) |end| {
                const content = text[content_start .. content_start + end];
                try results.append(content);
                pos = content_start + end + close_delim.len;
                continue;
            }
        }
        break;
    }

    return results;
}

// Language-specific patterns have been moved to their respective modules:
// - TypeScript patterns: src/lib/languages/typescript/patterns.zig
// - Zig patterns: src/lib/languages/zig/patterns.zig
// - CSS patterns: src/lib/languages/css/patterns.zig
// - HTML patterns: src/lib/languages/html/patterns.zig
// - JSON patterns: can be added to src/lib/languages/json/patterns.zig if needed

/// Check if text is a comment line
pub fn isComment(text: []const u8, style: CommentStyle) bool {
    const trimmed = std.mem.trim(u8, text, " \t");

    return switch (style) {
        .c_style => std.mem.startsWith(u8, trimmed, "//") or
            std.mem.startsWith(u8, trimmed, "/*") or
            std.mem.startsWith(u8, trimmed, "*"),
        .hash => std.mem.startsWith(u8, trimmed, "#"),
        .html => std.mem.startsWith(u8, trimmed, "<!--"),
        .sql => std.mem.startsWith(u8, trimmed, "--"),
    };
}

pub const CommentStyle = enum {
    c_style, // // or /* */
    hash, // #
    html, // <!-- -->
    sql, // --
};

// Tag extraction moved to src/lib/languages/html/patterns.zig

test "startsWithAny" {
    const text = "export function test()";
    const prefixes = [_][]const u8{ "import", "export", "const" };
    try std.testing.expect(startsWithAny(text, &prefixes));
    try std.testing.expect(!startsWithAny("function test()", &prefixes));
}

test "containsAny" {
    const text = "const arrow = () => {}";
    const patterns = [_][]const u8{ "=>", "function", "class" };
    try std.testing.expect(containsAny(text, &patterns));
    try std.testing.expect(!containsAny("const value = 42", &patterns));
}

test "countBalance" {
    try std.testing.expectEqual(@as(i32, 0), countBalance("{}", '{', '}'));
    try std.testing.expectEqual(@as(i32, 1), countBalance("{{}", '{', '}'));
    try std.testing.expectEqual(@as(i32, -1), countBalance("{}}", '{', '}'));
    try std.testing.expectEqual(@as(i32, 1), countBalance("{ { } ", '{', '}')); // 2 opens, 1 close = balance of 1
}

test "findClosingDelimiter" {
    const text = "{ nested { inner } outer }";
    const close = findClosingDelimiter(text, 0, '{', '}');
    try std.testing.expect(close != null);
    try std.testing.expectEqual(@as(usize, 25), close.?); // Position of the final '}'
}

test "extractBetween" {
    const text = "<script>console.log('test');</script>";
    const content = extractBetween(text, "<script>", "</script>");
    try std.testing.expect(content != null);
    try std.testing.expectEqualStrings("console.log('test');", content.?);
}

// extractTagName test removed - function moved to src/lib/languages/html/patterns.zig

test "isComment" {
    try std.testing.expect(isComment("// comment", .c_style));
    try std.testing.expect(isComment("/* comment */", .c_style));
    try std.testing.expect(isComment("# comment", .hash));
    try std.testing.expect(isComment("<!-- comment -->", .html));
    try std.testing.expect(!isComment("not a comment", .c_style));
}

test "extractAllBetween" {
    const allocator = std.testing.allocator;
    // Simple test with clear delimiters
    const text = "[content1] and [content2]";

    var results = try extractAllBetween(allocator, text, "[", "]");
    defer results.deinit();

    try std.testing.expectEqual(@as(usize, 2), results.items.len);
    try std.testing.expectEqualStrings("content1", results.items[0]);
    try std.testing.expectEqualStrings("content2", results.items[1]);
}
