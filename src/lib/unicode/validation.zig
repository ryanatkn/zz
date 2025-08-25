/// Unicode Validation - RFC 9839 Compliance
///
/// Implements validation for problematic Unicode code points according to
/// RFC 9839 "Unicode Character Repertoire Subsets".
const std = @import("std");
const UnicodeMode = @import("mod.zig").UnicodeMode;
const ErrorCode = @import("mod.zig").ErrorCode;
const ValidationResult = @import("mod.zig").ValidationResult;
const codepoint = @import("codepoint.zig");
const utf8_utils = @import("utf8.zig");

/// Validate a single byte (ASCII subset)
pub fn validateByte(byte: u8, mode: UnicodeMode) ?ErrorCode {
    // In permissive mode, allow everything
    if (mode == .permissive) return null;

    // Check for control characters
    switch (byte) {
        // Useful control characters allowed in all modes
        0x09 => return null, // Tab (U+0009)
        0x0A => return null, // Newline (U+000A)

        // Carriage return - rejected in strict mode for Unix line endings
        0x0D => {
            if (mode == .strict) {
                return .carriage_return_in_string;
            }
            return null; // Allowed in sanitize mode
        },

        // C0 control characters (U+0000-U+001F excluding tab/newline/CR)
        0x00...0x08, 0x0B...0x0C, 0x0E...0x1F => {
            return .control_character_in_string;
        },

        // DEL character (U+007F)
        0x7F => {
            return .control_character_in_string;
        },

        // C1 control characters (U+0080-U+009F)
        // Note: These are in the extended ASCII range
        0x80...0x9F => {
            return .control_character_in_string;
        },

        // Regular ASCII characters
        else => return null,
    }
}

/// Validate an entire UTF-8 string
pub fn validateString(text: []const u8, mode: UnicodeMode) ValidationResult {
    // Check for BOM at start per RFC 5198 (except in permissive mode)
    if (mode != .permissive and text.len >= 3 and
        text[0] == 0xEF and text[1] == 0xBB and text[2] == 0xBF)
    {
        return ValidationResult{
            .valid = false,
            .error_code = .bom_at_string_start,
            .position = 0,
            .message = ErrorCode.bom_at_string_start.getMessage(),
        };
    }

    // In permissive mode, only check for valid UTF-8
    if (mode == .permissive) {
        const utf8_result = utf8_utils.validateUtf8(text);
        if (!utf8_result.valid) {
            return ValidationResult{
                .valid = false,
                .error_code = utf8_result.error_code,
                .position = utf8_result.position,
                .message = if (utf8_result.error_code) |ec| ec.getMessage() else null,
            };
        }
        return ValidationResult{ .valid = true };
    }

    var pos: usize = 0;
    while (pos < text.len) {
        const byte = text[pos];

        // Fast path for ASCII
        if (byte < 0x80) {
            if (validateByte(byte, mode)) |error_code| {
                return ValidationResult{
                    .valid = false,
                    .error_code = error_code,
                    .position = pos,
                    .message = error_code.getMessage(),
                };
            }
            pos += 1;
            continue;
        }

        // Decode UTF-8 code point
        const decode_result = utf8_utils.decodeCodePoint(text[pos..]);
        if (!decode_result.valid) {
            return ValidationResult{
                .valid = false,
                .error_code = decode_result.error_code,
                .position = pos,
                .message = if (decode_result.error_code) |ec| ec.getMessage() else null,
            };
        }

        // Validate the code point
        if (validateCodePoint(decode_result.code_point.?, mode)) |error_code| {
            return ValidationResult{
                .valid = false,
                .error_code = error_code,
                .position = pos,
                .code_point = decode_result.code_point,
                .message = error_code.getMessage(),
            };
        }

        pos += decode_result.bytes_consumed;
    }

    return ValidationResult{ .valid = true };
}

/// Validate a Unicode code point
pub fn validateCodePoint(cp: u32, mode: UnicodeMode) ?ErrorCode {
    // In permissive mode, allow everything
    if (mode == .permissive) return null;

    const class = codepoint.classifyCodePoint(cp);

    return switch (class) {
        .control_character => .control_character_in_string,
        .carriage_return => if (mode == .strict) .carriage_return_in_string else null,
        .surrogate => .surrogate_in_string,
        .noncharacter => .noncharacter_in_string,
        .valid => null,
    };
}

/// Sanitize a string by replacing problematic code points with U+FFFD
pub fn sanitizeString(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var pos: usize = 0;
    while (pos < text.len) {
        const byte = text[pos];

        // Fast path for ASCII
        if (byte < 0x80) {
            if (validateByte(byte, .strict)) |_| {
                // Replace with U+FFFD (Replacement Character)
                try result.appendSlice("\xEF\xBF\xBD");
            } else {
                try result.append(byte);
            }
            pos += 1;
            continue;
        }

        // Decode UTF-8 code point
        const decode_result = utf8_utils.decodeCodePoint(text[pos..]);
        if (!decode_result.valid or validateCodePoint(decode_result.code_point.?, .strict) != null) {
            // Replace with U+FFFD
            try result.appendSlice("\xEF\xBF\xBD");
            pos += if (decode_result.bytes_consumed > 0) decode_result.bytes_consumed else 1;
        } else {
            // Copy valid sequence
            try result.appendSlice(text[pos .. pos + decode_result.bytes_consumed]);
            pos += decode_result.bytes_consumed;
        }
    }

    return result.toOwnedSlice();
}

// Tests
const testing = std.testing;

test "validateByte - control characters" {
    // Strict mode
    try testing.expect(validateByte(0x00, .strict) == .control_character_in_string); // NULL
    try testing.expect(validateByte(0x08, .strict) == .control_character_in_string); // Backspace
    try testing.expect(validateByte(0x09, .strict) == null); // Tab (allowed)
    try testing.expect(validateByte(0x0A, .strict) == null); // Newline (allowed)
    try testing.expect(validateByte(0x0D, .strict) == .carriage_return_in_string); // CR (rejected in strict)
    try testing.expect(validateByte(0x7F, .strict) == .control_character_in_string); // DEL

    // Sanitize mode - allows carriage return
    try testing.expect(validateByte(0x0D, .sanitize) == null);

    // Permissive mode - allows everything
    try testing.expect(validateByte(0x00, .permissive) == null);
    try testing.expect(validateByte(0x0D, .permissive) == null);
    try testing.expect(validateByte(0x7F, .permissive) == null);
}

test "validateString - basic validation" {
    // Valid string
    const valid = validateString("Hello, World!", .strict);
    try testing.expect(valid.valid);
    try testing.expect(valid.error_code == null);

    // String with NULL byte
    const with_null = validateString("Hello\x00World", .strict);
    try testing.expect(!with_null.valid);
    try testing.expect(with_null.error_code == .control_character_in_string);
    try testing.expect(with_null.position == 5);

    // String with carriage return
    const with_cr = validateString("Hello\rWorld", .strict);
    try testing.expect(!with_cr.valid);
    try testing.expect(with_cr.error_code == .carriage_return_in_string);

    // Same string in sanitize mode (CR allowed)
    const cr_sanitize = validateString("Hello\rWorld", .sanitize);
    try testing.expect(cr_sanitize.valid);

    // Permissive mode allows everything
    const null_permissive = validateString("Hello\x00World", .permissive);
    try testing.expect(null_permissive.valid);
}

test "sanitizeString - replaces problematic characters" {
    const allocator = testing.allocator;

    // String with control characters
    const input = "Hello\x00World\x08Test";
    const sanitized = try sanitizeString(allocator, input);
    defer allocator.free(sanitized);

    // U+FFFD is 3 bytes: EF BF BD
    // "Hello" + FFFD + "World" + FFFD + "Test"
    try testing.expect(sanitized.len == 5 + 3 + 5 + 3 + 4);

    // Check that control characters are replaced
    try testing.expect(std.mem.indexOf(u8, sanitized, "\x00") == null);
    try testing.expect(std.mem.indexOf(u8, sanitized, "\x08") == null);

    // Check that replacement character is present
    try testing.expect(std.mem.indexOf(u8, sanitized, "\xEF\xBF\xBD") != null);
}
