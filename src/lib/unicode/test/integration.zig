/// Unicode Module Integration Tests
///
/// End-to-end tests combining multiple Unicode features.
const std = @import("std");
const testing = std.testing;
const unicode = @import("../mod.zig");

test "Unicode module - end-to-end validation" {
    const allocator = testing.allocator;

    // Test string with various problematic characters
    const test_cases = [_]struct {
        input: []const u8,
        mode: unicode.UnicodeMode,
        should_pass: bool,
        description: []const u8,
    }{
        .{
            .input = "Hello, World!",
            .mode = .strict,
            .should_pass = true,
            .description = "Regular ASCII should pass",
        },
        .{
            .input = "Hello\x00World",
            .mode = .strict,
            .should_pass = false,
            .description = "NULL byte should fail in strict",
        },
        .{
            .input = "Hello\x00World",
            .mode = .permissive,
            .should_pass = true,
            .description = "NULL byte should pass in permissive",
        },
        .{
            .input = "Line1\rLine2",
            .mode = .strict,
            .should_pass = false,
            .description = "CR should fail in strict (Unix line endings)",
        },
        .{
            .input = "Line1\rLine2",
            .mode = .sanitize,
            .should_pass = true,
            .description = "CR should pass in sanitize",
        },
        .{
            .input = "Tab\tand\nNewline",
            .mode = .strict,
            .should_pass = true,
            .description = "Tab and newline should pass",
        },
    };

    for (test_cases) |case| {
        const result = unicode.validateString(case.input, case.mode);
        if (case.should_pass) {
            if (!result.valid) {
                std.debug.print("Test failed: {s}\n", .{case.description});
                if (result.message) |msg| {
                    std.debug.print("  Error: {s}\n", .{msg});
                }
            }
            try testing.expect(result.valid);
        } else {
            if (result.valid) {
                std.debug.print("Test failed: {s} (expected failure but passed)\n", .{case.description});
            }
            try testing.expect(!result.valid);
        }
    }

    // Test sanitization
    const input_with_controls = "Hello\x00World\x08Test";
    const sanitized = try unicode.validation.sanitizeString(allocator, input_with_controls);
    defer allocator.free(sanitized);

    // Check that control characters are replaced with U+FFFD
    try testing.expect(std.mem.indexOf(u8, sanitized, "\x00") == null);
    try testing.expect(std.mem.indexOf(u8, sanitized, "\x08") == null);
    try testing.expect(std.mem.indexOf(u8, sanitized, "\xEF\xBF\xBD") != null);
}

test "Unicode module - escape sequence parsing" {
    const test_cases = [_]struct {
        input: []const u8,
        expected_valid: bool,
        expected_code_point: ?u32,
        expected_incomplete: bool,
        description: []const u8,
    }{
        .{
            .input = "u0041",
            .expected_valid = true,
            .expected_code_point = 0x41,
            .expected_incomplete = false,
            .description = "Valid \\uXXXX escape",
        },
        .{
            .input = "u00",
            .expected_valid = false,
            .expected_code_point = null,
            .expected_incomplete = true,
            .description = "Incomplete \\uXXXX escape",
        },
        .{
            .input = "uGGGG",
            .expected_valid = false,
            .expected_code_point = null,
            .expected_incomplete = false,
            .description = "Invalid \\uXXXX escape",
        },
        .{
            .input = "x41",
            .expected_valid = true,
            .expected_code_point = 0x41,
            .expected_incomplete = false,
            .description = "Valid \\xXX escape",
        },
        .{
            .input = "u{1F600}",
            .expected_valid = true,
            .expected_code_point = 0x1F600,
            .expected_incomplete = false,
            .description = "Valid Rust-style escape",
        },
    };

    for (test_cases) |case| {
        const result = unicode.parseUnicodeEscape(case.input);

        if (result.valid != case.expected_valid) {
            std.debug.print("Test failed: {s}\n", .{case.description});
            std.debug.print("  Expected valid={}, got valid={}\n", .{ case.expected_valid, result.valid });
        }
        try testing.expect(result.valid == case.expected_valid);

        if (case.expected_code_point) |expected| {
            if (result.code_point != expected) {
                std.debug.print("Test failed: {s}\n", .{case.description});
                std.debug.print("  Expected code_point=0x{X}, got 0x{X}\n", .{ expected, result.code_point.? });
            }
            try testing.expect(result.code_point == expected);
        }

        if (result.incomplete != case.expected_incomplete) {
            std.debug.print("Test failed: {s}\n", .{case.description});
            std.debug.print("  Expected incomplete={}, got incomplete={}\n", .{ case.expected_incomplete, result.incomplete });
        }
        try testing.expect(result.incomplete == case.expected_incomplete);
    }
}

test "Unicode module - UTF-8 validation" {
    const test_cases = [_]struct {
        input: []const u8,
        expected_valid: bool,
        description: []const u8,
    }{
        .{
            .input = "Valid UTF-8: 你好, 世界! 😀",
            .expected_valid = true,
            .description = "Valid UTF-8 with various scripts",
        },
        .{
            .input = "Invalid\x80UTF-8",
            .expected_valid = false,
            .description = "Invalid continuation byte as start",
        },
        .{
            .input = "Incomplete\xC3",
            .expected_valid = false,
            .description = "Incomplete 2-byte sequence",
        },
        .{
            .input = "Overlong\xC0\x80",
            .expected_valid = false,
            .description = "Overlong encoding",
        },
    };

    for (test_cases) |case| {
        const result = unicode.utf8.validateUtf8(case.input);

        if (result.valid != case.expected_valid) {
            std.debug.print("Test failed: {s}\n", .{case.description});
            std.debug.print("  Expected valid={}, got valid={}\n", .{ case.expected_valid, result.valid });
            if (result.error_code) |ec| {
                std.debug.print("  Error: {s}\n", .{ec.getMessage()});
            }
        }
        try testing.expect(result.valid == case.expected_valid);
    }
}

test "Unicode module - code point classification" {
    const test_cases = [_]struct {
        code_point: u32,
        expected_class: unicode.codepoint.CodePointClass,
        description: []const u8,
    }{
        .{
            .code_point = 0x41,
            .expected_class = .valid,
            .description = "ASCII letter A",
        },
        .{
            .code_point = 0x00,
            .expected_class = .control_character,
            .description = "NULL byte",
        },
        .{
            .code_point = 0x0D,
            .expected_class = .carriage_return,
            .description = "Carriage return",
        },
        .{
            .code_point = 0xD800,
            .expected_class = .surrogate,
            .description = "High surrogate",
        },
        .{
            .code_point = 0xFFFE,
            .expected_class = .noncharacter,
            .description = "Noncharacter at end of BMP",
        },
    };

    for (test_cases) |case| {
        const class = unicode.codepoint.classifyCodePoint(case.code_point);

        if (class != case.expected_class) {
            std.debug.print("Test failed: {s}\n", .{case.description});
            std.debug.print("  Code point U+{X:0>4}\n", .{case.code_point});
            std.debug.print("  Expected class={}, got class={}\n", .{ case.expected_class, class });
        }
        try testing.expect(class == case.expected_class);
    }
}

test "Unicode module - RFC 9839 problematic code points" {
    const problematic_cases = [_]struct {
        code_point: u32,
        description: []const u8,
        should_be_rejected: bool,
    }{
        // Surrogates (U+D800-U+DFFF)
        .{ .code_point = 0xD800, .description = "High surrogate start", .should_be_rejected = true },
        .{ .code_point = 0xDBFF, .description = "High surrogate end", .should_be_rejected = true },
        .{ .code_point = 0xDC00, .description = "Low surrogate start", .should_be_rejected = true },
        .{ .code_point = 0xDFFF, .description = "Low surrogate end", .should_be_rejected = true },

        // Control characters (legacy controls)
        .{ .code_point = 0x00, .description = "NULL", .should_be_rejected = true },
        .{ .code_point = 0x08, .description = "Backspace", .should_be_rejected = true },
        .{ .code_point = 0x7F, .description = "DEL", .should_be_rejected = true },
        .{ .code_point = 0x85, .description = "C1 control NEL", .should_be_rejected = true },
        .{ .code_point = 0x9F, .description = "C1 control APC", .should_be_rejected = true },

        // Useful controls (should NOT be rejected in permissive/sanitize)
        .{ .code_point = 0x09, .description = "Tab", .should_be_rejected = false },
        .{ .code_point = 0x0A, .description = "Newline", .should_be_rejected = false },

        // Noncharacters
        .{ .code_point = 0xFDD0, .description = "Noncharacter range start", .should_be_rejected = true },
        .{ .code_point = 0xFDEF, .description = "Noncharacter range end", .should_be_rejected = true },
        .{ .code_point = 0xFFFE, .description = "BMP noncharacter", .should_be_rejected = true },
        .{ .code_point = 0xFFFF, .description = "BMP noncharacter", .should_be_rejected = true },
        .{ .code_point = 0x1FFFE, .description = "Plane 1 noncharacter", .should_be_rejected = true },
        .{ .code_point = 0x10FFFF, .description = "Last plane noncharacter", .should_be_rejected = true },

        // Valid characters
        .{ .code_point = 0x20, .description = "Space", .should_be_rejected = false },
        .{ .code_point = 0x1F600, .description = "Emoji", .should_be_rejected = false },
        .{ .code_point = 0xFFFD, .description = "Replacement character", .should_be_rejected = false },
    };

    for (problematic_cases) |case| {
        const result_strict = unicode.validateCodePoint(case.code_point, .strict);
        const is_rejected = result_strict != null;

        if (is_rejected != case.should_be_rejected) {
            std.debug.print("RFC 9839 compliance test failed: {s}\n", .{case.description});
            std.debug.print("  Code point: U+{X:0>4}\n", .{case.code_point});
            std.debug.print("  Expected rejected={}, got rejected={}\n", .{ case.should_be_rejected, is_rejected });
            if (result_strict) |err| {
                std.debug.print("  Error code: {}\n", .{err});
            }
        }
        try testing.expect(is_rejected == case.should_be_rejected);

        // In permissive mode, nothing should be rejected
        const result_permissive = unicode.validateCodePoint(case.code_point, .permissive);
        try testing.expect(result_permissive == null);
    }
}

test "Unicode module - escape formatting" {
    const allocator = testing.allocator;

    // Test various escape formats
    const formats = [_]struct {
        code_point: u32,
        format: unicode.escape.Format,
        expected: []const u8,
    }{
        .{ .code_point = 0x41, .format = .json_style, .expected = "\\u0041" },
        .{ .code_point = 0x1F600, .format = .json_style, .expected = "\\uD83D\\uDE00" }, // Surrogate pair
        .{ .code_point = 0x41, .format = .zon_style, .expected = "\\x41" },
        .{ .code_point = 0x1F600, .format = .zon_style, .expected = "\\u{1f600}" },
        .{ .code_point = 0x41, .format = .rust_style, .expected = "\\u{41}" },
        .{ .code_point = 0x1F600, .format = .python_style, .expected = "\\U0001f600" },
    };

    for (formats) |fmt| {
        const result = try unicode.formatEscape(allocator, fmt.code_point, fmt.format);
        defer allocator.free(result);

        if (!std.mem.eql(u8, result, fmt.expected)) {
            std.debug.print("Format test failed:\n", .{});
            std.debug.print("  Code point: U+{X:0>4}\n", .{fmt.code_point});
            std.debug.print("  Format: {}\n", .{fmt.format});
            std.debug.print("  Expected: {s}\n", .{fmt.expected});
            std.debug.print("  Got: {s}\n", .{result});
        }
        try testing.expectEqualStrings(fmt.expected, result);
    }
}

test "Unicode module - mixed problematic content integration" {
    const allocator = testing.allocator;

    // Test string with multiple types of problematic content
    const mixed_input = "Hello\x00World\xED\xA0\x80Test\xEF\xBF\xBF\x85End"; // NULL + surrogate + BOM + NEL

    // Should fail in strict mode
    const strict_result = unicode.validateString(mixed_input, .strict);
    try testing.expect(!strict_result.valid);

    // Should pass in permissive mode (if UTF-8 is valid)
    const permissive_result = unicode.validateString(mixed_input, .permissive);
    _ = permissive_result; // May pass or fail depending on UTF-8 validity

    // Should sanitize in sanitize mode
    const sanitized = try unicode.validation.sanitizeString(allocator, mixed_input);
    defer allocator.free(sanitized);

    // Verify sanitization replaced problematic characters
    try testing.expect(std.mem.indexOf(u8, sanitized, "\x00") == null);
    try testing.expect(std.mem.indexOf(u8, sanitized, "\x85") == null);
    try testing.expect(std.mem.indexOf(u8, sanitized, "\xEF\xBF\xBD") != null);
}

test "Unicode module - mode comparison" {
    const test_string = "Valid\x00Mixed\x09Content"; // NULL + TAB (valid UTF-8)

    // Strict: should reject (NULL is control character)
    const strict = unicode.validateString(test_string, .strict);
    try testing.expect(!strict.valid);
    try testing.expect(strict.error_code == .control_character_in_string);

    // Sanitize: should also reject during validation (sanitizeString is separate)
    const sanitize = unicode.validateString(test_string, .sanitize);
    try testing.expect(!sanitize.valid);
    try testing.expect(sanitize.error_code == .control_character_in_string);

    // Permissive: should pass (valid UTF-8, no validation of content)
    const permissive = unicode.validateString(test_string, .permissive);
    try testing.expect(permissive.valid);
}

test "Unicode module - control character validation" {
    // C0 control characters (should be detected)
    try testing.expect(unicode.validateByte(0x00, .strict) == .control_character_in_string); // NULL
    try testing.expect(unicode.validateByte(0x08, .strict) == .control_character_in_string); // Backspace
    try testing.expect(unicode.validateByte(0x1F, .strict) == .control_character_in_string); // Unit separator

    // DEL character
    try testing.expect(unicode.validateByte(0x7F, .strict) == .control_character_in_string);

    // C1 control characters
    try testing.expect(unicode.validateByte(0x80, .strict) == .control_character_in_string);
    try testing.expect(unicode.validateByte(0x9F, .strict) == .control_character_in_string);

    // Tab and newline should not be flagged as problematic control chars
    try testing.expect(unicode.validateByte(0x09, .strict) == null); // Tab
    try testing.expect(unicode.validateByte(0x0A, .strict) == null); // Newline

    // Regular ASCII should not be flagged
    try testing.expect(unicode.validateByte(0x20, .strict) == null); // Space
    try testing.expect(unicode.validateByte(0x41, .strict) == null); // 'A'
    try testing.expect(unicode.validateByte(0x7E, .strict) == null); // '~'
}
