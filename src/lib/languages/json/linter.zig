const std = @import("std");
const char_utils = @import("../../char/mod.zig");
const AST = @import("../../ast/mod.zig").AST;
const Node = @import("../../ast/mod.zig").Node;
const NodeType = @import("../../ast/mod.zig").NodeType;
const Span = @import("../../parser/foundation/types/span.zig").Span;
const JsonRules = @import("../../ast/rules.zig").JsonRules;
const Rule = @import("../interface.zig").Rule;
const Diagnostic = @import("../interface.zig").Diagnostic;

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
            .name = "no-duplicate-keys",
            .description = "Object keys must be unique",
            .severity = .@"error",
        },
        Rule{
            .name = "no-leading-zeros",
            .description = "Numbers should not have leading zeros",
            .severity = .warning,
        },
        Rule{
            .name = "valid-string-encoding",
            .description = "Strings must be valid UTF-8",
            .severity = .@"error",
        },
        Rule{
            .name = "max-depth-exceeded",
            .description = "JSON structure exceeds maximum nesting depth",
            .severity = .@"error",
        },
        Rule{
            .name = "large-number-precision",
            .description = "Number has high precision that may cause issues",
            .severity = .warning,
        },
        Rule{
            .name = "large-structure",
            .description = "JSON structure is very large",
            .severity = .warning,
        },
        Rule{
            .name = "deep-nesting",
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
        var root = ast.root;
        try self.validateNode(&root, 0, enabled_rules);

        return self.diagnostics.toOwnedSlice();
    }

    fn validateNode(self: *Self, node: *const Node, depth: u32, enabled_rules: []const Rule) !void {
        // Check depth limit
        if (depth > self.options.max_depth) {
            if (self.isRuleEnabled("max-depth-exceeded", enabled_rules)) {
                try self.addDiagnostic(
                    "max-depth-exceeded",
                    "JSON nesting depth exceeds maximum limit",
                    .@"error",
                    Span.init(node.start_position, node.end_position),
                );
            }
            return;
        }

        // Warn about deep nesting
        if (depth > self.options.warn_on_deep_nesting) {
            if (self.isRuleEnabled("deep-nesting", enabled_rules)) {
                try self.addDiagnostic(
                    "deep-nesting",
                    "JSON structure has deep nesting",
                    .warning,
                    Span.init(node.start_position, node.end_position),
                );
            }
        }

        switch (node.rule_id) {
            JsonRules.string_literal => try self.validateString(node, enabled_rules),
            JsonRules.number_literal => try self.validateNumber(node, enabled_rules),
            JsonRules.object => try self.validateObject(node, depth, enabled_rules),
            JsonRules.array => try self.validateArray(node, depth, enabled_rules),
            JsonRules.member => try self.validateMember(node, depth, enabled_rules),
            else => {}, // Ignore other node types
        }

        // Recursively validate children
        for (node.children) |*child| {
            try self.validateNode(child, depth + 1, enabled_rules);
        }
    }

    fn validateString(self: *Self, node: *const Node, enabled_rules: []const Rule) !void {
        const raw_value = node.text;

        // Check length
        if (raw_value.len > self.options.max_string_length) {
            if (self.isRuleEnabled("large-structure", &.{})) {
                try self.addDiagnostic(
                    "large-structure",
                    "String exceeds maximum length",
                    .warning,
                    Span.init(node.start_position, node.end_position),
                );
            }
        }

        // Validate UTF-8 encoding if rule is enabled
        if (self.isRuleEnabled("valid-string-encoding", enabled_rules)) {
            if (raw_value.len >= 2 and raw_value[0] == '"' and raw_value[raw_value.len - 1] == '"') {
                const content = raw_value[1 .. raw_value.len - 1];
                if (!std.unicode.utf8ValidateSlice(content)) {
                    try self.addDiagnostic(
                        "valid-string-encoding",
                        "String contains invalid UTF-8 sequences",
                        .@"error",
                        Span.init(node.start_position, node.end_position),
                    );
                }

                // Validate escape sequences
                const span = Span.init(node.start_position, node.end_position);
                try self.validateEscapeSequences(content, span, enabled_rules);
            }
        }
    }

    fn validateNumber(self: *Self, node: *const Node, enabled_rules: []const Rule) !void {
        const value = node.text;
        if (value.len == 0) return;

        // Check for leading zeros
        if (self.isRuleEnabled("no-leading-zeros", enabled_rules) and !self.options.allow_leading_zeros) {
            if (value.len > 1 and value[0] == '0' and char_utils.isDigit(value[1])) {
                try self.addDiagnostic(
                    "no-leading-zeros",
                    "Number has leading zero",
                    .warning,
                    Span.init(node.start_position, node.end_position),
                );
            }
        }

        // Check number precision
        if (self.isRuleEnabled("large-number-precision", enabled_rules) and self.options.warn_on_large_numbers) {
            if (std.mem.indexOf(u8, value, ".")) |dot_pos| {
                const decimal_part = value[dot_pos + 1 ..];
                // Remove exponent part if present
                var decimal_digits = decimal_part;
                if (std.mem.indexOfAny(u8, decimal_part, "eE")) |exp_pos| {
                    decimal_digits = decimal_part[0..exp_pos];
                }

                if (decimal_digits.len > self.options.max_number_precision) {
                    try self.addDiagnostic(
                        "large-number-precision",
                        "Number has high precision that may cause floating-point issues",
                        .warning,
                        Span.init(node.start_position, node.end_position),
                    );
                }
            }
        }

        // Validate number format
        _ = std.fmt.parseFloat(f64, value) catch {
            try self.addDiagnostic(
                "invalid-number",
                "Number format is invalid",
                .@"error",
                Span.init(node.start_position, node.end_position),
            );
        };
    }

    fn validateObject(self: *Self, node: *const Node, _: u32, _: []const Rule) !void {
        const members = node.children;

        // Check object size
        if (members.len > self.options.max_object_keys) {
            if (self.isRuleEnabled("large-structure", &.{})) {
                try self.addDiagnostic(
                    "large-structure",
                    "Object has too many keys",
                    .warning,
                    Span.init(node.start_position, node.end_position),
                );
            }
        }

        // Check for duplicate keys
        if (self.isRuleEnabled("no-duplicate-keys", &.{}) and !self.options.allow_duplicate_keys) {
            var seen_keys = std.HashMap([]const u8, Span, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(self.allocator);
            defer seen_keys.deinit();

            for (members) |member| {
                if (member.rule_id != JsonRules.member) continue;
                const member_children = member.children;
                if (member_children.len < 2) continue;

                const key_node = member_children[0];
                const key_value = key_node.text;

                // Extract key content (remove quotes)
                const key_content = if (key_value.len >= 2 and key_value[0] == '"' and key_value[key_value.len - 1] == '"')
                    key_value[1 .. key_value.len - 1]
                else
                    key_value;

                if (seen_keys.get(key_content)) |_| {
                    try self.addDiagnosticWithFix(
                        "no-duplicate-keys",
                        "Duplicate object key",
                        .@"error",
                        Span.init(key_node.start_position, key_node.end_position),
                        "Remove duplicate key or rename to make unique",
                    );
                } else {
                    try seen_keys.put(key_content, Span.init(key_node.start_position, key_node.end_position));
                }
            }
        }
    }

    fn validateArray(self: *Self, node: *const Node, _: u32, _: []const Rule) !void {
        const elements = node.children;

        // Check array size
        if (elements.len > self.options.max_array_elements) {
            if (self.isRuleEnabled("large-structure", &.{})) {
                try self.addDiagnostic(
                    "large-structure",
                    "Array has too many elements",
                    .warning,
                    Span.init(node.start_position, node.end_position),
                );
            }
        }
    }

    fn validateMember(self: *Self, node: *const Node, _: u32, _: []const Rule) !void {
        const children = node.children;
        if (children.len != 2) return;

        const key_node = children[0];

        // Validate that key is a string
        if (key_node.rule_id != JsonRules.string_literal) {
            try self.addDiagnostic(
                "invalid-key-type",
                "Object key must be a string",
                .@"error",
                Span.init(key_node.start_position, key_node.end_position),
            );
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
                                        "invalid-escape",
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
                                "invalid-escape",
                                "Incomplete Unicode escape sequence",
                                .@"error",
                                span,
                            );
                            i += 2;
                        }
                    },
                    else => {
                        try self.addDiagnostic(
                            "invalid-escape",
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

    var lexer = JsonLexer.init(allocator, input, .{});
    defer lexer.deinit();
    const tokens = try lexer.tokenize();

    var parser = JsonParser.init(allocator, tokens, .{});
    defer parser.deinit();
    var ast = try parser.parse();
    defer ast.deinit();

    const enabled_rules = &[_]Rule{
        Rule{ .name = "no-duplicate-keys", .description = "", .severity = .@"error", .enabled = true },
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
    try testing.expectEqualStrings("no-duplicate-keys", diagnostics[0].rule);
}

test "JSON linter - leading zeros" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = "01";

    var lexer = JsonLexer.init(allocator, input, .{});
    defer lexer.deinit();
    const tokens = try lexer.tokenize();

    var parser = JsonParser.init(allocator, tokens, .{});
    defer parser.deinit();
    var ast = try parser.parse();
    defer ast.deinit();

    const enabled_rules = &[_]Rule{
        Rule{ .name = "no-leading-zeros", .description = "", .severity = .warning, .enabled = true },
    };

    const diagnostics = try lintJson(allocator, ast, enabled_rules);
    defer {
        for (diagnostics) |diag| {
            allocator.free(diag.message);
        }
        allocator.free(diagnostics);
    }

    // Should find leading zero
    try testing.expect(diagnostics.len > 0);
    try testing.expectEqualStrings("no-leading-zeros", diagnostics[0].rule);
}

test "JSON linter - deep nesting" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create deeply nested structure
    const input = "{\"a\": {\"b\": {\"c\": {\"d\": {\"e\": {\"f\": 1}}}}}}";

    var lexer = JsonLexer.init(allocator, input, .{});
    defer lexer.deinit();
    const tokens = try lexer.tokenize();

    var parser = JsonParser.init(allocator, tokens, .{});
    defer parser.deinit();
    var ast = try parser.parse();
    defer ast.deinit();

    var linter = JsonLinter.init(allocator, .{ .warn_on_deep_nesting = 3 });
    defer linter.deinit();

    const enabled_rules = &[_]Rule{
        Rule{ .name = "deep-nesting", .description = "", .severity = .warning, .enabled = true },
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
