/// JSON Linter - String Validation Rules
///
/// String-specific validation including UTF-8 encoding, escape sequences, and length checks
const std = @import("std");
const Span = @import("../../../../span/mod.zig").Span;
const char_utils = @import("../../../../char/mod.zig");
const unpackSpan = @import("../../../../span/mod.zig").unpackSpan;

// Import core linter types
const Linter = @import("../core.zig").Linter;
const EnabledRules = @import("../core.zig").EnabledRules;
const Token = @import("../../token/mod.zig").Token;

pub fn validateString(linter: *Linter, token: Token, enabled_rules: EnabledRules) !void {
    const span = unpackSpan(token.span);
    const text = linter.source[span.start..span.end];

    // Check length
    if (text.len > linter.options.max_string_length) {
        if (enabled_rules.contains(.large_structure)) {
            try linter.addDiagnostic(
                .large_structure,
                "String exceeds maximum length",
                .warning,
                span,
            );
        }
    }

    // Validate UTF-8 encoding if rule is enabled
    if (enabled_rules.contains(.valid_string_encoding)) {
        if (text.len >= 2 and text[0] == '"' and text[text.len - 1] == '"') {
            const content = text[1 .. text.len - 1];
            if (!std.unicode.utf8ValidateSlice(content)) {
                try linter.addDiagnostic(
                    .valid_string_encoding,
                    "String contains invalid UTF-8 sequences",
                    .err,
                    span,
                );
            }

            // Validate escape sequences
            try validateEscapeSequences(linter, content, span, enabled_rules);
        }
    }
}

pub fn validateEscapeSequences(linter: *Linter, content: []const u8, span: Span, _: EnabledRules) !void {
    var i: usize = 0;
    while (i < content.len) {
        if (content[i] == '\\' and i + 1 < content.len) {
            const escaped = content[i + 1];
            switch (escaped) {
                '"', '\\', '/', 'b', 'f', 'n', 'r', 't' => {
                    i += 2;
                },
                'u' => {
                    // Unicode escape sequence: \uXXXX
                    if (i + 5 < content.len) {
                        const hex_digits = content[i + 2 .. i + 6];
                        for (hex_digits) |digit| {
                            if (!char_utils.isHexDigit(digit)) {
                                try linter.addDiagnostic(
                                    .invalid_escape_sequence,
                                    "Invalid Unicode escape sequence",
                                    .err,
                                    span,
                                );
                                break;
                            }
                        }
                        i += 6;
                    } else {
                        try linter.addDiagnostic(
                            .invalid_escape_sequence,
                            "Incomplete Unicode escape sequence",
                            .err,
                            span,
                        );
                        i += 2;
                    }
                },
                else => {
                    try linter.addDiagnostic(
                        .invalid_escape_sequence,
                        "Invalid escape sequence",
                        .err,
                        span,
                    );
                    i += 2;
                },
            }
        } else {
            i += 1;
        }
    }
}
