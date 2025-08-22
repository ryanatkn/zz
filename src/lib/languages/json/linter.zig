const std = @import("std");
const char_utils = @import("../../char/mod.zig");
// Use local JSON AST
const json_ast = @import("ast.zig");
const AST = json_ast.AST;
const Node = json_ast.Node;
const NodeKind = json_ast.NodeKind;
const Span = @import("../../span/span.zig").Span;
const patterns = @import("patterns.zig");
const JsonLintRules = patterns.JsonLintRules;

// Import interface types
const interface_types = @import("../interface.zig");
const Severity = interface_types.RuleInfo.Severity;

/// JSON-specific linting rules
///
/// Performance Notes - Enum Rule System:
/// - enum(u8) supports up to 256 rules per language
/// - Current usage: JSON=7 rules (well under limit)
/// - EnumSet performance characteristics:
///   * ≤64 rules: Single u64 register, 1-2 CPU cycles for checks
///   * ≤128 rules: Single u128, 2-3 CPU cycles
///   * >128 rules: Bit array, 3-5 CPU cycles
/// - Future expansion: Change to enum(u16) if >256 rules needed
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

/// Diagnostic from linting (local to JSON)
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

/// JSON validator/linter with comprehensive error detection
///
/// Features:
/// - Duplicate key detection in objects
/// - Number format validation (leading zeros, valid exponents)
/// - String encoding validation (proper UTF-8)
/// - Structural validation (depth limits, key/value restrictions)
/// - Performance tracking and metrics
/// - Configurable rules with severity levels
pub const JsonLinter = struct {
    allocator: std.mem.Allocator,
    options: LinterOptions,
    diagnostics: std.ArrayList(Diagnostic),

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
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.diagnostics.items) |diag| {
            self.allocator.free(diag.message);
        }
        self.diagnostics.deinit();
    }

    /// Lint JSON AST and return diagnostics
    pub fn lint(self: *Self, ast: AST, enabled_rules: EnabledRules) ![]Diagnostic {
        try self.validateNode(ast.root, 0, enabled_rules);

        return self.diagnostics.toOwnedSlice();
    }

    fn validateNode(self: *Self, node: *const Node, depth: u32, enabled_rules: EnabledRules) !void {
        // Check depth limit
        if (depth > self.options.max_depth) {
            if (enabled_rules.contains(.max_depth_exceeded)) {
                try self.addDiagnostic(
                    "max_depth_exceeded",
                    "JSON nesting depth exceeds maximum limit",
                    .err,
                    node.span(),
                );
            }
            return;
        }

        // Warn about deep nesting
        if (depth > self.options.warn_on_deep_nesting) {
            if (enabled_rules.contains(.deep_nesting)) {
                try self.addDiagnostic(
                    "deep_nesting",
                    "JSON structure has deep nesting",
                    .warning,
                    node.span(),
                );
            }
        }

        switch (node.*) {
            .string => try self.validateString(node, enabled_rules),
            .number => try self.validateNumber(node, enabled_rules),
            .object => |n| {
                try self.validateObject(node, depth, enabled_rules);
                // Recursively validate properties
                for (n.properties) |*property| {
                    try self.validateNode(property, depth + 1, enabled_rules);
                }
            },
            .array => |n| {
                try self.validateArray(node, depth, enabled_rules);
                // Recursively validate elements
                for (n.elements) |*element| {
                    try self.validateNode(element, depth + 1, enabled_rules);
                }
            },
            .property => |n| {
                try self.validateProperty(node, depth, enabled_rules);
                // Validate key and value
                try self.validateNode(n.key, depth + 1, enabled_rules);
                try self.validateNode(n.value, depth + 1, enabled_rules);
            },
            .root => |n| {
                try self.validateNode(n.value, depth, enabled_rules);
            },
            .boolean, .null, .err => {}, // No special validation needed
        }
    }

    fn validateString(self: *Self, node: *const Node, enabled_rules: EnabledRules) !void {
        const string_node = node.string;
        const raw_value = string_node.value;

        // Check length
        if (raw_value.len > self.options.max_string_length) {
            if (enabled_rules.contains(.large_structure)) {
                try self.addDiagnostic(
                    "large_structure",
                    "String exceeds maximum length",
                    .warning,
                    node.span(),
                );
            }
        }

        // Validate UTF-8 encoding if rule is enabled
        if (enabled_rules.contains(.valid_string_encoding)) {
            if (raw_value.len >= 2 and raw_value[0] == '"' and raw_value[raw_value.len - 1] == '"') {
                const content = raw_value[1 .. raw_value.len - 1];
                if (!std.unicode.utf8ValidateSlice(content)) {
                    try self.addDiagnostic(
                        "valid_string_encoding",
                        "String contains invalid UTF-8 sequences",
                        .err,
                        node.span(),
                    );
                }

                // Validate escape sequences
                const span = node.span();
                try self.validateEscapeSequences(content, span, enabled_rules);
            }
        }
    }

    fn validateNumber(self: *Self, node: *const Node, enabled_rules: EnabledRules) !void {
        const number_node = node.number;
        const value = number_node.raw;
        if (value.len == 0) return;

        // Check for leading zeros
        if (enabled_rules.contains(.no_leading_zeros) and !self.options.allow_leading_zeros) {
            if (value.len > 1 and value[0] == '0' and char_utils.isDigit(value[1])) {
                try self.addDiagnostic(
                    "no_leading_zeros",
                    "Number has leading zero",
                    .warning,
                    node.span(),
                );
            }
        }

        // Check number precision
        if (enabled_rules.contains(.large_number_precision) and self.options.warn_on_large_numbers) {
            if (std.mem.indexOf(u8, value, ".")) |dot_pos| {
                const decimal_part = value[dot_pos + 1 ..];
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
                        node.span(),
                    );
                }
            }
        }

        // Validate number format
        _ = std.fmt.parseFloat(f64, value) catch {
            try self.addDiagnostic(
                "invalid_number",
                "Number format is invalid",
                .err,
                node.span(),
            );
        };
    }

    fn validateObject(self: *Self, node: *const Node, _: u32, enabled_rules: EnabledRules) !void {
        const object_node = node.object;
        const properties = object_node.properties;

        // Check object size
        if (properties.len > self.options.max_object_keys) {
            if (enabled_rules.contains(.large_structure)) {
                try self.addDiagnostic(
                    "large_structure",
                    "Object has too many keys",
                    .warning,
                    node.span(),
                );
            }
        }

        // Check for duplicate keys
        if (enabled_rules.contains(.no_duplicate_keys) and !self.options.allow_duplicate_keys) {
            var seen_keys = std.HashMap([]const u8, Span, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(self.allocator);
            defer seen_keys.deinit();

            for (properties) |property_node| {
                const property = switch (property_node) {
                    .property => |p| p,
                    else => continue,
                };

                const key_value = switch (property.key.*) {
                    .string => |s| s.value,
                    else => continue,
                };

                // Extract key content (remove quotes)
                const key_content = if (key_value.len >= 2 and key_value[0] == '"' and key_value[key_value.len - 1] == '"')
                    key_value[1 .. key_value.len - 1]
                else
                    key_value;

                if (seen_keys.get(key_content)) |_| {
                    // Use efficient enum-based diagnostic (but keep addDiagnosticWithFix for now)
                    try self.addDiagnosticWithFix(
                        JsonLintRules.name(.no_duplicate_keys), // Static string, no allocation
                        "Duplicate object key",
                        .err,
                        property.key.span(),
                        "Remove duplicate key or rename to make unique",
                    );
                } else {
                    try seen_keys.put(key_content, property.key.span());
                }
            }
        }
    }

    fn validateArray(self: *Self, node: *const Node, _: u32, enabled_rules: EnabledRules) !void {
        const array_node = node.array;
        const elements = array_node.elements;

        // Check array size
        if (elements.len > self.options.max_array_elements) {
            if (enabled_rules.contains(.large_structure)) {
                try self.addDiagnostic(
                    "large_structure",
                    "Array has too many elements",
                    .warning,
                    node.span(),
                );
            }
        }
    }

    fn validateProperty(self: *Self, node: *const Node, _: u32, _: EnabledRules) !void {
        const property_node = node.property;

        // Validate that key is a string
        switch (property_node.key.*) {
            .string => {}, // Valid
            else => {
                try self.addDiagnostic(
                    "invalid_key_type",
                    "Object key must be a string",
                    .err,
                    property_node.key.span(),
                );
            },
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

    /// Efficient diagnostic creation using enum (no string allocation for rule name)
    fn addDiagnosticEnum(self: *Self, rule_kind: JsonLintRules.KindType, message: []const u8, span: Span) !void {
        const owned_message = try self.allocator.dupe(u8, message);
        // Convert enum severity to Severity
        const rule_severity = switch (JsonLintRules.severity(rule_kind)) {
            .err => Severity.err,
            .warning => Severity.warning,
            .info => Severity.warning, // Map to warning for now
            .hint => Severity.warning, // Map to warning for now
        };
        try self.diagnostics.append(Diagnostic{
            .rule = JsonLintRules.name(rule_kind), // No allocation needed - static string
            .message = owned_message,
            .severity = rule_severity,
            .range = span,
            .fix = null,
        });
    }

    fn addDiagnosticWithFix(self: *Self, rule: []const u8, message: []const u8, severity: Severity, span: Span, fix_description: []const u8) !void {
        const owned_message = try self.allocator.dupe(u8, message);
        const owned_fix_desc = try self.allocator.dupe(u8, fix_description);

        try self.diagnostics.append(Diagnostic{
            .rule = rule,
            .message = owned_message,
            .severity = severity,
            .range = span,
            .fix = Diagnostic.Fix{
                .description = owned_fix_desc,
                .edits = &.{}, // No automatic fixes for now
            },
        });
    }
};

/// Convenience function for basic JSON linting
pub fn lintJson(allocator: std.mem.Allocator, ast: AST, enabled_rules: EnabledRules) ![]Diagnostic {
    var linter = JsonLinter.init(allocator, .{});
    defer linter.deinit();

    return linter.lint(ast, enabled_rules);
}

// Tests
const testing = std.testing;
const JsonLexer = @import("lexer.zig").JsonLexer;
const JsonParser = @import("parser.zig").JsonParser;

test "JSON linter - duplicate keys" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = "{\"key\": 1, \"key\": 2}";

    var lexer = JsonLexer.init(allocator);
    defer lexer.deinit();
    const tokens = try lexer.batchTokenize(allocator, input);

    var parser = JsonParser.init(allocator, tokens, input, .{});
    defer parser.deinit();
    var ast = try parser.parse();
    defer ast.deinit();

    var enabled_rules = EnabledRules.initEmpty();
    enabled_rules.insert(.no_duplicate_keys);

    const diagnostics = try lintJson(allocator, ast, enabled_rules);
    defer {
        for (diagnostics) |diag| {
            allocator.free(diag.message);
        }
        allocator.free(diagnostics);
    }

    // Should find duplicate key
    try testing.expect(diagnostics.len > 0);
    try testing.expectEqualStrings("no_duplicate_keys", diagnostics[0].rule);
}

test "JSON linter - deep nesting" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create deeply nested structure
    const input = "{\"a\": {\"b\": {\"c\": {\"d\": {\"e\": {\"f\": 1}}}}}}";

    var lexer = JsonLexer.init(allocator);
    defer lexer.deinit();
    const tokens = try lexer.batchTokenize(allocator, input);

    var parser = JsonParser.init(allocator, tokens, input, .{});
    defer parser.deinit();
    var ast = try parser.parse();
    defer ast.deinit();

    var linter = JsonLinter.init(allocator, .{ .warn_on_deep_nesting = 3 });
    defer linter.deinit();

    var enabled_rules = EnabledRules.initEmpty();
    enabled_rules.insert(.deep_nesting);

    const diagnostics = try linter.lint(ast, enabled_rules);
    defer {
        for (diagnostics) |diag| {
            allocator.free(diag.message);
        }
        allocator.free(diagnostics);
    }

    // Should warn about deep nesting
    try testing.expect(diagnostics.len > 0);
}
