/// JSON Linter - Number Validation Rules
///
/// Number-specific validation including leading zeros, precision, and format checks
const std = @import("std");
const char_utils = @import("../../../../char/mod.zig");
const unpackSpan = @import("../../../../span/mod.zig").unpackSpan;

// Import core linter types
const Linter = @import("../core.zig").Linter;
const EnabledRules = @import("../core.zig").EnabledRules;
const Token = @import("../../token/mod.zig").Token;

pub fn validateNumber(linter: *Linter, token: Token, enabled_rules: EnabledRules) !void {
    const span = unpackSpan(token.span);
    const text = linter.source[span.start..span.end];

    if (text.len == 0) return;

    // Check for leading zeros
    if (enabled_rules.contains(.no_leading_zeros) and !linter.options.allow_leading_zeros) {
        if (text.len > 1 and text[0] == '0' and char_utils.isDigit(text[1])) {
            try linter.addDiagnostic(
                .no_leading_zeros,
                "Number has leading zero",
                .warning,
                span,
            );
        }
    }

    // Check number precision
    if (enabled_rules.contains(.large_number_precision) and linter.options.warn_on_large_numbers) {
        if (std.mem.indexOf(u8, text, ".")) |dot_pos| {
            const decimal_part = text[dot_pos + 1 ..];
            // Remove exponent part if present
            var decimal_digits = decimal_part;
            if (std.mem.indexOfAny(u8, decimal_part, "eE")) |exp_pos| {
                decimal_digits = decimal_part[0..exp_pos];
            }

            if (decimal_digits.len > linter.options.max_number_precision) {
                try linter.addDiagnostic(
                    .large_number_precision,
                    "Number has high precision that may cause floating-point issues",
                    .warning,
                    span,
                );
            }
        }
    }

    // Validate number format
    _ = std.fmt.parseFloat(f64, text) catch {
        try linter.addDiagnostic(
            .invalid_number,
            "Number format is invalid",
            .err,
            span,
        );
    };
}
