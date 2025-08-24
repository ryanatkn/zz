const std = @import("std");

/// JSON-specific patterns and language utilities
///
/// Self-contained pattern matching for JSON parsing without dependencies on old modules.
/// Provides efficient enum-based pattern matching for delimiters and literals.
/// JSON delimiter types
pub const JsonDelimiterType = enum(u8) {
    left_brace, // {
    right_brace, // }
    left_bracket, // [
    right_bracket, // ]
    comma, // ,
    colon, // :
};

/// JSON literal types
pub const JsonLiteralType = enum(u8) {
    true_literal,
    false_literal,
    null_literal,
};

/// Delimiter operations
pub const JsonDelimiters = struct {
    pub const KindType = JsonDelimiterType;

    /// Get delimiter type from character
    pub fn fromChar(char: u8) ?JsonDelimiterType {
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
    pub fn toChar(delimiter: JsonDelimiterType) u8 {
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
    pub fn description(delimiter: JsonDelimiterType) []const u8 {
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
pub const JsonLiterals = struct {
    pub const KindType = JsonLiteralType;

    /// Get literal type from first character
    pub fn fromFirstChar(char: u8) ?JsonLiteralType {
        return switch (char) {
            't' => .true_literal,
            'f' => .false_literal,
            'n' => .null_literal,
            else => null,
        };
    }

    /// Get text for literal
    pub fn text(literal: JsonLiteralType) []const u8 {
        return switch (literal) {
            .true_literal => "true",
            .false_literal => "false",
            .null_literal => "null",
        };
    }

    /// Get token kind for literal (using new token system)
    pub fn tokenKind(literal: JsonLiteralType) @import("token/mod.zig").JsonTokenKind {
        return switch (literal) {
            .true_literal => .boolean_true,
            .false_literal => .boolean_false,
            .null_literal => .null_value,
        };
    }
};

/// Lint rule operations - using the existing JsonRuleType enum
pub const JsonLintRules = struct {
    pub const KindType = @import("linter/mod.zig").JsonRuleType;

    /// Get rule name
    pub fn name(rule: KindType) []const u8 {
        return switch (rule) {
            .no_duplicate_keys => "no_duplicate_keys",
            .no_leading_zeros => "no_leading_zeros",
            .valid_string_encoding => "valid_string_encoding",
            .max_depth_exceeded => "max_depth_exceeded",
            .large_number_precision => "large_number_precision",
            .large_structure => "large_structure",
            .deep_nesting => "deep_nesting",
        };
    }

    /// Get rule from name
    pub fn fromName(rule_name: []const u8) ?KindType {
        inline for (@typeInfo(KindType).@"enum".fields) |field| {
            if (std.mem.eql(u8, rule_name, field.name)) {
                return @enumFromInt(field.value);
            }
        }
        return null;
    }

    /// Get rule severity
    pub fn severity(rule: KindType) Severity {
        return switch (rule) {
            .no_duplicate_keys => .err,
            .no_leading_zeros => .warning,
            .valid_string_encoding => .err,
            .max_depth_exceeded => .err,
            .large_number_precision => .warning,
            .large_structure => .warning,
            .deep_nesting => .warning,
        };
    }

    /// Get rule description
    pub fn description(rule: KindType) []const u8 {
        return switch (rule) {
            .no_duplicate_keys => "Object keys must be unique",
            .no_leading_zeros => "Numbers should not have leading zeros",
            .valid_string_encoding => "String encoding must be valid",
            .max_depth_exceeded => "Structure exceeds maximum depth limit",
            .large_number_precision => "Number has precision issues",
            .large_structure => "Structure is excessively large",
            .deep_nesting => "Deep nesting may be hard to read",
        };
    }
};

// Import Severity from interface
const Severity = @import("../interface.zig").RuleInfo.Severity;

// Tests
const testing = std.testing;

test "JSON delimiters" {
    // Test delimiter functionality
    try testing.expect(JsonDelimiters.fromChar('{') != null);
    try testing.expect(JsonDelimiters.fromChar('}') != null);
    try testing.expect(JsonDelimiters.fromChar('[') != null);
    try testing.expect(JsonDelimiters.fromChar(']') != null);
    try testing.expect(JsonDelimiters.fromChar(',') != null);
    try testing.expect(JsonDelimiters.fromChar(':') != null);
    try testing.expect(JsonDelimiters.fromChar('x') == null);

    // Test delimiter to char conversion
    const left_brace = JsonDelimiters.fromChar('{').?;
    try testing.expectEqual(@as(u8, '{'), JsonDelimiters.toChar(left_brace));
}

test "JSON literals" {
    // Test literal functionality
    try testing.expect(JsonLiterals.fromFirstChar('t') != null);
    try testing.expect(JsonLiterals.fromFirstChar('f') != null);
    try testing.expect(JsonLiterals.fromFirstChar('n') != null);
    try testing.expect(JsonLiterals.fromFirstChar('x') == null);

    // Test literal text
    const true_literal = JsonLiterals.fromFirstChar('t').?;
    try testing.expectEqualStrings("true", JsonLiterals.text(true_literal));
    try testing.expectEqual(@import("token/mod.zig").JsonTokenKind.boolean_true, JsonLiterals.tokenKind(true_literal));
}

test "JSON lint rules" {
    // Test lint rule functionality
    try testing.expect(JsonLintRules.fromName("no_duplicate_keys") != null);
    try testing.expect(JsonLintRules.fromName("no_leading_zeros") != null);
    try testing.expect(JsonLintRules.fromName("nonexistent_rule") == null);

    // Test lint rule properties
    const no_dup_keys = JsonLintRules.fromName("no_duplicate_keys").?;
    try testing.expectEqual(Severity.err, JsonLintRules.severity(no_dup_keys));
    try testing.expectEqualStrings("Object keys must be unique", JsonLintRules.description(no_dup_keys));
}
