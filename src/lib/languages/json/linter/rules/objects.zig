/// JSON Linter - Object Validation Rules
///
/// Object-specific validation including duplicate keys, depth checking, and structure validation
const std = @import("std");
const char_utils = @import("../../../../char/mod.zig");
const unpackSpan = @import("../../../../span/mod.zig").unpackSpan;
const TokenIterator = @import("../../../../token/iterator.zig").TokenIterator;

// Import core linter types
const Linter = @import("../core.zig").Linter;
const EnabledRules = @import("../core.zig").EnabledRules;

// Import token types
const Token = @import("../../token/types.zig").Token;
const TokenKind = @import("../../token/types.zig").TokenKind;

/// Validate JSON object structure and contents
pub fn validateObject(linter: *Linter, iter: *TokenIterator, start_token: Token, enabled_rules: EnabledRules) !void {
    const start_span = unpackSpan(start_token.span);

    // Check depth
    linter.depth += 1;
    defer linter.depth -= 1;

    if (enabled_rules.contains(.max_depth_exceeded) and linter.depth > linter.options.max_depth) {
        try linter.addDiagnostic(.max_depth_exceeded, "Structure exceeds maximum depth limit", .err, start_span);
    }

    if (enabled_rules.contains(.deep_nesting) and linter.depth > linter.options.warn_on_deep_nesting) {
        try linter.addDiagnostic(.deep_nesting, "Deep nesting may be hard to read", .warning, start_span);
    }

    // Track object keys for duplicate detection
    var seen_keys = std.StringHashMap(void).init(linter.allocator);
    defer {
        // Free all duplicated keys before deinit
        var key_iter = seen_keys.iterator();
        while (key_iter.next()) |entry| {
            linter.allocator.free(entry.key_ptr.*);
        }
        seen_keys.deinit();
    }

    var brace_count: u32 = 1;
    var property_count: u32 = 0;

    while (iter.next()) |token| {
        const vtoken = switch (token) {
            .json => |t| t,
            else => continue,
        };

        switch (vtoken.kind) {
            .object_start => {
                brace_count += 1;
                // Check depth using token's built-in depth information
                if (enabled_rules.contains(.deep_nesting) and vtoken.depth > linter.options.warn_on_deep_nesting) {
                    const span = unpackSpan(vtoken.span);
                    try linter.addDiagnostic(.deep_nesting, "Deep nesting may be hard to read", .warning, span);
                }
            },
            .object_end => {
                brace_count -= 1;
                if (brace_count == 0) break;
            },
            .property_name => {
                property_count += 1;

                // Check for duplicate keys
                if (enabled_rules.contains(.no_duplicate_keys) and brace_count == 1) {
                    const span = unpackSpan(vtoken.span);
                    const key_text = linter.source[span.start..span.end];

                    // Remove quotes from property name for comparison
                    const unquoted_key = if (key_text.len >= 2 and key_text[0] == '"' and key_text[key_text.len - 1] == '"')
                        key_text[1 .. key_text.len - 1]
                    else
                        key_text;

                    if (seen_keys.contains(unquoted_key)) {
                        try linter.addDiagnostic(.no_duplicate_keys, "Duplicate object key found", .err, span);
                    } else {
                        try seen_keys.put(try linter.allocator.dupe(u8, unquoted_key), {});
                    }
                }
            },
            .err => {
                // Error tokens indicate lexer found invalid syntax
                const span = unpackSpan(vtoken.span);
                const text = linter.source[span.start..span.end];

                // Check if it's a leading zero issue in object context
                if (enabled_rules.contains(.no_leading_zeros) and text.len > 0 and text[0] == '0') {
                    try linter.addDiagnostic(.no_leading_zeros, "Number has leading zero (invalid in JSON)", .err, span);
                }
            },
            else => {
                // Other tokens don't need validation at object level
            },
        }
    }

    // Check for large structure
    if (enabled_rules.contains(.large_structure) and property_count > 50) {
        try linter.addDiagnostic(.large_structure, "Object has many properties and may be hard to read", .warning, start_span);
    }
}

/// Skip to matching closing brace (utility function)
pub fn skipToMatchingBrace(iter: *TokenIterator, start_kind: TokenKind) !void {
    const end_kind: TokenKind = switch (start_kind) {
        .object_start => .object_end,
        .array_start => .array_end,
        else => return,
    };

    var count: u32 = 1;
    while (iter.next()) |token| {
        const vtoken = switch (token) {
            .json => |t| t,
            else => continue,
        };

        if (vtoken.kind == start_kind) {
            count += 1;
        } else if (vtoken.kind == end_kind) {
            count -= 1;
            if (count == 0) break;
        }
    }
}
