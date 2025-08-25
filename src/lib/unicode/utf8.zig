/// UTF-8 Encoding and Decoding Utilities
///
/// Provides functions for working with UTF-8 encoded text.
const std = @import("std");
const ErrorCode = @import("mod.zig").ErrorCode;

/// Result of UTF-8 validation
pub const ValidationResult = struct {
    valid: bool,
    error_code: ?ErrorCode = null,
    position: ?usize = null,
};

/// Result of decoding a code point
pub const DecodeResult = struct {
    valid: bool,
    code_point: ?u32 = null,
    bytes_consumed: usize = 0,
    error_code: ?ErrorCode = null,
};

/// Validate a UTF-8 string
pub fn validateUtf8(text: []const u8) ValidationResult {
    var pos: usize = 0;

    while (pos < text.len) {
        const result = decodeCodePoint(text[pos..]);
        if (!result.valid) {
            return ValidationResult{
                .valid = false,
                .error_code = result.error_code,
                .position = pos,
            };
        }
        pos += result.bytes_consumed;
    }

    return ValidationResult{ .valid = true };
}

/// Decode a single UTF-8 code point
pub fn decodeCodePoint(text: []const u8) DecodeResult {
    if (text.len == 0) {
        return DecodeResult{
            .valid = false,
            .error_code = .incomplete_utf8_sequence,
        };
    }

    const first = text[0];

    // 1-byte sequence (ASCII)
    if (first <= 0x7F) {
        return DecodeResult{
            .valid = true,
            .code_point = first,
            .bytes_consumed = 1,
        };
    }

    // Invalid start bytes per RFC 3629 Section 4:
    // - Continuation bytes (0x80-0xBF) cannot start a sequence
    // - 0xC0, 0xC1 would create overlong 2-byte sequences
    // - 0xF5-0xFF would encode beyond valid Unicode range
    if (first <= 0xBF or first == 0xC0 or first == 0xC1 or first >= 0xF5) {
        return DecodeResult{
            .valid = false,
            .error_code = .invalid_utf8_sequence,
            .bytes_consumed = 1,
        };
    }

    // 2-byte sequence
    if (first <= 0xDF) {
        if (text.len < 2) {
            return DecodeResult{
                .valid = false,
                .error_code = .incomplete_utf8_sequence,
                .bytes_consumed = 1,
            };
        }

        const second = text[1];
        if ((second & 0xC0) != 0x80) {
            return DecodeResult{
                .valid = false,
                .error_code = .invalid_utf8_sequence,
                .bytes_consumed = 1,
            };
        }

        const code_point: u32 = (@as(u32, first & 0x1F) << 6) | (second & 0x3F);

        // Check for overlong encoding
        if (code_point < 0x80) {
            return DecodeResult{
                .valid = false,
                .error_code = .overlong_utf8_sequence,
                .bytes_consumed = 2,
            };
        }

        return DecodeResult{
            .valid = true,
            .code_point = code_point,
            .bytes_consumed = 2,
        };
    }

    // 3-byte sequence
    if (first <= 0xEF) {
        if (text.len < 3) {
            return DecodeResult{
                .valid = false,
                .error_code = .incomplete_utf8_sequence,
                .bytes_consumed = text.len,
            };
        }

        const second = text[1];
        const third = text[2];

        if ((second & 0xC0) != 0x80 or (third & 0xC0) != 0x80) {
            return DecodeResult{
                .valid = false,
                .error_code = .invalid_utf8_sequence,
                .bytes_consumed = 1,
            };
        }

        const code_point: u32 = (@as(u32, first & 0x0F) << 12) |
            (@as(u32, second & 0x3F) << 6) |
            (third & 0x3F);

        // Check for overlong encoding
        if (code_point < 0x800) {
            return DecodeResult{
                .valid = false,
                .error_code = .overlong_utf8_sequence,
                .bytes_consumed = 3,
            };
        }

        return DecodeResult{
            .valid = true,
            .code_point = code_point,
            .bytes_consumed = 3,
        };
    }

    // 4-byte sequence
    if (first <= 0xF7) {
        if (text.len < 4) {
            return DecodeResult{
                .valid = false,
                .error_code = .incomplete_utf8_sequence,
                .bytes_consumed = text.len,
            };
        }

        const second = text[1];
        const third = text[2];
        const fourth = text[3];

        if ((second & 0xC0) != 0x80 or (third & 0xC0) != 0x80 or (fourth & 0xC0) != 0x80) {
            return DecodeResult{
                .valid = false,
                .error_code = .invalid_utf8_sequence,
                .bytes_consumed = 1,
            };
        }

        const code_point: u32 = (@as(u32, first & 0x07) << 18) |
            (@as(u32, second & 0x3F) << 12) |
            (@as(u32, third & 0x3F) << 6) |
            (fourth & 0x3F);

        // Check for overlong encoding
        if (code_point < 0x10000) {
            return DecodeResult{
                .valid = false,
                .error_code = .overlong_utf8_sequence,
                .bytes_consumed = 4,
            };
        }

        // Check for values beyond Unicode range
        if (code_point > 0x10FFFF) {
            return DecodeResult{
                .valid = false,
                .error_code = .invalid_utf8_sequence,
                .bytes_consumed = 4,
            };
        }

        return DecodeResult{
            .valid = true,
            .code_point = code_point,
            .bytes_consumed = 4,
        };
    }

    // Invalid UTF-8 start byte
    return DecodeResult{
        .valid = false,
        .error_code = .invalid_utf8_sequence,
        .bytes_consumed = 1,
    };
}

/// Encode a code point to UTF-8
pub fn encodeCodePoint(buffer: []u8, code_point: u32) !usize {
    if (code_point > 0x10FFFF) {
        return error.InvalidCodePoint;
    }

    // 1-byte sequence
    if (code_point <= 0x7F) {
        if (buffer.len < 1) return error.BufferTooSmall;
        buffer[0] = @intCast(code_point);
        return 1;
    }

    // 2-byte sequence
    if (code_point <= 0x7FF) {
        if (buffer.len < 2) return error.BufferTooSmall;
        buffer[0] = @intCast(0xC0 | (code_point >> 6));
        buffer[1] = @intCast(0x80 | (code_point & 0x3F));
        return 2;
    }

    // 3-byte sequence
    if (code_point <= 0xFFFF) {
        if (buffer.len < 3) return error.BufferTooSmall;
        buffer[0] = @intCast(0xE0 | (code_point >> 12));
        buffer[1] = @intCast(0x80 | ((code_point >> 6) & 0x3F));
        buffer[2] = @intCast(0x80 | (code_point & 0x3F));
        return 3;
    }

    // 4-byte sequence
    if (buffer.len < 4) return error.BufferTooSmall;
    buffer[0] = @intCast(0xF0 | (code_point >> 18));
    buffer[1] = @intCast(0x80 | ((code_point >> 12) & 0x3F));
    buffer[2] = @intCast(0x80 | ((code_point >> 6) & 0x3F));
    buffer[3] = @intCast(0x80 | (code_point & 0x3F));
    return 4;
}

/// Get the expected byte count for a UTF-8 sequence based on the first byte
pub fn getSequenceLength(first_byte: u8) usize {
    if (first_byte <= 0x7F) return 1;
    if (first_byte <= 0xBF) return 0; // Invalid
    if (first_byte <= 0xDF) return 2;
    if (first_byte <= 0xEF) return 3;
    if (first_byte <= 0xF7) return 4;
    return 0; // Invalid
}

/// Check if a byte is a UTF-8 continuation byte
pub fn isContinuationByte(byte: u8) bool {
    return (byte & 0xC0) == 0x80;
}

// Tests
const testing = std.testing;

test "decodeCodePoint - ASCII" {
    const result = decodeCodePoint("A");
    try testing.expect(result.valid);
    try testing.expect(result.code_point.? == 0x41);
    try testing.expect(result.bytes_consumed == 1);
}

test "decodeCodePoint - 2-byte sequence" {
    const text = "\xC3\xA9"; // é (U+00E9)
    const result = decodeCodePoint(text);
    try testing.expect(result.valid);
    try testing.expect(result.code_point.? == 0xE9);
    try testing.expect(result.bytes_consumed == 2);
}

test "decodeCodePoint - 3-byte sequence" {
    const text = "\xE2\x82\xAC"; // € (U+20AC)
    const result = decodeCodePoint(text);
    try testing.expect(result.valid);
    try testing.expect(result.code_point.? == 0x20AC);
    try testing.expect(result.bytes_consumed == 3);
}

test "decodeCodePoint - 4-byte sequence" {
    const text = "\xF0\x9F\x98\x80"; // 😀 (U+1F600)
    const result = decodeCodePoint(text);
    try testing.expect(result.valid);
    try testing.expect(result.code_point.? == 0x1F600);
    try testing.expect(result.bytes_consumed == 4);
}

test "decodeCodePoint - invalid sequences" {
    // Invalid start byte
    const result1 = decodeCodePoint("\x80");
    try testing.expect(!result1.valid);
    try testing.expect(result1.error_code == .invalid_utf8_sequence);

    // Incomplete sequence
    const result2 = decodeCodePoint("\xC3");
    try testing.expect(!result2.valid);
    try testing.expect(result2.error_code == .incomplete_utf8_sequence);

    // Invalid continuation byte
    const result3 = decodeCodePoint("\xC3\x00");
    try testing.expect(!result3.valid);
    try testing.expect(result3.error_code == .invalid_utf8_sequence);

    // Invalid start byte (C0 would create overlong encoding, now caught earlier)
    const result4 = decodeCodePoint("\xC0\x80"); // Invalid start byte per RFC 3629
    try testing.expect(!result4.valid);
    try testing.expect(result4.error_code == .invalid_utf8_sequence);
}

test "decodeCodePoint - RFC 3629 security: invalid start bytes" {
    // C0 (would create overlong 2-byte sequences)
    const result_c0 = decodeCodePoint("\xC0\x80");
    try testing.expect(!result_c0.valid);
    try testing.expect(result_c0.error_code == .invalid_utf8_sequence);

    // C1 (would create overlong 2-byte sequences)
    const result_c1 = decodeCodePoint("\xC1\x81");
    try testing.expect(!result_c1.valid);
    try testing.expect(result_c1.error_code == .invalid_utf8_sequence);

    // F5 (would encode beyond valid Unicode range)
    const result_f5 = decodeCodePoint("\xF5\x80\x80\x80");
    try testing.expect(!result_f5.valid);
    try testing.expect(result_f5.error_code == .invalid_utf8_sequence);

    // F6-FF (would encode beyond valid Unicode range)
    const result_f6 = decodeCodePoint("\xF6\x80\x80\x80");
    try testing.expect(!result_f6.valid);
    try testing.expect(result_f6.error_code == .invalid_utf8_sequence);

    const result_ff = decodeCodePoint("\xFF\x80\x80\x80");
    try testing.expect(!result_ff.valid);
    try testing.expect(result_ff.error_code == .invalid_utf8_sequence);
}

test "encodeCodePoint" {
    var buffer: [4]u8 = undefined;

    // ASCII
    const len1 = try encodeCodePoint(&buffer, 0x41);
    try testing.expect(len1 == 1);
    try testing.expect(buffer[0] == 0x41);

    // 2-byte
    const len2 = try encodeCodePoint(&buffer, 0xE9);
    try testing.expect(len2 == 2);
    try testing.expect(buffer[0] == 0xC3);
    try testing.expect(buffer[1] == 0xA9);

    // 3-byte
    const len3 = try encodeCodePoint(&buffer, 0x20AC);
    try testing.expect(len3 == 3);
    try testing.expect(buffer[0] == 0xE2);
    try testing.expect(buffer[1] == 0x82);
    try testing.expect(buffer[2] == 0xAC);

    // 4-byte
    const len4 = try encodeCodePoint(&buffer, 0x1F600);
    try testing.expect(len4 == 4);
    try testing.expect(buffer[0] == 0xF0);
    try testing.expect(buffer[1] == 0x9F);
    try testing.expect(buffer[2] == 0x98);
    try testing.expect(buffer[3] == 0x80);
}

test "validateUtf8" {
    // Valid UTF-8
    const valid = validateUtf8("Hello, 世界! 😀");
    try testing.expect(valid.valid);
    try testing.expect(valid.error_code == null);

    // Invalid UTF-8
    const invalid = validateUtf8("Hello\x80World");
    try testing.expect(!invalid.valid);
    try testing.expect(invalid.error_code == .invalid_utf8_sequence);
    try testing.expect(invalid.position.? == 5);
}
