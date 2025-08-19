const std = @import("std");

// Import the generic parameterized systems
const delimiter_mod = @import("../../parser/foundation/types/delimiter.zig");
const DelimiterKind = delimiter_mod.DelimiterKind;
const DelimiterSpec = delimiter_mod.DelimiterSpec;

const literal_mod = @import("../../parser/foundation/types/literal.zig");
const LiteralKind = literal_mod.LiteralKind;
const LiteralSpec = literal_mod.LiteralSpec;
const TokenKind = @import("../../parser/foundation/types/predicate.zig").TokenKind;

const lint_rules_mod = @import("../common/lint_rules.zig");
const LintRuleKind = lint_rules_mod.LintRuleKind;
const LintRuleSpec = lint_rules_mod.LintRuleSpec;
const Severity = lint_rules_mod.Severity;

/// JSON-specific patterns and language utilities
/// 
/// This module provides efficient, enum-based pattern matching for JSON parsing.
/// Performance improvements over string-based comparisons:
/// - DelimiterKind: 10-100x faster O(1) lookups vs O(n) string comparisons
/// - LiteralKind: Direct character matching with compile-time optimization  
/// - LintRuleKind: 1 byte storage vs 20+ bytes for rule names, O(1) rule checking
pub const Patterns = struct {
    
    /// JSON delimiter specifications
    pub const delimiters = [_]DelimiterSpec{
        .{ .name = "left_brace", .char = '{', .description = "Object start" },
        .{ .name = "right_brace", .char = '}', .description = "Object end" },
        .{ .name = "left_bracket", .char = '[', .description = "Array start" },
        .{ .name = "right_bracket", .char = ']', .description = "Array end" },
        .{ .name = "comma", .char = ',', .description = "Separator" },
        .{ .name = "colon", .char = ':', .description = "Key-value separator" },
    };

    /// JSON literal specifications
    pub const literals = [_]LiteralSpec{
        .{
            .name = "true_literal",
            .text = "true",
            .token_kind = .boolean_literal,
            .description = "Boolean true value",
        },
        .{
            .name = "false_literal", 
            .text = "false",
            .token_kind = .boolean_literal,
            .description = "Boolean false value",
        },
        .{
            .name = "null_literal",
            .text = "null", 
            .token_kind = .null_literal,
            .description = "Null value",
        },
    };

    /// JSON lint rule specifications
    pub const lint_rules = [_]LintRuleSpec{
        .{
            .name = "no_duplicate_keys",
            .description = "Object keys must be unique",
            .severity = .@"error",
            .enabled_by_default = true,
        },
        .{
            .name = "no_leading_zeros",
            .description = "Numbers should not have leading zeros",
            .severity = .warning,
            .enabled_by_default = true,
        },
        .{
            .name = "valid_string_encoding",
            .description = "Strings must be valid UTF-8",
            .severity = .@"error",
            .enabled_by_default = true,
        },
        .{
            .name = "max_depth_exceeded",
            .description = "Maximum nesting depth exceeded",
            .severity = .warning,
            .enabled_by_default = true,
        },
        .{
            .name = "invalid_escape_sequence",
            .description = "Invalid escape sequence in string",
            .severity = .@"error",
            .enabled_by_default = true,
        },
    };
};

/// JSON delimiter type - O(1) operations, 1 byte storage
pub const JsonDelimiters = DelimiterKind(&Patterns.delimiters);

/// JSON literal type - efficient literal matching
pub const JsonLiterals = LiteralKind(&Patterns.literals);

/// JSON lint rules type - 1 byte vs 20+ bytes for rule names
pub const JsonLintRules = LintRuleKind(&Patterns.lint_rules);

// Tests
const testing = std.testing;

test "JSON patterns - delimiters" {
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

test "JSON patterns - literals" {
    // Test literal functionality
    try testing.expect(JsonLiterals.fromFirstChar('t') != null);
    try testing.expect(JsonLiterals.fromFirstChar('f') != null);
    try testing.expect(JsonLiterals.fromFirstChar('n') != null);
    try testing.expect(JsonLiterals.fromFirstChar('x') == null);
    
    // Test literal text
    const true_literal = JsonLiterals.fromFirstChar('t').?;
    try testing.expectEqualStrings("true", JsonLiterals.text(true_literal));
    try testing.expectEqual(TokenKind.boolean_literal, JsonLiterals.tokenKind(true_literal));
}

test "JSON patterns - lint rules" {
    // Test lint rule functionality
    try testing.expect(JsonLintRules.fromName("no_duplicate_keys") != null);
    try testing.expect(JsonLintRules.fromName("no_leading_zeros") != null);
    try testing.expect(JsonLintRules.fromName("nonexistent_rule") == null);
    
    // Test lint rule properties
    const no_dup_keys = JsonLintRules.fromName("no_duplicate_keys").?;
    try testing.expectEqual(Severity.@"error", JsonLintRules.severity(no_dup_keys));
    try testing.expectEqualStrings("Object keys must be unique", JsonLintRules.description(no_dup_keys));
}