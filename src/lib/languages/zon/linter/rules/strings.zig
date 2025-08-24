/// ZON Linter - String Validation Rules
///
/// String and identifier validation including UTF-8 encoding and ZON identifier rules
const std = @import("std");
const ZonToken = @import("../../token/types.zig").Token;
const unpackSpan = @import("../../../../span/mod.zig").unpackSpan;
const Span = @import("../../../../span/mod.zig").Span;
const char_utils = @import("../../../../char/mod.zig");

// Import core linter types
const Linter = @import("../core.zig").Linter;
const EnabledRules = @import("../core.zig").EnabledRules;

/// Validate string tokens for UTF-8 and encoding issues
pub fn validateString(linter: *Linter, token: ZonToken, enabled_rules: EnabledRules) !void {
    const span = unpackSpan(token.span);
    const text = linter.source[span.start..span.end];

    // Basic UTF-8 validation
    if (!std.unicode.utf8ValidateSlice(text)) {
        if (enabled_rules.contains(.invalid_identifier)) {
            try linter.addDiagnostic(
                .invalid_string,
                "String contains invalid UTF-8 sequences",
                span.start,
                span.end,
                .err,
            );
        }
    }
}

/// Validate field names (.field_name format)
pub fn validateField(linter: *Linter, token: ZonToken, enabled_rules: EnabledRules) !void {
    const span = unpackSpan(token.span);
    const text = linter.source[span.start..span.end];

    // Validate field name format (.field_name)
    if (text.len == 0) {
        if (enabled_rules.contains(.invalid_identifier)) {
            try linter.addDiagnostic(
                .invalid_identifier,
                "Field name cannot be empty",
                span.start,
                span.end,
                .err,
            );
        }
        return;
    }

    // Field should start with '.'
    if (text[0] != '.') {
        if (enabled_rules.contains(.invalid_identifier)) {
            try linter.addDiagnostic(
                .invalid_identifier,
                "Field name must start with '.'",
                span.start,
                span.end,
                .err,
            );
        }
        return;
    }

    // Validate the identifier part (after the dot)
    if (text.len > 1) {
        try validateIdentifierText(linter, text[1..], Span.init(span.start, span.end), enabled_rules);
    }
}

/// Validate enum literals (.enum_value format)
pub fn validateEnumLiteral(linter: *Linter, token: ZonToken, enabled_rules: EnabledRules) !void {
    const span = unpackSpan(token.span);
    const text = linter.source[span.start..span.end];

    // Enum literal should start with '.'
    if (text.len == 0 or text[0] != '.') {
        if (enabled_rules.contains(.invalid_identifier)) {
            try linter.addDiagnostic(
                .invalid_identifier,
                "Enum literal must start with '.'",
                span.start,
                span.end,
                .err,
            );
        }
    }
}

/// Validate identifier text according to ZON rules
pub fn validateIdentifierText(linter: *Linter, text: []const u8, span: Span, enabled_rules: EnabledRules) !void {
    // Check if it's a @"keyword" identifier
    if (text.len >= 3 and text[0] == '@' and text[1] == '"' and text[text.len - 1] == '"') {
        // @"keyword" syntax - the content inside quotes can be anything
        return;
    }

    // Regular identifier validation
    if (text.len == 0) return;

    // First character must be letter or underscore
    const first_char = text[0];
    if (!char_utils.isAlpha(first_char) and first_char != '_') {
        if (enabled_rules.contains(.invalid_identifier)) {
            try linter.addDiagnostic(
                .invalid_identifier,
                "Identifier must start with letter or underscore",
                span.start,
                span.end,
                .err,
            );
        }
        return;
    }

    // Remaining characters must be alphanumeric or underscore
    for (text[1..]) |char| {
        if (!char_utils.isAlphaNumeric(char) and char != '_') {
            if (enabled_rules.contains(.invalid_identifier)) {
                try linter.addDiagnostic(
                    .invalid_identifier,
                    "Identifier contains invalid character",
                    span.start,
                    span.end,
                    .err,
                );
            }
            return;
        }
    }
}
