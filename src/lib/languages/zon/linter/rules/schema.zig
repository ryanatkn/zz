/// ZON Linter - Schema Validation Rules
///
/// Schema-specific validation for known ZON file types (build.zig.zon, zz.zon)
const std = @import("std");
const TokenIterator = @import("../../../../token/iterator.zig").TokenIterator;
const ZonToken = @import("../../token/types.zig").Token;
const unpackSpan = @import("../../../../span/mod.zig").unpackSpan;

// Import core linter types
const Linter = @import("../core.zig").Linter;
const EnabledRules = @import("../core.zig").EnabledRules;

/// Schema types for known ZON file formats
pub const SchemaType = enum {
    build_zig_zon,
    zz_zon,
    unknown,
};

/// Detect schema type from initial tokens
pub fn detectSchemaType(linter: *Linter, iter: *TokenIterator) !SchemaType {
    // Look for characteristic fields to identify schema
    while (linter.nextNonTrivia(iter)) |token| {
        if (token.kind == .field_name) {
            const span = unpackSpan(token.span);
            const text = linter.source[span.start..span.end];

            // Remove . prefix if present
            const field_name = if (text.len > 0 and text[0] == '.') text[1..] else text;

            if (std.mem.eql(u8, field_name, "name") or
                std.mem.eql(u8, field_name, "version") or
                std.mem.eql(u8, field_name, "dependencies"))
            {
                return .build_zig_zon;
            }

            if (std.mem.eql(u8, field_name, "base_patterns") or
                std.mem.eql(u8, field_name, "ignored_patterns") or
                std.mem.eql(u8, field_name, "symlink_behavior"))
            {
                return .zz_zon;
            }
        }
    }

    return .unknown;
}

/// Validate fields specific to build.zig.zon schema
pub fn validateBuildField(linter: *Linter, field_name: []const u8, value_token: ZonToken, _: EnabledRules) !void {
    const span = unpackSpan(value_token.span);

    if (std.mem.eql(u8, field_name, "name") or std.mem.eql(u8, field_name, "version")) {
        // Should be string
        if (value_token.kind != .string_value) {
            try linter.addDiagnostic(
                .invalid_field_type,
                try std.fmt.allocPrint(linter.allocator, "'{s}' must be a string", .{field_name}),
                span.start,
                span.end,
                .err,
            );
        }
    } else if (std.mem.eql(u8, field_name, "dependencies")) {
        // Should be object
        if (value_token.kind != .object_start) {
            try linter.addDiagnostic(
                .invalid_field_type,
                "Dependencies must be an object",
                span.start,
                span.end,
                .err,
            );
        }
    } else if (std.mem.eql(u8, field_name, "paths")) {
        // Should be array
        if (value_token.kind != .array_start and value_token.kind != .object_start) {
            try linter.addDiagnostic(
                .invalid_field_type,
                "Paths must be an array",
                span.start,
                span.end,
                .err,
            );
        }
    }
}
