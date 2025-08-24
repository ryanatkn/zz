/// JSON Linter - Core Infrastructure and Main Logic
///
/// Core linting infrastructure with streaming token validation
const std = @import("std");
const TokenIterator = @import("../../../token/iterator.zig").TokenIterator;
const Token = @import("../../../token/stream_token.zig").Token;
const TokenKind = @import("../token/mod.zig").TokenKind;
const unpackSpan = @import("../../../span/mod.zig").unpackSpan;
const Span = @import("../../../span/span.zig").Span;
const char_utils = @import("../../../char/mod.zig");

// Import interface types for compatibility
const interface_types = @import("../../interface.zig");
const Severity = interface_types.Severity;

// Import rule implementations
const linter_rules = @import("rules/mod.zig");

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
pub const RuleType = enum(u8) {
    no_duplicate_keys,
    no_leading_zeros,
    valid_string_encoding,
    max_depth_exceeded,
    large_number_precision,
    large_structure,
    deep_nesting,
    // Additional rules found in code
    invalid_number,
    invalid_escape_sequence,
    syntax_error,
};

/// Efficient rule set using bitflags for O(1) lookups
pub const EnabledRules = std.EnumSet(RuleType);

/// Diagnostic from linting (enum-based, zero allocation for rules)
pub const Diagnostic = @import("../../interface.zig").Diagnostic(RuleType);

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
pub const Linter = struct {
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
        description: []const u8,
        severity: Severity,
        enabled_by_default: bool,
    };

    /// Built-in linting rules metadata
    pub const RULE_INFO = std.EnumArray(RuleType, RuleInfo).init(.{
        .no_duplicate_keys = .{
            .description = "Object keys must be unique",
            .severity = .err,
            .enabled_by_default = true,
        },
        .no_leading_zeros = .{
            .description = "Numbers should not have leading zeros",
            .severity = .warning,
            .enabled_by_default = true,
        },
        .valid_string_encoding = .{
            .description = "Strings must be valid UTF-8",
            .severity = .err,
            .enabled_by_default = true,
        },
        .max_depth_exceeded = .{
            .description = "JSON structure exceeds maximum nesting depth",
            .severity = .err,
            .enabled_by_default = true,
        },
        .large_number_precision = .{
            .description = "Number has high precision that may cause issues",
            .severity = .warning,
            .enabled_by_default = false,
        },
        .large_structure = .{
            .description = "JSON structure is very large",
            .severity = .warning,
            .enabled_by_default = false,
        },
        .deep_nesting = .{
            .description = "JSON has deep nesting that may be hard to read",
            .severity = .warning,
            .enabled_by_default = true,
        },
        .invalid_number = .{
            .description = "Number format is invalid",
            .severity = .err,
            .enabled_by_default = true,
        },
        .invalid_escape_sequence = .{
            .description = "String contains invalid escape sequence",
            .severity = .err,
            .enabled_by_default = true,
        },
        .syntax_error = .{
            .description = "Invalid JSON syntax",
            .severity = .err,
            .enabled_by_default = true,
        },
    });

    /// Get default enabled rules
    pub fn getDefaultRules() EnabledRules {
        var rules = EnabledRules.initEmpty();
        inline for (std.meta.fields(RuleType)) |field| {
            const rule_type = @field(RuleType, field.name);
            if (RULE_INFO.get(rule_type).enabled_by_default) {
                rules.insert(rule_type);
            }
        }
        return rules;
    }

    pub fn init(allocator: std.mem.Allocator, options: LinterOptions) Linter {
        return Linter{
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

    /// Core token-based validation loop
    pub fn lintFromTokens(self: *Self, enabled_rules: EnabledRules) !void {
        if (self.iterator) |*iter| {
            // Start with the root value validation
            try self.validateValue(iter, enabled_rules);
        } else {
            // Debug: no iterator available
            // std.debug.print("lintFromTokens: no iterator available\n", .{});
        }
    }

    /// Validate a value starting from the iterator position
    pub fn validateValue(self: *Self, iter: *TokenIterator, enabled_rules: EnabledRules) ValidationError!void {
        const token_opt = self.nextNonTriviaJson(iter);
        if (token_opt == null) return;
        const token = token_opt.?;

        // Debug: print what token we got
        // std.debug.print("validateValue got token: {}\n", .{token.kind});

        switch (token.kind) {
            .string_value, .property_name => try linter_rules.validateString(self, token, enabled_rules),
            .number_value => try linter_rules.validateNumber(self, token, enabled_rules),
            .boolean_true, .boolean_false, .null_value => {
                // Basic values are always valid
            },
            .object_start => try linter_rules.validateObject(self, iter, token, enabled_rules),
            .array_start => try linter_rules.validateArray(self, iter, token, enabled_rules),
            .object_end, .array_end, .comma, .colon => {
                // Structural tokens - no validation needed for simple case
            },
            .eof => {
                // End of input - no validation needed
            },
            .whitespace, .comment => {
                // Trivia - should already be filtered out by nextNonTrivia
            },
            .err => {
                // Error tokens indicate lexer found invalid syntax - generate diagnostic
                const span = unpackSpan(token.span);
                const text = self.source[span.start..span.end];

                // Check if it's a leading zero issue (common JSON syntax error)
                if (enabled_rules.contains(.no_leading_zeros) and text.len > 0 and text[0] == '0') {
                    try self.addDiagnostic(.no_leading_zeros, "Number has leading zero (invalid in JSON)", .err, span);
                } else {
                    // Generic syntax error
                    try self.addDiagnostic(.syntax_error, "Invalid JSON syntax", .err, span);
                }
            },
            .continuation => {
                // Boundary tokens - no validation needed
            },
        }
    }

    // =========================================================================
    // Core Utilities
    // =========================================================================

    /// Add diagnostic using enum rule (zero allocation for rule names)
    pub fn addDiagnostic(self: *Self, rule: RuleType, message: []const u8, severity: Severity, span: Span) !void {
        const owned_message = try self.allocator.dupe(u8, message);
        try self.diagnostics.append(.{
            .rule = rule, // Direct enum - no conversion or allocation needed!
            .message = owned_message,
            .severity = severity,
            .range = span,
        });
    }

    pub fn peekNonTrivia(_: *Self, iter: *TokenIterator) ?Token {
        while (iter.peek()) |stream_token| {
            switch (stream_token) {
                .json => |token| {
                    if (token.kind != .whitespace and token.kind != .comment) {
                        return token;
                    }
                    _ = iter.next(); // Skip trivia
                },
                else => return null,
            }
        }
        return null;
    }

    // Helper to extract JSON token from Token union, skipping trivia
    pub fn nextNonTriviaJson(self: *Self, iter: *TokenIterator) ?@import("../token/types.zig").Token {
        _ = self;
        while (iter.next()) |token| {
            switch (token) {
                .json => |json_token| {
                    if (json_token.kind != .whitespace and json_token.kind != .comment) {
                        return json_token;
                    }
                },
                else => unreachable,
            }
        }
        return null;
    }
};
