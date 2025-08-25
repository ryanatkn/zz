/// Unicode Processing Module
///
/// Centralized Unicode validation, classification, and escape handling
/// following RFC 9839 (Unicode Character Repertoire Subsets) and RFC 8259 (JSON).
///
/// This module provides reusable Unicode functionality for all language implementations
/// in zz, ensuring consistent behavior and compliance across parsers and formatters.
const std = @import("std");

// Re-export core functionality
pub const validation = @import("validation.zig");
pub const codepoint = @import("codepoint.zig");
pub const escape = @import("escape.zig");
pub const utf8 = @import("utf8.zig");

/// Unicode validation mode
pub const UnicodeMode = enum {
    /// Reject all problematic code points (default)
    /// - Control characters (except tab, newline)
    /// - Carriage return (enforce Unix line endings)
    /// - Surrogates (U+D800-U+DFFF)
    /// - Noncharacters (U+FDD0-U+FDEF, last 2 of each plane)
    strict,

    /// Replace problematic code points with U+FFFD
    /// - Same detection as strict mode
    /// - Replaces instead of rejecting
    sanitize,

    /// Allow everything, validate on output
    /// - No validation during parsing
    /// - Escape problematic code points on serialization
    permissive,
};

/// Result of Unicode validation
pub const ValidationResult = struct {
    /// Whether the input is valid
    valid: bool,

    /// Error code if invalid
    error_code: ?ErrorCode = null,

    /// Position of first invalid character
    position: ?usize = null,

    /// The problematic code point (if decoded)
    code_point: ?u32 = null,

    /// Human-readable error message
    message: ?[]const u8 = null,
};

/// Unicode-related error codes
pub const ErrorCode = enum {
    // Control characters
    control_character_in_string,
    carriage_return_in_string,

    // RFC 5198 compliance
    bom_at_string_start,

    // Invalid code points
    surrogate_in_string,
    noncharacter_in_string,

    // Escape sequences
    invalid_escape_sequence,
    incomplete_unicode_escape,
    invalid_unicode_escape,

    // UTF-8 errors
    invalid_utf8_sequence,
    incomplete_utf8_sequence,
    overlong_utf8_sequence,

    pub fn getMessage(self: ErrorCode) []const u8 {
        return switch (self) {
            .control_character_in_string => "Unescaped control character in string",
            .carriage_return_in_string => "Carriage return not allowed (use Unix line endings)",
            .bom_at_string_start => "BOM (Byte Order Mark) not allowed at string start per RFC 5198",
            .surrogate_in_string => "Invalid surrogate code point (U+D800-U+DFFF)",
            .noncharacter_in_string => "Noncharacter code point (not for interchange)",
            .invalid_escape_sequence => "Invalid escape sequence",
            .incomplete_unicode_escape => "Incomplete Unicode escape sequence",
            .invalid_unicode_escape => "Invalid Unicode escape sequence",
            .invalid_utf8_sequence => "Invalid UTF-8 byte sequence",
            .incomplete_utf8_sequence => "Incomplete UTF-8 byte sequence",
            .overlong_utf8_sequence => "Overlong UTF-8 encoding",
        };
    }
};

/// Quick validation for a single byte
pub fn validateByte(byte: u8, mode: UnicodeMode) ?ErrorCode {
    return validation.validateByte(byte, mode);
}

/// Validate an entire UTF-8 string
pub fn validateString(text: []const u8, mode: UnicodeMode) ValidationResult {
    return validation.validateString(text, mode);
}

/// Validate a single code point
pub fn validateCodePoint(code_point: u32, mode: UnicodeMode) ?ErrorCode {
    return validation.validateCodePoint(code_point, mode);
}

/// Parse a Unicode escape sequence (\uXXXX or \xXX)
pub fn parseUnicodeEscape(text: []const u8) escape.ParseResult {
    return escape.parseUnicodeEscape(text);
}

/// Format a code point as an escape sequence
pub fn formatEscape(allocator: std.mem.Allocator, code_point: u32, format: escape.Format) ![]u8 {
    return escape.formatEscape(allocator, code_point, format);
}
