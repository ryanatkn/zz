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

/// Linting rule definition (local to JSON)
pub const Rule = struct {
    name: []const u8,
    description: []const u8,
    severity: Severity,
    enabled: bool = true,

    pub const Severity = enum { @"error", warning, info, hint };
};

/// Diagnostic from linting (local to JSON)
pub const Diagnostic = struct {
    rule: []const u8,
    message: []const u8,
    severity: Rule.Severity,
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

    // Built-in linting rules
    pub const RULES = [_]Rule{
        Rule{
            .name = "no_duplicate_keys",
            .description = "Object keys must be unique",
            .severity = .@"error",
        },
        Rule{
            .name = "no_leading_zeros",
            .description = "Numbers should not have leading zeros",
            .severity = .warning,
        },
        Rule{
            .name = "valid_string_encoding",
            .description = "Strings must be valid UTF-8",
            .severity = .@"error",
        },
        Rule{
            .name = "max_depth_exceeded",
            .description = "JSON structure exceeds maximum nesting depth",
            .severity = .@"error",
        },
        Rule{
            .name = "large_number_precision",
            .description = "Number has high precision that may cause issues",
            .severity = .warning,
        },
        Rule{
            .name = "large_structure",
            .description = "JSON structure is very large",
            .severity = .warning,
        },
        Rule{
            .name = "deep_nesting",
            .description = "JSON has deep nesting that may be hard to read",
            .severity = .warning,
        },
    };

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
    pub fn lint(self: *Self, ast: AST, enabled_rules: []const Rule) ![]Diagnostic {
        try self.validateNode(ast.root, 0, enabled_rules);

        return self.diagnostics.toOwnedSlice();
    }

    fn validateNode(self: *Self, node: *const Node, depth: u32, enabled_rules: []const Rule) !void {
        // Check depth limit
        if (depth > self.options.max_depth) {
            if (self.isRuleEnabled("max_depth_exceeded", enabled_rules)) {
                try self.addDiagnostic(
                    "max_depth_exceeded",
                    "JSON nesting depth exceeds maximum limit",
                    .@"error",
                    node.span(),
                );
            }
            return;
        }

        // Warn about deep nesting
        if (depth > self.options.warn_on_deep_nesting) {
            if (self.isRuleEnabled("deep_nesting", enabled_rules)) {
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

    fn validateString(self: *Self, node: *const Node, enabled_rules: []const Rule) !void {
        const string_node = node.string;
        const raw_value = string_node.value;

        // Check length
        if (raw_value.len > self.options.max_string_length) {
            if (self.isRuleEnabled("large_structure", &.{})) {
                try self.addDiagnostic(
                    "large_structure",
                    "String exceeds maximum length",
                    .warning,
                    node.span(),
                );
            }
        }

        // Validate UTF-8 encoding if rule is enabled
        if (self.isRuleEnabled("valid_string_encoding", enabled_rules)) {
            if (raw_value.len >= 2 and raw_value[0] == '"' and raw_value[raw_value.len - 1] == '"') {
                const content = raw_value[1 .. raw_value.len - 1];
                if (!std.unicode.utf8ValidateSlice(content)) {
                    try self.addDiagnostic(
                        "valid_string_encoding",
                        "String contains invalid UTF-8 sequences",
                        .@"error",
                        node.span(),
                    );
                }

                // Validate escape sequences
                const span = node.span();
                try self.validateEscapeSequences(content, span, enabled_rules);
            }
        }
    }

    fn validateNumber(self: *Self, node: *const Node, enabled_rules: []const Rule) !void {
        const number_node = node.number;
        const value = number_node.raw;
        if (value.len == 0) return;

        // Check for leading zeros
        if (self.isRuleEnabled("no_leading_zeros", enabled_rules) and !self.options.allow_leading_zeros) {
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
        if (self.isRuleEnabled("large_number_precision", enabled_rules) and self.options.warn_on_large_numbers) {
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
                .@"error",
                node.span(),
            );
        };
    }

    fn validateObject(self: *Self, node: *const Node, _: u32, enabled_rules: []const Rule) !void {
        const object_node = node.object;
        const members = object_node.properties;

        // Check object size
        if (members.len > self.options.max_object_keys) {
            if (self.isRuleEnabled("large_structure", &.{})) {
                try self.addDiagnostic(
                    "large_structure",
                    "Object has too many keys",
                    .warning,
                    node.span(),
                );
            }
        }

        // Check for duplicate keys
        if (self.isRuleEnabled("no_duplicate_keys", enabled_rules) and !self.options.allow_duplicate_keys) {
            var seen_keys = std.HashMap([]const u8, Span, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(self.allocator);
            defer seen_keys.deinit();

            for (members) |member| {
                const property = switch (member) {
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
                        .@"error",
                        property.key.span(),
                        "Remove duplicate key or rename to make unique",
                    );
                } else {
                    try seen_keys.put(key_content, property.key.span());
                }
            }
        }
    }

    fn validateArray(self: *Self, node: *const Node, _: u32, _: []const Rule) !void {
        const array_node = node.array;
        const elements = array_node.elements;

        // Check array size
        if (elements.len > self.options.max_array_elements) {
            if (self.isRuleEnabled("large_structure", &.{})) {
                try self.addDiagnostic(
                    "large_structure",
                    "Array has too many elements",
                    .warning,
                    node.span(),
                );
            }
        }
    }

    fn validateProperty(self: *Self, node: *const Node, _: u32, _: []const Rule) !void {
        const property_node = node.property;

        // Validate that key is a string
        switch (property_node.key.*) {
            .string => {}, // Valid
            else => {
                try self.addDiagnostic(
                    "invalid_key_type",
                    "Object key must be a string",
                    .@"error",
                    property_node.key.span(),
                );
            },
        }
    }

    fn validateEscapeSequences(self: *Self, content: []const u8, span: Span, _: []const Rule) !void {
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
                                        .@"error",
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
                                .@"error",
                                span,
                            );
                            i += 2;
                        }
                    },
                    else => {
                        try self.addDiagnostic(
                            "invalid_escape_sequence",
                            "Invalid escape sequence",
                            .@"error",
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

    fn isRuleEnabled(_: *Self, rule_name: []const u8, enabled_rules: []const Rule) bool {
        for (enabled_rules) |rule| {
            if (std.mem.eql(u8, rule.name, rule_name)) {
                return rule.enabled;
            }
        }
        return false;
    }

    /// Efficient rule checking using enum (O(1) vs O(n) string comparison)
    fn isRuleEnabledEnum(self: *Self, rule_kind: JsonLintRules.KindType, enabled_rules: []const JsonLintRules.KindType) bool {
        _ = self;
        for (enabled_rules) |enabled_rule| {
            if (enabled_rule == rule_kind) {
                return true;
            }
        }
        return false;
    }

    fn addDiagnostic(self: *Self, rule: []const u8, message: []const u8, severity: Rule.Severity, span: Span) !void {
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
        // Convert enum severity to Rule.Severity
        const rule_severity = switch (JsonLintRules.severity(rule_kind)) {
            .@"error" => Rule.Severity.@"error",
            .warning => Rule.Severity.warning,
            .info => Rule.Severity.warning, // Map to warning for now
            .hint => Rule.Severity.warning, // Map to warning for now
        };
        try self.diagnostics.append(Diagnostic{
            .rule = JsonLintRules.name(rule_kind), // No allocation needed - static string
            .message = owned_message,
            .severity = rule_severity,
            .range = span,
            .fix = null,
        });
    }

    fn addDiagnosticWithFix(self: *Self, rule: []const u8, message: []const u8, severity: Rule.Severity, span: Span, fix_description: []const u8) !void {
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
pub fn lintJson(allocator: std.mem.Allocator, ast: AST, enabled_rules: []const Rule) ![]Diagnostic {
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

    const enabled_rules = &[_]Rule{
        Rule{ .name = "no_duplicate_keys", .description = "", .severity = .@"error", .enabled = true },
    };

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

    const enabled_rules = &[_]Rule{
        Rule{ .name = "deep_nesting", .description = "", .severity = .warning, .enabled = true },
    };

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
