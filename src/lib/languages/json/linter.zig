/// JSON Streaming Linter - Direct token stream validation
///
/// SIMPLIFIED: Validates directly from streaming tokens without building AST
/// Performance target: <1ms for 10KB JSON validation
const std = @import("std");
const TokenIterator = @import("../../token/iterator.zig").TokenIterator;
const StreamToken = @import("../../token/stream_token.zig").StreamToken;
const JsonToken = @import("stream_token.zig").JsonToken;
const JsonTokenKind = @import("stream_token.zig").JsonTokenKind;
const unpackSpan = @import("../../span/mod.zig").unpackSpan;
const Span = @import("../../span/span.zig").Span;
const char_utils = @import("../../char/mod.zig");

// Import interface types for compatibility
const interface_types = @import("../interface.zig");
const Severity = interface_types.RuleInfo.Severity;

/// Comprehensive error set for all validation operations
pub const ValidationError = error{
    OutOfMemory,
    SourceNotAvailable,
    InvalidToken,
    UnexpectedToken,
    MalformedStructure,
    ValidationFailed,
};

/// JSON-specific linting rules
pub const JsonRuleType = enum(u8) {
    no_duplicate_keys,
    no_leading_zeros,
    valid_string_encoding,
    max_depth_exceeded,
    large_number_precision,
    large_structure,
    deep_nesting,
};

/// Efficient rule set using bitflags for O(1) lookups
pub const EnabledRules = std.EnumSet(JsonRuleType);

/// Diagnostic from linting
pub const Diagnostic = struct {
    rule: []const u8,
    message: []const u8,
    severity: Severity,
    range: Span,
    fix: ?Fix = null,

    pub const Fix = struct {
        description: []const u8,
        edits: []Edit,
    };
};

/// Edit for diagnostic fixes
pub const Edit = struct {
    range: Span,
    new_text: []const u8,
};

/// JSON streaming linter with real-time validation
///
/// Features:
/// - Validates tokens as they stream (no AST needed)
/// - Duplicate key detection with hash map
/// - Number format validation during tokenization
/// - String encoding validation on the fly
/// - Nesting depth tracking in real-time
/// - Memory efficient with streaming approach
pub const JsonLinter = struct {
    allocator: std.mem.Allocator,
    options: LinterOptions,
    diagnostics: std.ArrayList(Diagnostic),
    source: []const u8,
    iterator: ?TokenIterator,

    // State tracking for streaming validation
    depth: u32,
    object_keys: std.ArrayList(std.StringHashMap(Span)),
    array_sizes: std.ArrayList(u32),
    property_count: u32,

    const Self = @This();

    pub const LinterOptions = struct {
        max_depth: u32 = 100,
        max_string_length: u32 = 65536,
        max_number_precision: u32 = 15,
        max_object_keys: u32 = 10000,
        max_array_elements: u32 = 100000,
        allow_duplicate_keys: bool = false,
        allow_leading_zeros: bool = false,
        allow_trailing_decimals: bool = true,
        require_quotes_around_keys: bool = true,
        warn_on_large_numbers: bool = true,
        warn_on_deep_nesting: u32 = 20,
    };

    /// Rule metadata for each enum value
    pub const RuleInfo = struct {
        name: []const u8,
        description: []const u8,
        severity: Severity,
        enabled_by_default: bool,
    };

    /// Built-in linting rules metadata
    pub const RULE_INFO = std.EnumArray(JsonRuleType, RuleInfo).init(.{
        .no_duplicate_keys = .{
            .name = "no_duplicate_keys",
            .description = "Object keys must be unique",
            .severity = .err,
            .enabled_by_default = true,
        },
        .no_leading_zeros = .{
            .name = "no_leading_zeros",
            .description = "Numbers should not have leading zeros",
            .severity = .warning,
            .enabled_by_default = true,
        },
        .valid_string_encoding = .{
            .name = "valid_string_encoding",
            .description = "Strings must be valid UTF-8",
            .severity = .err,
            .enabled_by_default = true,
        },
        .max_depth_exceeded = .{
            .name = "max_depth_exceeded",
            .description = "JSON structure exceeds maximum nesting depth",
            .severity = .err,
            .enabled_by_default = true,
        },
        .large_number_precision = .{
            .name = "large_number_precision",
            .description = "Number has high precision that may cause issues",
            .severity = .warning,
            .enabled_by_default = false,
        },
        .large_structure = .{
            .name = "large_structure",
            .description = "JSON structure is very large",
            .severity = .warning,
            .enabled_by_default = false,
        },
        .deep_nesting = .{
            .name = "deep_nesting",
            .description = "JSON has deep nesting that may be hard to read",
            .severity = .warning,
            .enabled_by_default = true,
        },
    });

    /// Get default enabled rules
    pub fn getDefaultRules() EnabledRules {
        var rules = EnabledRules.initEmpty();
        inline for (std.meta.fields(JsonRuleType)) |field| {
            const rule_type = @field(JsonRuleType, field.name);
            if (RULE_INFO.get(rule_type).enabled_by_default) {
                rules.insert(rule_type);
            }
        }
        return rules;
    }

    pub fn init(allocator: std.mem.Allocator, options: LinterOptions) JsonLinter {
        return JsonLinter{
            .allocator = allocator,
            .options = options,
            .diagnostics = std.ArrayList(Diagnostic).init(allocator),
            .source = "",
            .iterator = null,
            .depth = 0,
            .object_keys = std.ArrayList(std.StringHashMap(Span)).init(allocator),
            .array_sizes = std.ArrayList(u32).init(allocator),
            .property_count = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.diagnostics.items) |diag| {
            self.allocator.free(diag.message);
        }
        self.diagnostics.deinit();

        for (self.object_keys.items) |*keys| {
            keys.deinit();
        }
        self.object_keys.deinit();
        self.array_sizes.deinit();
    }

    /// Lint JSON from source directly using streaming tokens
    pub fn lintSource(self: *Self, source: []const u8, enabled_rules: EnabledRules) ![]Diagnostic {
        self.source = source;
        self.iterator = try TokenIterator.init(source, .json);

        try self.lintFromTokens(enabled_rules);

        return self.diagnostics.toOwnedSlice();
    }

    /// Lint JSON AST (compatibility layer)
    pub fn lint(self: *Self, ast: anytype, enabled_rules: EnabledRules) ![]Diagnostic {
        // Extract source from AST and lint it
        const source = ast.source;
        return self.lintSource(source, enabled_rules);
    }

    /// Main streaming validation loop
    fn lintFromTokens(self: *Self, enabled_rules: EnabledRules) !void {
        const iter = &self.iterator.?;

        // Start validation
        try self.validateValue(iter, enabled_rules);
    }

    fn validateValue(self: *Self, iter: *TokenIterator, enabled_rules: EnabledRules) ValidationError!void {
        const token = self.nextNonTrivia(iter) orelse return;

        switch (token.kind) {
            .string_value, .property_name => try self.validateString(token, enabled_rules),
            .number_value => try self.validateNumber(token, enabled_rules),
            .boolean_true, .boolean_false => {}, // No validation needed
            .null_value => {}, // No validation needed
            .object_start => try self.validateObject(iter, token, enabled_rules),
            .array_start => try self.validateArray(iter, token, enabled_rules),
            else => {}, // Skip unexpected tokens
        }
    }

    fn validateString(self: *Self, token: JsonToken, enabled_rules: EnabledRules) !void {
        const span = unpackSpan(token.span);
        const text = self.source[span.start..span.end];

        // Check length
        if (text.len > self.options.max_string_length) {
            if (enabled_rules.contains(.large_structure)) {
                try self.addDiagnostic(
                    "large_structure",
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
                    try self.addDiagnostic(
                        "valid_string_encoding",
                        "String contains invalid UTF-8 sequences",
                        .err,
                        span,
                    );
                }

                // Validate escape sequences
                try self.validateEscapeSequences(content, span, enabled_rules);
            }
        }
    }

    fn validateNumber(self: *Self, token: JsonToken, enabled_rules: EnabledRules) !void {
        const span = unpackSpan(token.span);
        const text = self.source[span.start..span.end];

        if (text.len == 0) return;

        // Check for leading zeros
        if (enabled_rules.contains(.no_leading_zeros) and !self.options.allow_leading_zeros) {
            if (text.len > 1 and text[0] == '0' and char_utils.isDigit(text[1])) {
                try self.addDiagnostic(
                    "no_leading_zeros",
                    "Number has leading zero",
                    .warning,
                    span,
                );
            }
        }

        // Check number precision
        if (enabled_rules.contains(.large_number_precision) and self.options.warn_on_large_numbers) {
            if (std.mem.indexOf(u8, text, ".")) |dot_pos| {
                const decimal_part = text[dot_pos + 1 ..];
                // Remove exponent part if present
                var decimal_digits = decimal_part;
                if (std.mem.indexOfAny(u8, decimal_part, "eE")) |exp_pos| {
                    decimal_digits = decimal_part[0..exp_pos];
                }

                if (decimal_digits.len > self.options.max_number_precision) {
                    try self.addDiagnostic(
                        "large_number_precision",
                        "Number has high precision that may cause floating-point issues",
                        .warning,
                        span,
                    );
                }
            }
        }

        // Validate number format
        _ = std.fmt.parseFloat(f64, text) catch {
            try self.addDiagnostic(
                "invalid_number",
                "Number format is invalid",
                .err,
                span,
            );
        };
    }

    fn validateObject(self: *Self, iter: *TokenIterator, start_token: JsonToken, enabled_rules: EnabledRules) !void {
        const start_span = unpackSpan(start_token.span);

        // Check depth
        self.depth += 1;
        defer self.depth -= 1;

        if (enabled_rules.contains(.max_depth_exceeded) and self.depth > self.options.max_depth) {
            try self.addDiagnostic(
                "max_depth_exceeded",
                "JSON nesting depth exceeds maximum limit",
                .err,
                Span.init(start_span.start, start_span.end),
            );
            // Skip to end of object
            try self.skipToMatchingBrace(iter, .object_end);
            return;
        }

        if (enabled_rules.contains(.deep_nesting) and self.depth > self.options.warn_on_deep_nesting) {
            try self.addDiagnostic(
                "deep_nesting",
                "JSON structure has deep nesting",
                .warning,
                Span.init(start_span.start, start_span.end),
            );
        }

        // Track keys for duplicate detection
        var seen_keys = std.StringHashMap(Span).init(self.allocator);
        defer seen_keys.deinit();

        var property_count: u32 = 0;

        while (true) {
            const token = self.peekNonTrivia(iter) orelse break;

            if (token.kind == .object_end) {
                _ = self.nextNonTrivia(iter); // Consume }
                break;
            }

            // Expect property name
            if (token.kind != .property_name) {
                _ = self.nextNonTrivia(iter); // Skip unexpected token
                continue;
            }

            const name_token = self.nextNonTrivia(iter).?;
            const name_span = unpackSpan(name_token.span);
            const name_text = self.source[name_span.start..name_span.end];

            // Extract key content (remove quotes)
            const key_content = if (name_text.len >= 2 and name_text[0] == '"' and name_text[name_text.len - 1] == '"')
                name_text[1 .. name_text.len - 1]
            else
                name_text;

            // Check for duplicate keys
            if (enabled_rules.contains(.no_duplicate_keys) and !self.options.allow_duplicate_keys) {
                if (seen_keys.get(key_content)) |_| {
                    try self.addDiagnostic(
                        "no_duplicate_keys",
                        "Duplicate object key",
                        .err,
                        Span.init(name_span.start, name_span.end),
                    );
                } else {
                    try seen_keys.put(key_content, Span.init(name_span.start, name_span.end));
                }
            }

            property_count += 1;

            // Expect colon
            const colon = self.peekNonTrivia(iter);
            if (colon != null and colon.?.kind == .colon) {
                _ = self.nextNonTrivia(iter); // Consume colon
            }

            // Validate value
            try self.validateValue(iter, enabled_rules);

            // Check for comma
            const next = self.peekNonTrivia(iter);
            if (next != null and next.?.kind == .comma) {
                _ = self.nextNonTrivia(iter); // Consume comma
            }
        }

        // Check object size
        if (enabled_rules.contains(.large_structure) and property_count > self.options.max_object_keys) {
            try self.addDiagnostic(
                "large_structure",
                "Object has too many keys",
                .warning,
                Span.init(start_span.start, start_span.end),
            );
        }
    }

    fn validateArray(self: *Self, iter: *TokenIterator, start_token: JsonToken, enabled_rules: EnabledRules) !void {
        const start_span = unpackSpan(start_token.span);

        // Check depth
        self.depth += 1;
        defer self.depth -= 1;

        if (enabled_rules.contains(.max_depth_exceeded) and self.depth > self.options.max_depth) {
            try self.addDiagnostic(
                "max_depth_exceeded",
                "JSON nesting depth exceeds maximum limit",
                .err,
                Span.init(start_span.start, start_span.end),
            );
            // Skip to end of array
            try self.skipToMatchingBrace(iter, .array_end);
            return;
        }

        var element_count: u32 = 0;

        while (true) {
            const token = self.peekNonTrivia(iter) orelse break;

            if (token.kind == .array_end) {
                _ = self.nextNonTrivia(iter); // Consume ]
                break;
            }

            // Validate element
            try self.validateValue(iter, enabled_rules);
            element_count += 1;

            // Check for comma
            const next = self.peekNonTrivia(iter);
            if (next != null and next.?.kind == .comma) {
                _ = self.nextNonTrivia(iter); // Consume comma
            }
        }

        // Check array size
        if (enabled_rules.contains(.large_structure) and element_count > self.options.max_array_elements) {
            try self.addDiagnostic(
                "large_structure",
                "Array has too many elements",
                .warning,
                Span.init(start_span.start, start_span.end),
            );
        }
    }

    fn validateEscapeSequences(self: *Self, content: []const u8, span: Span, _: EnabledRules) !void {
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
                                    try self.addDiagnostic(
                                        "invalid_escape_sequence",
                                        "Invalid Unicode escape sequence",
                                        .err,
                                        span,
                                    );
                                    break;
                                }
                            }
                            i += 6;
                        } else {
                            try self.addDiagnostic(
                                "invalid_escape_sequence",
                                "Incomplete Unicode escape sequence",
                                .err,
                                span,
                            );
                            i += 2;
                        }
                    },
                    else => {
                        try self.addDiagnostic(
                            "invalid_escape_sequence",
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

    fn skipToMatchingBrace(_: *Self, iter: *TokenIterator, end_kind: JsonTokenKind) !void {
        var depth: u32 = 1;

        while (iter.next()) |token| {
            switch (token) {
                .json => |t| {
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

    fn addDiagnostic(self: *Self, rule: []const u8, message: []const u8, severity: Severity, span: Span) !void {
        const owned_message = try self.allocator.dupe(u8, message);
        try self.diagnostics.append(Diagnostic{
            .rule = rule,
            .message = owned_message,
            .severity = severity,
            .range = span,
            .fix = null,
        });
    }

    fn peekNonTrivia(self: *Self, iter: *TokenIterator) ?JsonToken {
        _ = self;
        while (iter.peek()) |token| {
            switch (token) {
                .json => |t| {
                    if (t.kind != .whitespace and t.kind != .comment) {
                        return t;
                    }
                    _ = iter.next(); // Skip trivia
                },
                else => return null,
            }
        }
        return null;
    }

    fn nextNonTrivia(self: *Self, iter: *TokenIterator) ?JsonToken {
        _ = self;
        while (iter.next()) |token| {
            switch (token) {
                .json => |t| {
                    if (t.kind != .whitespace and t.kind != .comment) {
                        return t;
                    }
                },
                else => return null,
            }
        }
        return null;
    }
};

/// Convenience function for basic JSON linting
pub fn lintJson(allocator: std.mem.Allocator, ast: anytype, enabled_rules: EnabledRules) ![]Diagnostic {
    var linter = JsonLinter.init(allocator, .{});
    defer linter.deinit();

    return linter.lint(ast, enabled_rules);
}

// Tests will be updated separately to use the new streaming interface
