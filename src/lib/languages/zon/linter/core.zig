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

    const SchemaType = enum {
        build_zig_zon,
        zz_zon,
        unknown,
    };

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
        self.schema_type = try self.detectSchemaType(iter);

        // Reset iterator for actual validation
        self.iterator = try TokenIterator.init(self.source, .zon);
        iter = &self.iterator.?;

        // Start validation
        try self.validateValue(iter, enabled_rules);
    }

    fn detectSchemaType(self: *Self, iter: *TokenIterator) !SchemaType {
        // Look for characteristic fields to identify schema
        while (self.nextNonTrivia(iter)) |token| {
            if (token.kind == .field_name) {
                const span = unpackSpan(token.span);
                const text = self.source[span.start..span.end];

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

    fn validateValue(self: *Self, iter: *TokenIterator, enabled_rules: EnabledRules) ValidationError!void {
        const token = self.nextNonTrivia(iter) orelse return;

        switch (token.kind) {
            .string_value => try self.validateString(token, enabled_rules),
            .number_value => try self.validateNumber(token, enabled_rules),
            .boolean_true, .boolean_false => {}, // No validation needed
            .null_value => {}, // No validation needed
            .field_name => try self.validateField(token, enabled_rules),
            .enum_literal => try self.validateEnumLiteral(token, enabled_rules),
            .struct_start => try self.validateObject(iter, token, enabled_rules),
            .array_start => try self.validateArray(iter, token, enabled_rules),
            .import => {}, // Import expressions are validated elsewhere
            else => {}, // Skip unexpected tokens
        }
    }

    fn validateString(self: *Self, token: ZonToken, enabled_rules: EnabledRules) ValidationError!void {
        const span = unpackSpan(token.span);
        const text = self.source[span.start..span.end];

        // Basic UTF-8 validation
        if (!std.unicode.utf8ValidateSlice(text)) {
            if (enabled_rules.contains(.invalid_identifier)) {
                try self.addDiagnostic(
                    .invalid_string,
                    "String contains invalid UTF-8 sequences",
                    span.start,
                    span.end,
                    .err,
                );
            }
        }
    }

    fn validateNumber(self: *Self, token: ZonToken, _: EnabledRules) ValidationError!void {
        const span = unpackSpan(token.span);
        const text = self.source[span.start..span.end];

        // Validate number format (ZON supports various number formats)
        _ = std.fmt.parseFloat(f64, text) catch |err| {
            // Try parsing as integer
            _ = std.fmt.parseInt(i64, text, 0) catch {
                try self.addDiagnostic(
                    .invalid_number,
                    try std.fmt.allocPrint(self.allocator, "Invalid number format: {}", .{err}),
                    span.start,
                    span.end,
                    .err,
                );
            };
        };
    }

    fn validateField(self: *Self, token: ZonToken, enabled_rules: EnabledRules) ValidationError!void {
        const span = unpackSpan(token.span);
        const text = self.source[span.start..span.end];

        // Validate field name format (.field_name)
        if (text.len == 0) {
            if (enabled_rules.contains(.invalid_identifier)) {
                try self.addDiagnostic(
                    .invalid_identifier,
                    "Field name cannot be empty",
                    span.start,
                    span.end,
                    .err,
                );
            }
            return;
        }

        // Field should start with '.'
        if (text[0] != '.') {
            if (enabled_rules.contains(.invalid_identifier)) {
                try self.addDiagnostic(
                    .invalid_identifier,
                    "Field name must start with '.'",
                    span.start,
                    span.end,
                    .err,
                );
            }
            return;
        }

        // Validate the identifier part (after the dot)
        if (text.len > 1) {
            try self.validateIdentifierText(text[1..], span, enabled_rules);
        }
    }

    fn validateEnumLiteral(self: *Self, token: ZonToken, enabled_rules: EnabledRules) ValidationError!void {
        const span = unpackSpan(token.span);
        const text = self.source[span.start..span.end];

        // Enum literal should start with '.'
        if (text.len == 0 or text[0] != '.') {
            if (enabled_rules.contains(.invalid_identifier)) {
                try self.addDiagnostic(
                    .invalid_identifier,
                    "Enum literal must start with '.'",
                    span.start,
                    span.end,
                    .err,
                );
            }
        }
    }

    fn validateObject(self: *Self, iter: *TokenIterator, start_token: ZonToken, enabled_rules: EnabledRules) ValidationError!void {
        const start_span = unpackSpan(start_token.span);

        // Check depth
        self.depth += 1;
        defer self.depth -= 1;

        if (enabled_rules.contains(.max_depth_exceeded) and self.depth > self.options.max_depth) {
            try self.addDiagnostic(
                .max_depth_exceeded,
                "Structure exceeds maximum depth limit",
                start_span.start,
                start_span.end,
                .err,
            );
            // Skip to end of object
            try self.skipToMatchingBrace(iter, .struct_end);
            return;
        }

        if (enabled_rules.contains(.deep_nesting) and self.depth > self.options.warn_on_deep_nesting) {
            try self.addDiagnostic(
                .deep_nesting,
                "Deep nesting may be hard to read",
                start_span.start,
                start_span.end,
                .warning,
            );
        }

        // Track fields for duplicate detection
        var seen_fields = std.StringHashMap(Span).init(self.allocator);
        defer seen_fields.deinit();

        var field_count: u32 = 0;
        var has_name = false;
        var has_version = false;

        while (true) {
            const token = self.peekNonTrivia(iter) orelse break;

            if (token.kind == .struct_end) {
                _ = self.nextNonTrivia(iter); // Consume }
                break;
            }

            // Expect field
            if (token.kind != .field_name) {
                _ = self.nextNonTrivia(iter); // Skip unexpected token
                continue;
            }

            const field_token = self.nextNonTrivia(iter).?;
            const field_span = unpackSpan(field_token.span);
            const field_text = self.source[field_span.start..field_span.end];

            // Extract field name (remove . prefix)
            const field_name = if (field_text.len > 0 and field_text[0] == '.') field_text[1..] else field_text;

            // Track for schema validation
            if (std.mem.eql(u8, field_name, "name")) has_name = true;
            if (std.mem.eql(u8, field_name, "version")) has_version = true;

            // Check for duplicate fields
            if (enabled_rules.contains(.no_duplicate_keys) and !self.options.allow_duplicate_keys) {
                if (seen_fields.get(field_name)) |prev_span| {
                    const message = try std.fmt.allocPrint(
                        self.allocator,
                        "Duplicate key '{s}' (previously defined at position {})",
                        .{ field_name, prev_span.start },
                    );
                    try self.addDiagnosticOwned(
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
            const eq = self.peekNonTrivia(iter);
            if (eq != null and eq.?.kind == .equals) {
                _ = self.nextNonTrivia(iter); // Consume =
            }

            // Validate value and check types for known schemas
            const value_start = self.peekNonTrivia(iter);
            if (value_start != null and self.schema_type == .build_zig_zon and
                enabled_rules.contains(.invalid_field_type))
            {
                try self.validateBuildField(field_name, value_start.?, enabled_rules);
            }

            try self.validateValue(iter, enabled_rules);

            // Check for comma
            const next = self.peekNonTrivia(iter);
            if (next != null and next.?.kind == .comma) {
                _ = self.nextNonTrivia(iter); // Consume comma
            }
        }

        // Check field count
        if (enabled_rules.contains(.large_structure) and field_count > self.options.max_field_count) {
            try self.addDiagnostic(
                .large_structure,
                "Object has too many fields",
                start_span.start,
                start_span.end,
                .warning,
            );
        }

        // Check required fields for known schemas
        if (self.schema_type == .build_zig_zon and enabled_rules.contains(.missing_required_field)) {
            if (!has_name) {
                try self.addDiagnostic(
                    .missing_required_field,
                    "Missing required field 'name' in build.zig.zon",
                    start_span.start,
                    start_span.start,
                    .err,
                );
            }
            if (!has_version) {
                try self.addDiagnostic(
                    .missing_required_field,
                    "Missing required field 'version' in build.zig.zon",
                    start_span.start,
                    start_span.start,
                    .err,
                );
            }
        }
    }

    fn validateArray(self: *Self, iter: *TokenIterator, start_token: ZonToken, enabled_rules: EnabledRules) ValidationError!void {
        const start_span = unpackSpan(start_token.span);

        // Check depth
        self.depth += 1;
        defer self.depth -= 1;

        if (enabled_rules.contains(.max_depth_exceeded) and self.depth > self.options.max_depth) {
            try self.addDiagnostic(
                .max_depth_exceeded,
                "Structure exceeds maximum depth limit",
                start_span.start,
                start_span.end,
                .err,
            );
            // Skip to end of array
            try self.skipToMatchingBrace(iter, .array_end);
            return;
        }

        var element_count: u32 = 0;

        while (true) {
            const token = self.peekNonTrivia(iter) orelse break;

            if (token.kind == .array_end or token.kind == .struct_end) {
                _ = self.nextNonTrivia(iter); // Consume ] or }
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
        if (enabled_rules.contains(.large_structure) and element_count > self.options.max_array_size) {
            try self.addDiagnostic(
                .large_structure,
                "Array has too many elements",
                start_span.start,
                start_span.end,
                .warning,
            );
        }
    }

    fn validateBuildField(self: *Self, field_name: []const u8, value_token: ZonToken, _: EnabledRules) !void {
        const span = unpackSpan(value_token.span);

        if (std.mem.eql(u8, field_name, "name") or std.mem.eql(u8, field_name, "version")) {
            // Should be string
            if (value_token.kind != .string_value) {
                try self.addDiagnostic(
                    .invalid_field_type,
                    try std.fmt.allocPrint(self.allocator, "'{s}' must be a string", .{field_name}),
                    span.start,
                    span.end,
                    .err,
                );
            }
        } else if (std.mem.eql(u8, field_name, "dependencies")) {
            // Should be object
            if (value_token.kind != .object_start) {
                try self.addDiagnostic(
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
                try self.addDiagnostic(
                    .invalid_field_type,
                    "Paths must be an array",
                    span.start,
                    span.end,
                    .err,
                );
            }
        }
    }

    fn validateIdentifierText(self: *Self, text: []const u8, span: Span, enabled_rules: EnabledRules) !void {
        // Check if it's a @"keyword" identifier
        if (text.len >= 3 and text[0] == '@' and text[1] == '"' and text[text.len - 1] == '"') {
            // @"keyword" syntax - the content inside quotes can be anything
            return;
        }

        // Regular identifier validation
        if (text.len == 0) return;

        // First character must be letter or underscore
        const first_char = text[0];
        if (!char_utils.isAlpha(first_char) and first_char != '_') {
            if (enabled_rules.contains(.invalid_identifier)) {
                try self.addDiagnostic(
                    .invalid_identifier,
                    "Identifier must start with letter or underscore",
                    span.start,
                    span.end,
                    .err,
                );
            }
            return;
        }

        // Remaining characters must be alphanumeric or underscore
        for (text[1..]) |char| {
            if (!char_utils.isAlphaNumeric(char) and char != '_') {
                if (enabled_rules.contains(.invalid_identifier)) {
                    try self.addDiagnostic(
                        .invalid_identifier,
                        "Identifier contains invalid character",
                        span.start,
                        span.end,
                        .err,
                    );
                }
                return;
            }
        }
    }

    fn skipToMatchingBrace(_: *Self, iter: *TokenIterator, end_kind: TokenKind) !void {
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

    fn addDiagnostic(self: *Self, rule: RuleType, message: []const u8, start_pos: u32, end_pos: u32, severity: Diagnostic.Severity) !void {
        const owned_message = try self.allocator.dupe(u8, message);
        try self.addDiagnosticOwned(rule, owned_message, start_pos, end_pos, severity);
    }

    fn addDiagnosticOwned(self: *Self, rule: RuleType, owned_message: []const u8, start_pos: u32, end_pos: u32, severity: Diagnostic.Severity) !void {
        const diagnostic = Diagnostic{
            .message = owned_message,
            .span = Span.init(start_pos, end_pos),
            .severity = severity,
            .rule = rule, // Direct enum, no allocation needed!
        };

        try self.diagnostics.append(diagnostic);
    }

    fn peekNonTrivia(self: *Self, iter: *TokenIterator) ?ZonToken {
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

    fn nextNonTrivia(self: *Self, iter: *TokenIterator) ?ZonToken {
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
