/// ZON Streaming Linter - Direct token stream validation
///
/// SIMPLIFIED: Validates directly from streaming tokens without building AST
/// Performance target: <1ms for typical build.zig.zon files
const std = @import("std");
const TokenIterator = @import("../../../token/iterator.zig").TokenIterator;
const StreamToken = @import("../../../token/stream_token.zig").Token;
const ZonToken = @import("../token/types.zig").Token;
const TokenKind = @import("../token/types.zig").TokenKind;
const unpackSpan = @import("../../../span/mod.zig").unpackSpan;
const Span = @import("../../../span/mod.zig").Span;
const char_utils = @import("../../../char/mod.zig");

// Import interface types for compatibility
const interface_types = @import("../../interface.zig");
const InterfaceSeverity = interface_types.Severity;

// For AST compatibility
const common = @import("../utils/common.zig");
const AST = common.AST;

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

/// ZON-specific linting rules
pub const RuleType = enum(u8) {
    no_duplicate_keys,
    max_depth_exceeded,
    large_structure,
    deep_nesting,
    invalid_field_type,
    unknown_field,
    missing_required_field,
    invalid_identifier,
    prefer_explicit_type,
    schema_validation,
    // Additional rules found in code
    invalid_string,
    invalid_number,
};

/// Efficient rule set using bitflags for O(1) lookups
pub const EnabledRules = std.EnumSet(RuleType);

/// Diagnostic from linting
pub const Diagnostic = struct {
    message: []const u8,
    span: Span,
    severity: Severity,
    rule: RuleType, // Enum instead of string!

    pub const Severity = enum {
        err,
        warning,
        info,
        hint,
    };

    pub fn deinit(self: Diagnostic, allocator: std.mem.Allocator) void {
        allocator.free(self.message);
        // No need to free rule - it's an enum, not allocated memory
    }
};

/// ZON streaming linter with real-time validation
///
/// Features:
/// - Validates tokens as they stream (no AST needed)
/// - Duplicate field detection with hash map
/// - Type validation for known schemas (build.zig.zon, zz.zon)
/// - Structural validation (depth limits, size checks)
/// - ZON-specific syntax validation
/// - Memory efficient with streaming approach
pub const Linter = struct {
    allocator: std.mem.Allocator,
    options: LintOptions,
    diagnostics: std.ArrayList(Diagnostic),
    source: []const u8,
    iterator: ?TokenIterator,

    // State tracking for streaming validation
    depth: u32,
    field_count: u32,
    array_size: u32,
    schema_type: SchemaType,

    const Self = @This();

    pub const LintOptions = struct {
        max_depth: u32 = 100,
        max_field_count: u32 = 1000,
        max_array_size: u32 = 10000,
        warn_on_deep_nesting: u32 = 20,
        allow_duplicate_keys: bool = false,
        check_known_schemas: bool = true,
        strict_types: bool = false,
        allow_trailing_commas: bool = true,
        check_unused_fields: bool = false,
    };

    /// Rule metadata for each enum value
    pub const RuleInfo = struct {
        description: []const u8,
        severity: InterfaceSeverity,
        enabled_by_default: bool,
    };

    /// Built-in linting rules metadata
    pub const RULE_INFO = std.EnumArray(RuleType, RuleInfo).init(.{
        .no_duplicate_keys = .{
            .description = "Object keys must be unique",
            .severity = .err,
            .enabled_by_default = true,
        },
        .max_depth_exceeded = .{
            .description = "ZON structure exceeds maximum nesting depth",
            .severity = .err,
            .enabled_by_default = true,
        },
        .large_structure = .{
            .description = "ZON structure is very large",
            .severity = .warning,
            .enabled_by_default = false,
        },
        .deep_nesting = .{
            .description = "ZON has deep nesting that may be hard to read",
            .severity = .warning,
            .enabled_by_default = true,
        },
        .invalid_field_type = .{
            .description = "Field has invalid type for known schema",
            .severity = .err,
            .enabled_by_default = false,
        },
        .unknown_field = .{
            .description = "Field is not recognized in known schema",
            .severity = .warning,
            .enabled_by_default = false,
        },
        .missing_required_field = .{
            .description = "Required field is missing from object",
            .severity = .err,
            .enabled_by_default = false,
        },
        .invalid_identifier = .{
            .description = "Identifier uses invalid ZON syntax",
            .severity = .err,
            .enabled_by_default = true,
        },
        .prefer_explicit_type = .{
            .description = "Consider using explicit type annotation",
            .severity = .hint,
            .enabled_by_default = false,
        },
        .schema_validation = .{
            .description = "Validate ZON structure against known schemas",
            .severity = .warning,
            .enabled_by_default = false,
        },
        .invalid_string = .{
            .description = "String contains invalid characters or encoding",
            .severity = .err,
            .enabled_by_default = true,
        },
        .invalid_number = .{
            .description = "Number has invalid format",
            .severity = .err,
            .enabled_by_default = true,
        },
    });

    const SchemaType = linter_rules.SchemaType;

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

    pub fn init(allocator: std.mem.Allocator, options: LintOptions) Linter {
        return Linter{
            .allocator = allocator,
            .options = options,
            .diagnostics = std.ArrayList(Diagnostic).init(allocator),
            .source = "",
            .iterator = null,
            .depth = 0,
            .field_count = 0,
            .array_size = 0,
            .schema_type = .unknown,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.diagnostics.items) |diag| {
            diag.deinit(self.allocator);
        }
        self.diagnostics.deinit();
    }

    /// Lint ZON from source directly using streaming tokens
    pub fn lintSource(self: *Self, source: []const u8, enabled_rules: EnabledRules) ![]Diagnostic {
        self.source = source;
        self.iterator = try TokenIterator.init(source, .zon);

        try self.lintFromTokens(enabled_rules);

        return self.diagnostics.toOwnedSlice();
    }

    /// Lint ZON AST (compatibility layer)
    pub fn lint(self: *Self, ast: AST, enabled_rules: EnabledRules) ![]Diagnostic {
        // For compatibility, we re-tokenize the source
        self.source = ast.source;
        self.iterator = try TokenIterator.init(ast.source, .zon);

        try self.lintFromTokens(enabled_rules);

        return self.diagnostics.toOwnedSlice();
    }

    /// Main streaming validation loop
    fn lintFromTokens(self: *Self, enabled_rules: EnabledRules) !void {
        var iter = &self.iterator.?;

        // Detect schema type from initial tokens
        self.schema_type = try linter_rules.detectSchemaType(self, iter);

        // Reset iterator for actual validation
        self.iterator = try TokenIterator.init(self.source, .zon);
        iter = &self.iterator.?;

        // Start validation
        try self.validateValue(iter, enabled_rules);
    }

    pub fn validateValue(self: *Self, iter: *TokenIterator, enabled_rules: EnabledRules) ValidationError!void {
        const token = self.nextNonTrivia(iter) orelse return;

        switch (token.kind) {
            .string_value => try linter_rules.validateString(self, token, enabled_rules),
            .number_value => try linter_rules.validateNumber(self, token, enabled_rules),
            .boolean_true, .boolean_false => {}, // No validation needed
            .null_value => {}, // No validation needed
            .field_name => try linter_rules.validateField(self, token, enabled_rules),
            .enum_literal => try linter_rules.validateEnumLiteral(self, token, enabled_rules),
            .struct_start => try linter_rules.validateObject(self, iter, token, enabled_rules),
            .array_start => try linter_rules.validateArray(self, iter, token, enabled_rules),
            .import => {}, // Import expressions are validated elsewhere
            else => {}, // Skip unexpected tokens
        }
    }

    pub fn addDiagnostic(self: *Self, rule: RuleType, message: []const u8, start_pos: u32, end_pos: u32, severity: Diagnostic.Severity) !void {
        const owned_message = try self.allocator.dupe(u8, message);
        try self.addDiagnosticOwned(rule, owned_message, start_pos, end_pos, severity);
    }

    pub fn addDiagnosticOwned(self: *Self, rule: RuleType, owned_message: []const u8, start_pos: u32, end_pos: u32, severity: Diagnostic.Severity) !void {
        const diagnostic = Diagnostic{
            .message = owned_message,
            .span = Span.init(start_pos, end_pos),
            .severity = severity,
            .rule = rule, // Direct enum, no allocation needed!
        };

        try self.diagnostics.append(diagnostic);
    }

    pub fn peekNonTrivia(self: *Self, iter: *TokenIterator) ?ZonToken {
        _ = self;
        while (iter.peek()) |token| {
            switch (token) {
                .zon => |t| {
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

    pub fn nextNonTrivia(self: *Self, iter: *TokenIterator) ?ZonToken {
        _ = self;
        while (iter.next()) |token| {
            switch (token) {
                .zon => |t| {
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

/// Convenience function for linting ZON AST (compatibility)
pub fn lint(allocator: std.mem.Allocator, ast: AST, enabled_rules: anytype) ![]Linter.Diagnostic {
    _ = enabled_rules;
    var linter = Linter.init(allocator, .{});
    defer linter.deinit();
    return linter.lint(ast, Linter.getDefaultRules());
}

/// Lint ZON string directly
pub fn lintString(allocator: std.mem.Allocator, zon_content: []const u8, enabled_rules: anytype) ![]Linter.Diagnostic {
    _ = enabled_rules;
    var linter = Linter.init(allocator, .{});
    defer linter.deinit();
    return linter.lintSource(zon_content, Linter.getDefaultRules());
}
