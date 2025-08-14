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
            return text[content_start..content_start + end];
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
                const content = text[content_start..content_start + end];
                try results.append(content);
                pos = content_start + end + close_delim.len;
                continue;
            }
        }
        break;
    }
    
    return results;
}

/// Common code patterns for various languages
pub const Patterns = struct {
    // TypeScript/JavaScript patterns
    pub const ts_functions = [_][]const u8{
        "function ",
        "export function ",
        "export async function ",
        "async function ",
        "const ",
        "let ",
        "var ",
    };
    
    pub const ts_types = [_][]const u8{
        "interface ",
        "export interface ",
        "type ",
        "export type ",
        "class ",
        "export class ",
        "enum ",
        "export enum ",
    };
    
    pub const ts_imports = [_][]const u8{
        "import ",
        "export ",
        "require(",
    };
    
    // CSS patterns
    pub const css_selectors = [_][]const u8{
        ".",  // class
        "#",  // id
        "[",  // attribute
        ":",  // pseudo
    };
    
    pub const css_at_rules = [_][]const u8{
        "@import",
        "@media",
        "@keyframes",
        "@supports",
        "@font-face",
    };
    
    // HTML patterns
    pub const html_void_elements = [_][]const u8{
        "area",
        "base",
        "br",
        "col",
        "embed",
        "hr",
        "img",
        "input",
        "link",
        "meta",
        "param",
        "source",
        "track",
        "wbr",
    };
    
    // Zig patterns (comprehensive)
    pub const zig_functions = [_][]const u8{
        "pub fn ",
        "fn ",
        "export fn ",
        "inline fn ",
        "test ",
    };
    
    pub const zig_declarations = [_][]const u8{
        "pub fn ",
        "fn ",
        "pub const ",
        "const ",
        "pub var ",
        "var ",
        "test ",
        "comptime ",
        "threadlocal ",
    };
    
    pub const zig_types = [_][]const u8{
        "struct",
        "enum",
        "union",
        "error",
        "packed struct",
        "extern struct",
        "opaque",
    };
    
    pub const zig_docs = [_][]const u8{
        "///",
        "//!",
    };
    
    // JSON patterns
    pub const json_structural = [_][]const u8{
        "{",
        "}",
        "[",
        "]",
    };
    
    // Python patterns (for future use)
    pub const python_functions = [_][]const u8{
        "def ",
        "async def ",
        "lambda ",
    };
    
    pub const python_classes = [_][]const u8{
        "class ",
    };
    
    pub const python_imports = [_][]const u8{
        "import ",
        "from ",
    };
    
    // Rust patterns (for future use)
    pub const rust_functions = [_][]const u8{
        "fn ",
        "pub fn ",
        "async fn ",
        "const fn ",
    };
    
    pub const rust_types = [_][]const u8{
        "struct ",
        "enum ",
        "trait ",
        "impl ",
        "type ",
    };
    
    pub const rust_imports = [_][]const u8{
        "use ",
        "extern crate ",
        "mod ",
    };
    
    // Go patterns (for future use)
    pub const go_functions = [_][]const u8{
        "func ",
    };
    
    pub const go_types = [_][]const u8{
        "type ",
        "struct {",
        "interface {",
    };
    
    pub const go_imports = [_][]const u8{
        "import ",
        "package ",
    };
};

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
    c_style,  // // or /* */
    hash,     // #
    html,     // <!-- -->
    sql,      // --
};

/// Extract tag name from HTML/XML tag
pub fn extractTagName(tag: []const u8) ?[]const u8 {
    var start: usize = 0;
    if (std.mem.startsWith(u8, tag, "</")) {
        start = 2;
    } else if (std.mem.startsWith(u8, tag, "<")) {
        start = 1;
    } else {
        return null;
    }
    
    var end = start;
    while (end < tag.len) : (end += 1) {
        const c = tag[end];
        if (c == ' ' or c == '>' or c == '/' or c == '\t' or c == '\n') {
            break;
        }
    }
    
    return if (end > start) tag[start..end] else null;
}

/// Check if line is likely a function/method signature
pub fn isFunctionSignature(text: []const u8, lang: Language) bool {
    const trimmed = std.mem.trim(u8, text, " \t");
    
    return switch (lang) {
        .zig => startsWithAny(trimmed, &[_][]const u8{ "pub fn", "fn", "test" }),
        .typescript, .javascript => startsWithAny(trimmed, &Patterns.ts_functions) or
                                   std.mem.indexOf(u8, trimmed, "=>") != null,
        .css => false,
        .html => false,
        else => false,
    };
}

pub const Language = enum {
    zig,
    typescript,
    javascript,
    css,
    html,
    json,
    svelte,
    unknown,
};

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

test "extractTagName" {
    try std.testing.expectEqualStrings("div", extractTagName("<div>").?);
    try std.testing.expectEqualStrings("div", extractTagName("</div>").?);
    try std.testing.expectEqualStrings("input", extractTagName("<input type='text'>").?);
    try std.testing.expect(extractTagName("not a tag") == null);
}

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