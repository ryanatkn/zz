/// ZON Linter - Object Validation Rules
///
/// Object structure validation including nesting depth, field count, and duplicate keys
const std = @import("std");
const TokenIterator = @import("../../../../token/iterator.zig").TokenIterator;
const ZonToken = @import("../../token/types.zig").Token;
const TokenKind = @import("../../token/types.zig").TokenKind;
const unpackSpan = @import("../../../../span/mod.zig").unpackSpan;
const Span = @import("../../../../span/mod.zig").Span;

// Import core linter types
const Linter = @import("../core.zig").Linter;
const EnabledRules = @import("../core.zig").EnabledRules;
const ValidationError = @import("../core.zig").ValidationError;

// Import schema validation
const schema = @import("schema.zig");

/// Validate object structures with depth checking and duplicate key detection
pub fn validateObject(linter: *Linter, iter: *TokenIterator, start_token: ZonToken, enabled_rules: EnabledRules) ValidationError!void {
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
        // Skip to end of object
        try skipToMatchingBrace(linter, iter, .struct_end);
        return;
    }

    if (enabled_rules.contains(.deep_nesting) and linter.depth > linter.options.warn_on_deep_nesting) {
        try linter.addDiagnostic(
            .deep_nesting,
            "Deep nesting may be hard to read",
            start_span.start,
            start_span.end,
            .warning,
        );
    }

    // Track fields for duplicate detection
    var seen_fields = std.StringHashMap(Span).init(linter.allocator);
    defer seen_fields.deinit();

    var field_count: u32 = 0;
    var has_name = false;
    var has_version = false;

    while (true) {
        const token = linter.peekNonTrivia(iter) orelse break;

        if (token.kind == .struct_end) {
            _ = linter.nextNonTrivia(iter); // Consume }
            break;
        }

        // Expect field
        if (token.kind != .field_name) {
            _ = linter.nextNonTrivia(iter); // Skip unexpected token
            continue;
        }

        const field_token = linter.nextNonTrivia(iter).?;
        const field_span = unpackSpan(field_token.span);
        const field_text = linter.source[field_span.start..field_span.end];

        // Extract field name (remove . prefix)
        const field_name = if (field_text.len > 0 and field_text[0] == '.') field_text[1..] else field_text;

        // Track for schema validation
        if (std.mem.eql(u8, field_name, "name")) has_name = true;
        if (std.mem.eql(u8, field_name, "version")) has_version = true;

        // Check for duplicate fields
        if (enabled_rules.contains(.no_duplicate_keys) and !linter.options.allow_duplicate_keys) {
            if (seen_fields.get(field_name)) |prev_span| {
                const message = try std.fmt.allocPrint(
                    linter.allocator,
                    "Duplicate key '{s}' (previously defined at position {})",
                    .{ field_name, prev_span.start },
                );
                try linter.addDiagnosticOwned(
                    .no_duplicate_keys,
                    message,
                    field_span.start,
                    field_span.end,
                    .err,
                );
            } else {
                try seen_fields.put(field_name, Span.init(field_span.start, field_span.end));
            }
        }

        field_count += 1;

        // Expect equals
        const eq = linter.peekNonTrivia(iter);
        if (eq != null and eq.?.kind == .equals) {
            _ = linter.nextNonTrivia(iter); // Consume =
        }

        // Validate value and check types for known schemas
        const value_start = linter.peekNonTrivia(iter);
        if (value_start != null and linter.schema_type == .build_zig_zon and
            enabled_rules.contains(.invalid_field_type))
        {
            try schema.validateBuildField(linter, field_name, value_start.?, enabled_rules);
        }

        try linter.validateValue(iter, enabled_rules);

        // Check for comma
        const next = linter.peekNonTrivia(iter);
        if (next != null and next.?.kind == .comma) {
            _ = linter.nextNonTrivia(iter); // Consume comma
        }
    }

    // Check field count
    if (enabled_rules.contains(.large_structure) and field_count > linter.options.max_field_count) {
        try linter.addDiagnostic(
            .large_structure,
            "Object has too many fields",
            start_span.start,
            start_span.end,
            .warning,
        );
    }

    // Check required fields for known schemas
    if (linter.schema_type == .build_zig_zon and enabled_rules.contains(.missing_required_field)) {
        if (!has_name) {
            try linter.addDiagnostic(
                .missing_required_field,
                "Missing required field 'name' in build.zig.zon",
                start_span.start,
                start_span.start,
                .err,
            );
        }
        if (!has_version) {
            try linter.addDiagnostic(
                .missing_required_field,
                "Missing required field 'version' in build.zig.zon",
                start_span.start,
                start_span.start,
                .err,
            );
        }
    }
}

/// Skip tokens until matching closing brace is found
pub fn skipToMatchingBrace(_: *Linter, iter: *TokenIterator, end_kind: TokenKind) !void {
    var depth: u32 = 1;

    while (iter.next()) |token| {
        switch (token) {
            .zon => |t| {
                if (t.kind == .object_start or t.kind == .array_start) {
                    depth += 1;
                } else if (t.kind == end_kind) {
                    depth -= 1;
                    if (depth == 0) return;
                }
            },
            else => {},
        }
    }
}
