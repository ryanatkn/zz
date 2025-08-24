/// ZON Linter - Array Validation Rules
///
/// Array structure validation including element count and depth checking
const std = @import("std");
const TokenIterator = @import("../../../../token/iterator.zig").TokenIterator;
const ZonToken = @import("../../token/types.zig").Token;
const unpackSpan = @import("../../../../span/mod.zig").unpackSpan;

// Import core linter types
const Linter = @import("../core.zig").Linter;
const EnabledRules = @import("../core.zig").EnabledRules;
const ValidationError = @import("../core.zig").ValidationError;

// Import utilities
const objects = @import("objects.zig");

/// Validate array structures with element count and depth checking
pub fn validateArray(linter: *Linter, iter: *TokenIterator, start_token: ZonToken, enabled_rules: EnabledRules) ValidationError!void {
    const start_span = unpackSpan(start_token.span);

    // Check depth
    linter.depth += 1;
    defer linter.depth -= 1;

    if (enabled_rules.contains(.max_depth_exceeded) and linter.depth > linter.options.max_depth) {
        try linter.addDiagnostic(
            .max_depth_exceeded,
            "Structure exceeds maximum depth limit",
            start_span.start,
            start_span.end,
            .err,
        );
        // Skip to end of array
        try objects.skipToMatchingBrace(linter, iter, .array_end);
        return;
    }

    var element_count: u32 = 0;

    while (true) {
        const token = linter.peekNonTrivia(iter) orelse break;

        if (token.kind == .array_end or token.kind == .struct_end) {
            _ = linter.nextNonTrivia(iter); // Consume ] or }
            break;
        }

        // Validate element
        try linter.validateValue(iter, enabled_rules);
        element_count += 1;

        // Check for comma
        const next = linter.peekNonTrivia(iter);
        if (next != null and next.?.kind == .comma) {
            _ = linter.nextNonTrivia(iter); // Consume comma
        }
    }

    // Check array size
    if (enabled_rules.contains(.large_structure) and element_count > linter.options.max_array_size) {
        try linter.addDiagnostic(
            .large_structure,
            "Array has too many elements",
            start_span.start,
            start_span.end,
            .warning,
        );
    }
}
