/// RFC Compliance Tests
///
/// Edge cases and boundary conditions from Unicode RFCs.
const std = @import("std");
const testing = std.testing;
const unicode = @import("../mod.zig");

test "RFC 5198 - BOM (Byte Order Mark) Handling" {
    const allocator = testing.allocator;

    // UTF-8 BOM at start of string should be rejected per RFC 5198
    const bom_at_start = "\xEF\xBB\xBF" ++ "Hello World";
    const result = unicode.validateString(bom_at_start, .strict);

    // Should be rejected in strict mode per RFC 5198
    try testing.expect(!result.valid);
    try testing.expect(result.error_code == .bom_at_string_start);
    try testing.expect(result.position.? == 0);

    // Should also be rejected in sanitize mode
    const sanitize_result = unicode.validateString(bom_at_start, .sanitize);
    try testing.expect(!sanitize_result.valid);
    try testing.expect(sanitize_result.error_code == .bom_at_string_start);

    // But should pass in permissive mode (valid UTF-8)
    const permissive_result = unicode.validateString(bom_at_start, .permissive);
    try testing.expect(permissive_result.valid);

    // BOM in middle should be treated as ZERO WIDTH NO-BREAK SPACE (valid)
    const bom_in_middle = "Hello\xEF\xBB\xBF" ++ "World";
    const middle_result = unicode.validateString(bom_in_middle, .strict);
    try testing.expect(middle_result.valid);

    // Test sanitization of string without BOM at start
    const no_bom_string = "Hello\x00World"; // NULL instead of BOM
    const sanitized = try unicode.validation.sanitizeString(allocator, no_bom_string);
    defer allocator.free(sanitized);
    // Should replace NULL with replacement character
    try testing.expect(std.mem.indexOf(u8, sanitized, "\xEF\xBF\xBD") != null);
}

test "RFC 5198 - BOM Edge Cases" {
    // Test various BOM positions and scenarios
    const test_cases = [_]struct {
        name: []const u8,
        input: []const u8,
        mode: unicode.UnicodeMode,
        should_pass: bool,
        expected_error: ?unicode.ErrorCode,
    }{
        // BOM at start - should fail in strict/sanitize
        .{ .name = "BOM at start - strict", .input = "\xEF\xBB\xBF", .mode = .strict, .should_pass = false, .expected_error = .bom_at_string_start },
        .{ .name = "BOM at start - sanitize", .input = "\xEF\xBB\xBF", .mode = .sanitize, .should_pass = false, .expected_error = .bom_at_string_start },
        .{ .name = "BOM at start - permissive", .input = "\xEF\xBB\xBF", .mode = .permissive, .should_pass = true, .expected_error = null },

        // BOM in middle - should pass (valid U+FEFF)
        .{ .name = "BOM in middle - strict", .input = "A\xEF\xBB\xBF" ++ "B", .mode = .strict, .should_pass = true, .expected_error = null },
        .{ .name = "BOM in middle - sanitize", .input = "A\xEF\xBB\xBF" ++ "B", .mode = .sanitize, .should_pass = true, .expected_error = null },
        .{ .name = "BOM in middle - permissive", .input = "A\xEF\xBB\xBF" ++ "B", .mode = .permissive, .should_pass = true, .expected_error = null },

        // BOM at end - should pass (valid U+FEFF)
        .{ .name = "BOM at end - strict", .input = "Hello\xEF\xBB\xBF", .mode = .strict, .should_pass = true, .expected_error = null },

        // Multiple BOMs - start should fail, middle should pass
        .{ .name = "Multiple BOMs", .input = "\xEF\xBB\xBF" ++ "A\xEF\xBB\xBF" ++ "B", .mode = .strict, .should_pass = false, .expected_error = .bom_at_string_start },

        // Partial BOM sequences at start (should not trigger BOM error)
        .{ .name = "Partial BOM - EF BB", .input = "\xEF\xBB", .mode = .strict, .should_pass = false, .expected_error = .incomplete_utf8_sequence },
        .{ .name = "Partial BOM - EF", .input = "\xEF", .mode = .strict, .should_pass = false, .expected_error = .incomplete_utf8_sequence },

        // Empty string
        .{ .name = "Empty string", .input = "", .mode = .strict, .should_pass = true, .expected_error = null },
    };

    for (test_cases) |case| {
        const result = unicode.validateString(case.input, case.mode);

        if (result.valid != case.should_pass) {
            std.debug.print("BOM edge case failed: {s}\n", .{case.name});
            std.debug.print("  Expected valid: {}\n", .{case.should_pass});
            std.debug.print("  Got valid: {}\n", .{result.valid});
            if (result.error_code) |ec| {
                std.debug.print("  Error: {s}\n", .{ec.getMessage()});
            }
        }
        try testing.expect(result.valid == case.should_pass);

        if (case.expected_error) |expected| {
            try testing.expect(result.error_code == expected);
        }
    }
}

test "RFC 5198 - CRLF vs LF Line Ending Policy" {
    // RFC 5198 requires CRLF for network protocols, but we enforce Unix LF
    // This documents our intentional deviation

    const crlf_text = "Line1\r\nLine2\r\nLine3";
    const lf_text = "Line1\nLine2\nLine3";
    const cr_only = "Line1\rLine2\rLine3";

    // CRLF should fail in strict mode (CR is rejected)
    const crlf_result = unicode.validateString(crlf_text, .strict);
    try testing.expect(!crlf_result.valid);
    try testing.expect(crlf_result.error_code == .carriage_return_in_string);

    // LF-only should pass (Unix standard)
    const lf_result = unicode.validateString(lf_text, .strict);
    try testing.expect(lf_result.valid);

    // CR-only should fail in strict mode
    const cr_result = unicode.validateString(cr_only, .strict);
    try testing.expect(!cr_result.valid);
    try testing.expect(cr_result.error_code == .carriage_return_in_string);

    // But should pass in sanitize mode
    const cr_sanitize = unicode.validateString(cr_only, .sanitize);
    try testing.expect(cr_sanitize.valid);
}

test "RFC 3629 - UTF-8 Boundary Values" {
    // Test boundary values from UTF-8 specification
    const boundary_tests = [_]struct {
        name: []const u8,
        sequence: []const u8,
        code_point: u32,
        should_be_valid: bool,
    }{
        // 1-byte boundary
        .{ .name = "ASCII max", .sequence = "\x7F", .code_point = 0x7F, .should_be_valid = true },
        .{ .name = "Beyond ASCII", .sequence = "\x80", .code_point = 0x80, .should_be_valid = false }, // continuation byte

        // 2-byte boundaries
        .{ .name = "2-byte min", .sequence = "\xC2\x80", .code_point = 0x80, .should_be_valid = true },
        .{ .name = "2-byte max", .sequence = "\xDF\xBF", .code_point = 0x7FF, .should_be_valid = true },

        // 3-byte boundaries
        .{ .name = "3-byte min", .sequence = "\xE0\xA0\x80", .code_point = 0x800, .should_be_valid = true },
        .{ .name = "Before surrogates", .sequence = "\xED\x9F\xBF", .code_point = 0xD7FF, .should_be_valid = true },
        .{ .name = "After surrogates", .sequence = "\xEE\x80\x80", .code_point = 0xE000, .should_be_valid = true },
        .{ .name = "3-byte max", .sequence = "\xEF\xBF\xBF", .code_point = 0xFFFF, .should_be_valid = true },

        // 4-byte boundaries
        .{ .name = "4-byte min", .sequence = "\xF0\x90\x80\x80", .code_point = 0x10000, .should_be_valid = true },
        .{ .name = "Unicode max", .sequence = "\xF4\x8F\xBF\xBF", .code_point = 0x10FFFF, .should_be_valid = true },
        .{ .name = "Beyond Unicode", .sequence = "\xF4\x90\x80\x80", .code_point = 0x110000, .should_be_valid = false },
    };

    for (boundary_tests) |test_case| {
        const utf8_result = unicode.utf8.validateUtf8(test_case.sequence);

        if (utf8_result.valid != test_case.should_be_valid) {
            std.debug.print("Boundary test failed: {s}\n", .{test_case.name});
            std.debug.print("  Expected valid: {}\n", .{test_case.should_be_valid});
            std.debug.print("  Got valid: {}\n", .{utf8_result.valid});
            std.debug.print("  Code point: U+{X:0>4}\n", .{test_case.code_point});
        }
        try testing.expect(utf8_result.valid == test_case.should_be_valid);

        // If valid UTF-8, test code point decoding
        if (test_case.should_be_valid) {
            const decode_result = unicode.utf8.decodeCodePoint(test_case.sequence);
            try testing.expect(decode_result.valid);
            try testing.expect(decode_result.code_point.? == test_case.code_point);
        }
    }
}

test "RFC 3629 - Minimal Encoding Enforcement" {
    // Test that non-minimal encodings are rejected
    const non_minimal_tests = [_]struct {
        name: []const u8,
        sequence: []const u8,
        minimal_form: []const u8,
    }{
        // 2-byte overlong for 1-byte characters
        .{ .name = "Overlong ASCII A", .sequence = "\xC1\x81", .minimal_form = "A" },
        .{ .name = "Overlong ASCII DEL", .sequence = "\xC1\xFF", .minimal_form = "\x7F" },

        // 3-byte overlong for 2-byte characters
        .{ .name = "Overlong 2-byte min", .sequence = "\xE0\x82\x80", .minimal_form = "\xC2\x80" },
        .{ .name = "Overlong 2-byte max", .sequence = "\xE0\x9F\xBF", .minimal_form = "\xDF\xBF" },

        // 4-byte overlong for 3-byte characters
        .{ .name = "Overlong 3-byte min", .sequence = "\xF0\x80\xA0\x80", .minimal_form = "\xE0\xA0\x80" },
        .{ .name = "Overlong 3-byte max", .sequence = "\xF0\x8F\xBF\xBF", .minimal_form = "\xEF\xBF\xBF" },
    };

    for (non_minimal_tests) |test_case| {
        // Non-minimal encoding should be rejected
        const overlong_result = unicode.utf8.validateUtf8(test_case.sequence);
        if (overlong_result.valid) {
            std.debug.print("Minimal encoding test failed: {s} should be rejected\n", .{test_case.name});
        }
        try testing.expect(!overlong_result.valid);
        try testing.expect(overlong_result.error_code == .invalid_utf8_sequence or
            overlong_result.error_code == .overlong_utf8_sequence);

        // Minimal form should be valid
        const minimal_result = unicode.utf8.validateUtf8(test_case.minimal_form);
        try testing.expect(minimal_result.valid);
    }
}

test "RFC 2781 - Surrogate Pair Edge Cases" {
    const allocator = testing.allocator;

    // Test surrogate pair handling in escape sequences
    const surrogate_tests = [_]struct {
        name: []const u8,
        code_point: u32,
        expected_json: []const u8,
    }{
        .{ .name = "Emoji grinning", .code_point = 0x1F600, .expected_json = "\\uD83D\\uDE00" },
        .{ .name = "Supplementary min", .code_point = 0x10000, .expected_json = "\\uD800\\uDC00" },
        .{ .name = "Supplementary max", .code_point = 0x10FFFF, .expected_json = "\\uDBFF\\uDFFF" },
    };

    for (surrogate_tests) |test_case| {
        const result = try unicode.formatEscape(allocator, test_case.code_point, .json_style);
        defer allocator.free(result);

        if (!std.mem.eql(u8, result, test_case.expected_json)) {
            std.debug.print("Surrogate pair test failed: {s}\n", .{test_case.name});
            std.debug.print("  Code point: U+{X:0>6}\n", .{test_case.code_point});
            std.debug.print("  Expected: {s}\n", .{test_case.expected_json});
            std.debug.print("  Got: {s}\n", .{result});
        }
        try testing.expectEqualStrings(test_case.expected_json, result);
    }
}

test "RFC 9839 - Noncharacter Boundary Testing" {
    // Test all noncharacter ranges systematically
    const noncharacter_ranges = [_]struct {
        name: []const u8,
        start: u32,
        end: u32,
    }{
        .{ .name = "Arabic block noncharacters", .start = 0xFDD0, .end = 0xFDEF },
        .{ .name = "BMP plane endings", .start = 0xFFFE, .end = 0xFFFF },
        .{ .name = "Plane 1 endings", .start = 0x1FFFE, .end = 0x1FFFF },
        .{ .name = "Plane 2 endings", .start = 0x2FFFE, .end = 0x2FFFF },
        .{ .name = "Plane 15 endings", .start = 0xFFFFE, .end = 0xFFFFF },
        .{ .name = "Plane 16 endings", .start = 0x10FFFE, .end = 0x10FFFF },
    };

    for (noncharacter_ranges) |range| {
        var cp = range.start;
        while (cp <= range.end) : (cp += 1) {
            const class = unicode.codepoint.classifyCodePoint(cp);
            if (class != .noncharacter) {
                std.debug.print("Noncharacter test failed: U+{X:0>6} in {s} should be noncharacter\n", .{ cp, range.name });
            }
            try testing.expect(class == .noncharacter);

            // Should be rejected in strict mode
            const result = unicode.validateCodePoint(cp, .strict);
            try testing.expect(result == .noncharacter_in_string);
        }
    }

    // Test boundaries around noncharacter ranges
    try testing.expect(unicode.codepoint.classifyCodePoint(0xFDCF) == .valid); // Before range
    try testing.expect(unicode.codepoint.classifyCodePoint(0xFDF0) == .valid); // After range
    try testing.expect(unicode.codepoint.classifyCodePoint(0xFFFD) == .valid); // Replacement char (valid)
}

test "RFC Compliance - Truncated Sequence Handling" {
    // Test behavior with truncated UTF-8 sequences at various lengths
    const truncated_tests = [_]struct {
        name: []const u8,
        sequence: []const u8,
        expected_consumed: usize,
    }{
        .{ .name = "2-byte truncated", .sequence = "\xC2", .expected_consumed = 1 },
        .{ .name = "3-byte truncated at 1", .sequence = "\xE0", .expected_consumed = 1 },
        .{ .name = "3-byte truncated at 2", .sequence = "\xE0\xA0", .expected_consumed = 2 },
        .{ .name = "4-byte truncated at 1", .sequence = "\xF0", .expected_consumed = 1 },
        .{ .name = "4-byte truncated at 2", .sequence = "\xF0\x90", .expected_consumed = 2 },
        .{ .name = "4-byte truncated at 3", .sequence = "\xF0\x90\x80", .expected_consumed = 3 },
    };

    for (truncated_tests) |test_case| {
        const result = unicode.utf8.decodeCodePoint(test_case.sequence);

        if (result.valid) {
            std.debug.print("Truncated sequence test failed: {s} should be invalid\n", .{test_case.name});
        }
        try testing.expect(!result.valid);
        try testing.expect(result.error_code == .incomplete_utf8_sequence);
        try testing.expect(result.bytes_consumed == test_case.expected_consumed);
    }
}

test "RFC Compliance - String Validation Error Positioning" {
    // Test that error positions are correctly reported
    const position_tests = [_]struct {
        name: []const u8,
        input: []const u8,
        expected_position: usize,
    }{
        .{ .name = "NULL at start", .input = "\x00Hello", .expected_position = 0 },
        .{ .name = "NULL in middle", .input = "Hello\x00World", .expected_position = 5 },
        .{ .name = "NULL at end", .input = "Hello\x00", .expected_position = 5 },
        .{ .name = "Invalid UTF-8", .input = "Hello\xFF", .expected_position = 5 },
        .{ .name = "Surrogate", .input = "Test\xED\xA0\x80", .expected_position = 4 },
        .{ .name = "Multiple issues", .input = "A\x00B\x85C", .expected_position = 1 }, // First issue
    };

    for (position_tests) |test_case| {
        const result = unicode.validateString(test_case.input, .strict);

        if (result.valid) {
            std.debug.print("Position test failed: {s} should be invalid\n", .{test_case.name});
            continue;
        }

        try testing.expect(!result.valid);
        if (result.position != test_case.expected_position) {
            std.debug.print("Position test failed: {s}\n", .{test_case.name});
            std.debug.print("  Expected position: {}\n", .{test_case.expected_position});
            std.debug.print("  Got position: {?}\n", .{result.position});
        }
        try testing.expect(result.position.? == test_case.expected_position);
    }
}
