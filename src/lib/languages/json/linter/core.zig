/// JSON Linter - Core Infrastructure and Main Logic
///
/// Core linting infrastructure with streaming token validation
const std = @import("std");
const TokenIterator = @import("../../../token/iterator.zig").TokenIterator;
const StreamToken = @import("../../../token/stream_token.zig").StreamToken;
const JsonToken = @import("../token/mod.zig").JsonToken;
const JsonTokenKind = @import("../token/mod.zig").JsonTokenKind;
const unpackSpan = @import("../../../span/mod.zig").unpackSpan;
const Span = @import("../../../span/span.zig").Span;
const char_utils = @import("../../../char/mod.zig");

// Import interface types for compatibility
const interface_types = @import("../../interface.zig");
const Severity = interface_types.RuleInfo.Severity;

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

    /// Lint JSON from AST (legacy compatibility)
    /// TODO: Remove this bridge method and use direct token stream validation
    pub fn lint(self: *Self, ast: anytype, enabled_rules: EnabledRules) ![]Diagnostic {
        // Extract source from AST if self.source is empty
        if (self.source.len == 0) {
            return self.lintSource(ast.source, enabled_rules);
        }
        return self.lintSource(self.source, enabled_rules);
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
        const token_opt = self.nextNonTrivia(iter);
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
                    try self.addDiagnostic("no_leading_zeros", "Number has leading zero (invalid in JSON)", .err, span);
                } else {
                    // Generic syntax error
                    try self.addDiagnostic("syntax_error", "Invalid JSON syntax", .err, span);
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

    pub fn addDiagnostic(self: *Self, rule: []const u8, message: []const u8, severity: Severity, span: Span) !void {
        const owned_message = try self.allocator.dupe(u8, message);
        try self.diagnostics.append(.{
            .rule = rule,
            .message = owned_message,
            .severity = severity,
            .range = span,
        });
    }

    pub fn peekNonTrivia(_: *Self, iter: *TokenIterator) ?JsonToken {
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

    pub fn nextNonTrivia(self: *Self, iter: *TokenIterator) ?JsonToken {
        _ = self;
        while (iter.next()) |stream_token| {
            switch (stream_token) {
                .json => |token| {
                    if (token.kind != .whitespace and token.kind != .comment) {
                        return token;
                    }
                },
                else => unreachable,
            }
        }
        return null;
    }
};
