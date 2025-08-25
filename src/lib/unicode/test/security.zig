/// Unicode Security Tests
///
/// Tests for security vulnerabilities and attack vectors from RFCs 3629, 5198, and 9839.
const std = @import("std");
const testing = std.testing;
const unicode = @import("../mod.zig");

test "RFC 3629 Security - Path Traversal Attack Prevention" {
    // The classic "../" path traversal attack mentioned in RFC 3629 Section 10
    const valid_path = "path/./file.txt"; // U+002F U+002E U+002E U+002F
    const overlong_attack = "path\x2F\xC0\xAE\x2E\x2F" ++ "file.txt"; // overlong dot encoding

    // Valid path should pass UTF-8 validation
    const valid_result = unicode.utf8.validateUtf8(valid_path);
    try testing.expect(valid_result.valid);

    // Attack with overlong encoding should fail
    const attack_result = unicode.utf8.validateUtf8(overlong_attack);
    try testing.expect(!attack_result.valid);
    try testing.expect(attack_result.error_code == .invalid_utf8_sequence);
}

test "RFC 3629 Security - Overlong NUL Attack Prevention" {
    // The C0 80 overlong NUL attack mentioned in RFC 3629
    const valid_null = "text\x00more"; // Valid NULL
    const overlong_null = "text\xC0\x80" ++ "more"; // Overlong NULL encoding

    // Both should be detected as problematic in strict mode
    const valid_result = unicode.validateString(valid_null, .strict);
    try testing.expect(!valid_result.valid);
    try testing.expect(valid_result.error_code == .control_character_in_string);

    // Overlong encoding should fail at UTF-8 level
    const overlong_result = unicode.validateString(overlong_null, .strict);
    try testing.expect(!overlong_result.valid);
    try testing.expect(overlong_result.error_code == .invalid_utf8_sequence);
}

test "RFC 3629 Security - Additional Overlong Attack Vectors" {
    const attack_vectors = [_]struct {
        name: []const u8,
        sequence: []const u8,
        target_char: []const u8,
    }{
        .{ .name = "Overlong slash", .sequence = "\xC0\xAF", .target_char = "/" },
        .{ .name = "Overlong dot", .sequence = "\xC0\xAE", .target_char = "." },
        .{ .name = "3-byte overlong NUL", .sequence = "\xE0\x80\x80", .target_char = "\x00" },
        .{ .name = "4-byte overlong NUL", .sequence = "\xF0\x80\x80\x80", .target_char = "\x00" },
        .{ .name = "Overlong space", .sequence = "\xC0\xA0", .target_char = " " },
        .{ .name = "3-byte overlong slash", .sequence = "\xE0\x80\xAF", .target_char = "/" },
    };

    for (attack_vectors) |vector| {
        const result = unicode.utf8.validateUtf8(vector.sequence);
        if (result.valid) {
            std.debug.print("Security test failed: {s} should be rejected\n", .{vector.name});
            std.debug.print("  Sequence: ", .{});
            for (vector.sequence) |byte| {
                std.debug.print("\\x{X:0>2}", .{byte});
            }
            std.debug.print("\n  Target: {s}\n", .{vector.target_char});
        }
        try testing.expect(!result.valid);
        try testing.expect(result.error_code == .invalid_utf8_sequence or
            result.error_code == .overlong_utf8_sequence);
    }
}

test "RFC 3629 Security - Invalid Start Byte Prevention" {
    // Test all invalid start bytes that could be used in attacks
    const invalid_sequences = [_]struct {
        name: []const u8,
        sequence: []const u8,
        expected_error: unicode.ErrorCode,
    }{
        .{ .name = "C0 overlong prefix", .sequence = "\xC0\x80", .expected_error = .invalid_utf8_sequence },
        .{ .name = "C1 overlong prefix", .sequence = "\xC1\xBF", .expected_error = .invalid_utf8_sequence },
        .{ .name = "F5 beyond Unicode", .sequence = "\xF5\x80\x80\x80", .expected_error = .invalid_utf8_sequence },
        .{ .name = "F6 beyond Unicode", .sequence = "\xF6\x80\x80\x80", .expected_error = .invalid_utf8_sequence },
        .{ .name = "F7 beyond Unicode", .sequence = "\xF7\x80\x80\x80", .expected_error = .invalid_utf8_sequence },
        .{ .name = "FF invalid", .sequence = "\xFF\x80\x80\x80", .expected_error = .invalid_utf8_sequence },
        .{ .name = "Continuation as start", .sequence = "\x80", .expected_error = .invalid_utf8_sequence },
        .{ .name = "Continuation as start 2", .sequence = "\xBF", .expected_error = .invalid_utf8_sequence },
    };

    for (invalid_sequences) |seq| {
        const result = unicode.utf8.validateUtf8(seq.sequence);
        if (result.valid) {
            std.debug.print("Security test failed: {s} should be rejected\n", .{seq.name});
        }
        try testing.expect(!result.valid);
        try testing.expect(result.error_code == seq.expected_error);
    }
}

test "RFC 9839 Security - Comprehensive C1 Control Rejection" {
    // Test all C1 control characters (U+0080-U+009F) systematically
    var i: u32 = 0x80;
    while (i <= 0x9F) : (i += 1) {
        // Should be rejected in strict mode
        const result = unicode.validateCodePoint(i, .strict);
        if (result == null) {
            std.debug.print("C1 control U+{X:0>4} should be rejected in strict mode\n", .{i});
        }
        try testing.expect(result == .control_character_in_string);

        // Should pass in permissive mode
        const permissive_result = unicode.validateCodePoint(i, .permissive);
        try testing.expect(permissive_result == null);
    }
}

test "RFC 5198 Security - Line/Paragraph Separator Rejection" {
    // Unicode Line Separator U+2028 and Paragraph Separator U+2029
    // These should be treated as normal valid characters in our implementation
    // but tested to ensure we handle them correctly

    const line_sep_utf8 = "\xE2\x80\xA8"; // U+2028
    const para_sep_utf8 = "\xE2\x80\xA9"; // U+2029

    // Should pass UTF-8 validation (they're valid Unicode)
    const line_result = unicode.utf8.validateUtf8(line_sep_utf8);
    try testing.expect(line_result.valid);

    const para_result = unicode.utf8.validateUtf8(para_sep_utf8);
    try testing.expect(para_result.valid);

    // Should pass Unicode validation (they're not problematic code points)
    const line_unicode_result = unicode.validateString(line_sep_utf8, .strict);
    try testing.expect(line_unicode_result.valid);

    const para_unicode_result = unicode.validateString(para_sep_utf8, .strict);
    try testing.expect(para_unicode_result.valid);
}

test "Security - Surrogate Injection Prevention" {
    // Test that surrogates encoded as UTF-8 are properly rejected
    const surrogate_sequences = [_]struct {
        name: []const u8,
        sequence: []const u8,
        code_point: u32,
    }{
        .{ .name = "High surrogate start", .sequence = "\xED\xA0\x80", .code_point = 0xD800 },
        .{ .name = "High surrogate end", .sequence = "\xED\xAF\xBF", .code_point = 0xDBFF },
        .{ .name = "Low surrogate start", .sequence = "\xED\xB0\x80", .code_point = 0xDC00 },
        .{ .name = "Low surrogate end", .sequence = "\xED\xBF\xBF", .code_point = 0xDFFF },
    };

    for (surrogate_sequences) |seq| {
        // Should be rejected at Unicode validation level
        const result = unicode.validateString(seq.sequence, .strict);
        if (result.valid) {
            std.debug.print("Surrogate security test failed: {s} should be rejected\n", .{seq.name});
        }
        try testing.expect(!result.valid);
        try testing.expect(result.error_code == .surrogate_in_string);

        // Direct code point validation should also reject
        const cp_result = unicode.validateCodePoint(seq.code_point, .strict);
        try testing.expect(cp_result == .surrogate_in_string);
    }
}

test "Security - Mixed Attack Vector Prevention" {
    // Test combinations of attack vectors
    const mixed_attacks = [_]struct {
        name: []const u8,
        sequence: []const u8,
        expected_to_fail: bool,
    }{
        .{ .name = "Path traversal with NULL", .sequence = "path\x00\x2F\xC0\xAE\x2E\x2F" ++ "file", .expected_to_fail = true },
        .{ .name = "Surrogate with control", .sequence = "test\xED\xA0\x80\x00end", .expected_to_fail = true },
        .{ .name = "Multiple overlong sequences", .sequence = "\xC0\x80\xC0\xAF\xC0\xAE", .expected_to_fail = true },
        .{ .name = "Valid mixed with attack", .sequence = "valid\xC0\x80valid", .expected_to_fail = true },
    };

    for (mixed_attacks) |attack| {
        const result = unicode.validateString(attack.sequence, .strict);
        if (result.valid == attack.expected_to_fail) {
            std.debug.print("Mixed attack test failed: {s}\n", .{attack.name});
            std.debug.print("  Expected to fail: {}\n", .{attack.expected_to_fail});
            std.debug.print("  Actually failed: {}\n", .{!result.valid});
            if (result.error_code) |ec| {
                std.debug.print("  Error: {s}\n", .{ec.getMessage()});
            }
        }
        try testing.expect(result.valid != attack.expected_to_fail);
    }
}
