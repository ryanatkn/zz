/// JSON Linter - Array Validation Rules
///
/// Array-specific validation including depth checking, size validation, and structure analysis
const std = @import("std");
const char_utils = @import("../../../../char/mod.zig");
const unpackSpan = @import("../../../../span/mod.zig").unpackSpan;
const TokenIterator = @import("../../../../token/iterator.zig").TokenIterator;

// Import core linter types
const JsonLinter = @import("../core.zig").JsonLinter;
const EnabledRules = @import("../core.zig").EnabledRules;

// Import token types
const JsonToken = @import("../../token/mod.zig").JsonToken;
const JsonTokenKind = @import("../../token/mod.zig").JsonTokenKind;

/// Validate JSON array structure and contents
pub fn validateArray(linter: *JsonLinter, iter: *TokenIterator, start_token: JsonToken, enabled_rules: EnabledRules) !void {
    const start_span = unpackSpan(start_token.span);

    // Check depth
    linter.depth += 1;
    defer linter.depth -= 1;

    if (enabled_rules.contains(.max_depth_exceeded) and linter.depth > linter.options.max_depth) {
        try linter.addDiagnostic("max-depth-exceeded", "Structure exceeds maximum depth limit", .err, start_span);
    }

    if (enabled_rules.contains(.deep_nesting) and linter.depth > 10) {
        try linter.addDiagnostic("deep-nesting", "Deep nesting may be hard to read", .warning, start_span);
    }

    var bracket_count: u32 = 1;
    var element_count: u32 = 0;

    while (iter.next()) |token| {
        const vtoken = switch (token) {
            .json => |t| t,
            else => continue,
        };

        switch (vtoken.kind) {
            .array_start => {
                bracket_count += 1;
            },
            .array_end => {
                bracket_count -= 1;
                if (bracket_count == 0) break;
            },
            .string_value, .number_value, .boolean_true, .boolean_false, .null_value => {
                // Count elements only at the top level of this array
                if (bracket_count == 1) {
                    element_count += 1;
                }
            },
            .object_start => {
                // Count object as element if at top level
                if (bracket_count == 1) {
                    element_count += 1;
                }
            },
            .err => {
                // Error tokens indicate lexer found invalid syntax
                const span = unpackSpan(vtoken.span);
                const text = linter.source[span.start..span.end];

                // Check if it's a leading zero issue in array context
                if (enabled_rules.contains(.no_leading_zeros) and text.len > 0 and text[0] == '0') {
                    try linter.addDiagnostic("no_leading_zeros", "Number has leading zero (invalid in JSON)", .err, span);
                }
            },
            else => {
                // Other tokens don't need validation at array level
            },
        }
    }

    // Check for large array
    if (enabled_rules.contains(.large_structure) and element_count > 100) {
        try linter.addDiagnostic("large-structure", "Array has many elements and may be hard to process", .warning, start_span);
    }
}
