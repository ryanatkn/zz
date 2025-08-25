/// Unicode Escape Sequence Handling
///
/// Parsing and formatting of Unicode escape sequences in various formats.
const std = @import("std");
const ErrorCode = @import("mod.zig").ErrorCode;

/// Escape sequence format
pub const Format = enum {
    json_style, // \uXXXX (4 hex digits)
    zon_style, // \xXX (2 hex digits) or \u{XXXX} (variable)
    c_style, // \xXX (2 hex digits)
    rust_style, // \u{X} to \u{XXXXXX} (variable, with braces)
    python_style, // \xXX (2 hex) or \uXXXX (4 hex) or \UXXXXXXXX (8 hex)
};

/// Result of parsing an escape sequence
pub const ParseResult = struct {
    /// Whether parsing succeeded
    valid: bool,

    /// The decoded code point (if valid)
    code_point: ?u32 = null,

    /// Number of characters consumed (including backslash)
    consumed: usize = 0,

    /// Error code if invalid
    error_code: ?ErrorCode = null,

    /// Whether the sequence is incomplete (vs invalid)
    incomplete: bool = false,
};

/// Parse a Unicode escape sequence
/// Input should start with the character after the backslash
pub fn parseUnicodeEscape(text: []const u8) ParseResult {
    if (text.len == 0) {
        return ParseResult{
            .valid = false,
            .error_code = .invalid_escape_sequence,
        };
    }

    switch (text[0]) {
        // \uXXXX format (JSON, JavaScript)
        'u' => {
            // Check for Rust/Zig style \u{...}
            if (text.len > 1 and text[1] == '{') {
                return parseRustStyleEscape(text);
            }
            return parseFixedHexEscape(text[1..], 4);
        },

        // \xXX format (C, ZON, Python)
        'x' => {
            return parseFixedHexEscape(text[1..], 2);
        },

        // \UXXXXXXXX format (Python, extended Unicode)
        'U' => {
            return parseFixedHexEscape(text[1..], 8);
        },

        // Not a Unicode escape
        else => {
            return ParseResult{
                .valid = false,
                .error_code = .invalid_escape_sequence,
            };
        },
    }
}

/// Parse a fixed-length hex escape sequence
fn parseFixedHexEscape(text: []const u8, expected_digits: usize) ParseResult {
    // Check if we have enough characters
    if (text.len < expected_digits) {
        // Determine if it's incomplete or invalid
        var all_hex = true;
        for (text) |ch| {
            if (!isHexDigit(ch)) {
                all_hex = false;
                break;
            }
        }

        return ParseResult{
            .valid = false,
            .error_code = if (all_hex) .incomplete_unicode_escape else .invalid_unicode_escape,
            .incomplete = all_hex,
            .consumed = 1 + text.len, // +1 for the prefix
        };
    }

    // Parse the hex digits
    var code_point: u32 = 0;
    for (text[0..expected_digits]) |ch| {
        if (!isHexDigit(ch)) {
            return ParseResult{
                .valid = false,
                .error_code = .invalid_unicode_escape,
                .consumed = 1, // Just the prefix character
            };
        }
        code_point = code_point * 16 + hexDigitValue(ch);
    }

    // Validate the code point
    if (code_point > 0x10FFFF) {
        return ParseResult{
            .valid = false,
            .error_code = .invalid_unicode_escape,
            .consumed = 1 + expected_digits,
        };
    }

    return ParseResult{
        .valid = true,
        .code_point = code_point,
        .consumed = 1 + expected_digits, // +1 for the prefix (u, x, or U)
    };
}

/// Parse Rust/Zig style \u{...} escape
fn parseRustStyleEscape(text: []const u8) ParseResult {
    // text[0] is 'u', text[1] is '{'
    if (text.len < 3) {
        return ParseResult{
            .valid = false,
            .error_code = .incomplete_unicode_escape,
            .incomplete = true,
            .consumed = text.len,
        };
    }

    // Find closing brace
    var end: usize = 2;
    var code_point: u32 = 0;
    var found_close = false;

    while (end < text.len and end < 10) { // Max 6 hex digits + braces
        if (text[end] == '}') {
            found_close = true;
            break;
        }
        if (!isHexDigit(text[end])) {
            return ParseResult{
                .valid = false,
                .error_code = .invalid_unicode_escape,
                .consumed = end + 1,
            };
        }
        code_point = code_point * 16 + hexDigitValue(text[end]);
        end += 1;
    }

    if (!found_close) {
        return ParseResult{
            .valid = false,
            .error_code = .incomplete_unicode_escape,
            .incomplete = true,
            .consumed = end,
        };
    }

    // Must have at least one hex digit
    if (end == 2) {
        return ParseResult{
            .valid = false,
            .error_code = .invalid_unicode_escape,
            .consumed = 3, // u{}
        };
    }

    // Validate code point
    if (code_point > 0x10FFFF) {
        return ParseResult{
            .valid = false,
            .error_code = .invalid_unicode_escape,
            .consumed = end + 1,
        };
    }

    return ParseResult{
        .valid = true,
        .code_point = code_point,
        .consumed = end + 1, // Include the closing brace
    };
}

/// Format a code point as an escape sequence
pub fn formatEscape(allocator: std.mem.Allocator, code_point: u32, format: Format) ![]u8 {
    if (code_point > 0x10FFFF) {
        return error.InvalidCodePoint;
    }

    return switch (format) {
        .json_style => {
            // JSON only supports \uXXXX for BMP
            // For supplementary planes, use surrogate pairs
            if (code_point <= 0xFFFF) {
                return std.fmt.allocPrint(allocator, "\\u{X:0>4}", .{code_point});
            } else {
                // Convert to surrogate pair
                const adjusted = code_point - 0x10000;
                const high = 0xD800 + (adjusted >> 10);
                const low = 0xDC00 + (adjusted & 0x3FF);
                return std.fmt.allocPrint(allocator, "\\u{X:0>4}\\u{X:0>4}", .{ high, low });
            }
        },
        .zon_style => {
            if (code_point <= 0xFF) {
                return std.fmt.allocPrint(allocator, "\\x{x:0>2}", .{code_point});
            } else {
                return std.fmt.allocPrint(allocator, "\\u{{{x}}}", .{code_point});
            }
        },
        .c_style => {
            if (code_point <= 0xFF) {
                return std.fmt.allocPrint(allocator, "\\x{x:0>2}", .{code_point});
            } else {
                return error.CodePointTooLarge;
            }
        },
        .rust_style => {
            return std.fmt.allocPrint(allocator, "\\u{{{x}}}", .{code_point});
        },
        .python_style => {
            if (code_point <= 0xFF) {
                return std.fmt.allocPrint(allocator, "\\x{x:0>2}", .{code_point});
            } else if (code_point <= 0xFFFF) {
                return std.fmt.allocPrint(allocator, "\\u{x:0>4}", .{code_point});
            } else {
                return std.fmt.allocPrint(allocator, "\\U{x:0>8}", .{code_point});
            }
        },
    };
}

/// Check if a character is a hex digit
fn isHexDigit(ch: u8) bool {
    return (ch >= '0' and ch <= '9') or
        (ch >= 'a' and ch <= 'f') or
        (ch >= 'A' and ch <= 'F');
}

/// Get the value of a hex digit
fn hexDigitValue(ch: u8) u32 {
    if (ch >= '0' and ch <= '9') return ch - '0';
    if (ch >= 'a' and ch <= 'f') return ch - 'a' + 10;
    if (ch >= 'A' and ch <= 'F') return ch - 'A' + 10;
    return 0;
}

// Tests
const testing = std.testing;

test "parseUnicodeEscape - JSON style \\uXXXX" {
    // Valid 4-digit escape
    const result1 = parseUnicodeEscape("u0041");
    try testing.expect(result1.valid);
    try testing.expect(result1.code_point.? == 0x41); // 'A'
    try testing.expect(result1.consumed == 5);

    // Incomplete escape
    const result2 = parseUnicodeEscape("u00");
    try testing.expect(!result2.valid);
    try testing.expect(result2.error_code == .incomplete_unicode_escape);
    try testing.expect(result2.incomplete);

    // Invalid hex digit
    const result3 = parseUnicodeEscape("u00GG");
    try testing.expect(!result3.valid);
    try testing.expect(result3.error_code == .invalid_unicode_escape);
    try testing.expect(!result3.incomplete);
}

test "parseUnicodeEscape - C style \\xXX" {
    // Valid 2-digit escape
    const result1 = parseUnicodeEscape("x41");
    try testing.expect(result1.valid);
    try testing.expect(result1.code_point.? == 0x41); // 'A'
    try testing.expect(result1.consumed == 3);

    // Incomplete
    const result2 = parseUnicodeEscape("x4");
    try testing.expect(!result2.valid);
    try testing.expect(result2.error_code == .incomplete_unicode_escape);

    // Invalid
    const result3 = parseUnicodeEscape("xGG");
    try testing.expect(!result3.valid);
    try testing.expect(result3.error_code == .invalid_unicode_escape);
}

test "parseUnicodeEscape - Rust style \\u{...}" {
    // Valid variable-length escape
    const result1 = parseUnicodeEscape("u{41}");
    try testing.expect(result1.valid);
    try testing.expect(result1.code_point.? == 0x41);
    try testing.expect(result1.consumed == 5);

    // Multiple digits
    const result2 = parseUnicodeEscape("u{1F600}");
    try testing.expect(result2.valid);
    try testing.expect(result2.code_point.? == 0x1F600); // Emoji
    try testing.expect(result2.consumed == 8);

    // Missing closing brace
    const result3 = parseUnicodeEscape("u{41");
    try testing.expect(!result3.valid);
    try testing.expect(result3.error_code == .incomplete_unicode_escape);

    // Empty braces
    const result4 = parseUnicodeEscape("u{}");
    try testing.expect(!result4.valid);
    try testing.expect(result4.error_code == .invalid_unicode_escape);
}

test "formatEscape - various formats" {
    const allocator = testing.allocator;

    // JSON style
    const json1 = try formatEscape(allocator, 0x41, .json_style);
    defer allocator.free(json1);
    try testing.expectEqualStrings("\\u0041", json1);

    // JSON style with surrogate pair
    const json2 = try formatEscape(allocator, 0x1F600, .json_style);
    defer allocator.free(json2);
    try testing.expectEqualStrings("\\uD83D\\uDE00", json2);

    // ZON style
    const zon1 = try formatEscape(allocator, 0x41, .zon_style);
    defer allocator.free(zon1);
    try testing.expectEqualStrings("\\x41", zon1);

    const zon2 = try formatEscape(allocator, 0x1F600, .zon_style);
    defer allocator.free(zon2);
    try testing.expectEqualStrings("\\u{1f600}", zon2);

    // Rust style
    const rust = try formatEscape(allocator, 0x1F600, .rust_style);
    defer allocator.free(rust);
    try testing.expectEqualStrings("\\u{1f600}", rust);

    // Python style
    const py1 = try formatEscape(allocator, 0x41, .python_style);
    defer allocator.free(py1);
    try testing.expectEqualStrings("\\x41", py1);

    const py2 = try formatEscape(allocator, 0x1F600, .python_style);
    defer allocator.free(py2);
    try testing.expectEqualStrings("\\U0001f600", py2);
}
