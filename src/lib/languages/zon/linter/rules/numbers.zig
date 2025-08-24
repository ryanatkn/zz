/// ZON Linter - Number Validation Rules
///
/// Number format validation for ZON numeric literals
const std = @import("std");
const ZonToken = @import("../../token/types.zig").Token;
const unpackSpan = @import("../../../../span/mod.zig").unpackSpan;

// Import core linter types
const Linter = @import("../core.zig").Linter;
const EnabledRules = @import("../core.zig").EnabledRules;

/// Validate number tokens for format and parsing issues
pub fn validateNumber(linter: *Linter, token: ZonToken, _: EnabledRules) !void {
    const span = unpackSpan(token.span);
    const text = linter.source[span.start..span.end];

    // Validate number format (ZON supports various number formats)
    _ = std.fmt.parseFloat(f64, text) catch |err| {
        // Try parsing as integer
        _ = std.fmt.parseInt(i64, text, 0) catch {
            try linter.addDiagnostic(
                .invalid_number,
                try std.fmt.allocPrint(linter.allocator, "Invalid number format: {}", .{err}),
                span.start,
                span.end,
                .err,
            );
        };
    };
}
