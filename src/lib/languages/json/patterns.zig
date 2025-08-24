const std = @import("std");

/// JSON-specific patterns and language utilities
///
/// Self-contained pattern matching for JSON parsing without dependencies on old modules.
/// Provides efficient enum-based pattern matching for delimiters and literals.
/// JSON delimiter types
pub const DelimiterType = enum(u8) {
    left_brace, // {
    right_brace, // }
    left_bracket, // [
    right_bracket, // ]
    comma, // ,
    colon, // :
};

/// JSON literal types
pub const LiteralType = enum(u8) {
    true_literal,
    false_literal,
    null_literal,
};

/// Delimiter operations
pub const Delimiters = struct {
    pub const KindType = DelimiterType;

    /// Get delimiter type from character
    pub fn fromChar(char: u8) ?DelimiterType {
        return switch (char) {
            '{' => .left_brace,
            '}' => .right_brace,
            '[' => .left_bracket,
            ']' => .right_bracket,
            ',' => .comma,
            ':' => .colon,
            else => null,
        };
    }

    /// Get character from delimiter type
    pub fn toChar(delimiter: DelimiterType) u8 {
        return switch (delimiter) {
            .left_brace => '{',
            .right_brace => '}',
            .left_bracket => '[',
            .right_bracket => ']',
            .comma => ',',
            .colon => ':',
        };
    }

    /// Get description of delimiter
    pub fn description(delimiter: DelimiterType) []const u8 {
        return switch (delimiter) {
            .left_brace => "Object start",
            .right_brace => "Object end",
            .left_bracket => "Array start",
            .right_bracket => "]",
            .comma => "Separator",
            .colon => "Key-value separator",
        };
    }
};

/// Literal operations
pub const Literals = struct {
    pub const KindType = LiteralType;

    /// Get literal type from first character
    pub fn fromFirstChar(char: u8) ?LiteralType {
        return switch (char) {
            't' => .true_literal,
            'f' => .false_literal,
            'n' => .null_literal,
            else => null,
        };
    }

    /// Get text for literal
    pub fn text(literal: LiteralType) []const u8 {
        return switch (literal) {
            .true_literal => "true",
            .false_literal => "false",
            .null_literal => "null",
        };
    }

    /// Get token kind for literal (using new token system)
    pub fn tokenKind(literal: LiteralType) @import("token/mod.zig").TokenKind {
        return switch (literal) {
            .true_literal => .boolean_true,
            .false_literal => .boolean_false,
            .null_literal => .null_value,
        };
    }
};

// Tests
const testing = std.testing;

test "JSON delimiters" {
    // Test delimiter functionality
    try testing.expect(Delimiters.fromChar('{') != null);
    try testing.expect(Delimiters.fromChar('}') != null);
    try testing.expect(Delimiters.fromChar('[') != null);
    try testing.expect(Delimiters.fromChar(']') != null);
    try testing.expect(Delimiters.fromChar(',') != null);
    try testing.expect(Delimiters.fromChar(':') != null);
    try testing.expect(Delimiters.fromChar('x') == null);

    // Test delimiter to char conversion
    const left_brace = Delimiters.fromChar('{').?;
    try testing.expectEqual(@as(u8, '{'), Delimiters.toChar(left_brace));
}

test "JSON literals" {
    // Test literal functionality
    try testing.expect(Literals.fromFirstChar('t') != null);
    try testing.expect(Literals.fromFirstChar('f') != null);
    try testing.expect(Literals.fromFirstChar('n') != null);
    try testing.expect(Literals.fromFirstChar('x') == null);

    // Test literal text
    const true_literal = Literals.fromFirstChar('t').?;
    try testing.expectEqualStrings("true", Literals.text(true_literal));
    try testing.expectEqual(@import("token/mod.zig").TokenKind.boolean_true, Literals.tokenKind(true_literal));
}
