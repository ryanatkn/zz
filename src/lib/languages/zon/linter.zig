const common = @import("common.zig");
const char_utils = @import("../../char/mod.zig");
const std = common.std;
const AST = common.AST;
const Node = common.Node;
const Span = common.Span;
const utils = common.utils;
const ZonRules = @import("../../ast/rules.zig").ZonRules;

/// ZON linter with comprehensive validation rules
///
/// Features:
/// - Duplicate field detection in objects
/// - Type validation for known schemas (build.zig.zon, zz.zon)
/// - Structural validation (depth limits, size checks)
/// - ZON-specific syntax validation
/// - Configurable rules with severity levels
/// - Performance optimized for config file sizes
pub const ZonLinter = struct {
    allocator: std.mem.Allocator,
    options: ZonLintOptions,
    diagnostics: std.ArrayList(Diagnostic),

    const Self = @This();

    pub const ZonLintOptions = struct {
        max_depth: u32 = 100, // Maximum nesting depth
        max_field_count: u32 = 1000, // Maximum fields in an object
        max_array_size: u32 = 10000, // Maximum array elements
        warn_on_deep_nesting: u32 = 20, // Warn at this depth
        allow_duplicate_keys: bool = false, // Allow duplicate object keys
        check_known_schemas: bool = true, // Validate against known schemas
        strict_types: bool = false, // Strict type checking
        allow_trailing_commas: bool = true, // Allow trailing commas
        check_unused_fields: bool = false, // Check for unused fields
    };

    pub const Diagnostic = struct {
        message: []const u8,
        span: Span,
        severity: Severity,
        rule_name: []const u8,

        pub const Severity = enum {
            @"error",
            warning,
            info,
            hint,
        };

        pub fn deinit(self: Diagnostic, allocator: std.mem.Allocator) void {
            allocator.free(self.message);
        }
    };

    pub const Rule = @import("../interface.zig").Rule;

    // Built-in linting rules
    pub const RULES = [_]Rule{
        Rule{
            .name = "no-duplicate-keys",
            .description = "Object keys must be unique",
            .severity = .@"error",
            .enabled = true,
        },
        Rule{
            .name = "max-depth-exceeded",
            .description = "ZON structure exceeds maximum nesting depth",
            .severity = .@"error",
            .enabled = true,
        },
        Rule{
            .name = "large-structure",
            .description = "ZON structure is very large",
            .severity = .warning,
            .enabled = false,
        },
        Rule{
            .name = "deep-nesting",
            .description = "ZON has deep nesting that may be hard to read",
            .severity = .warning,
            .enabled = true,
        },
        Rule{
            .name = "invalid-field-type",
            .description = "Field has invalid type for known schema",
            .severity = .@"error",
            .enabled = false,
        },
        Rule{
            .name = "unknown-field",
            .description = "Field is not recognized in known schema",
            .severity = .warning,
            .enabled = false, // Disabled by default - too aggressive for general use
        },
        Rule{
            .name = "missing-required-field",
            .description = "Required field is missing from object",
            .severity = .@"error",
            .enabled = false,
        },
        Rule{
            .name = "invalid-identifier",
            .description = "Identifier uses invalid ZON syntax",
            .severity = .@"error",
            .enabled = true,
        },
        Rule{
            .name = "prefer-explicit-type",
            .description = "Consider using explicit type annotation",
            .severity = .hint,
            .enabled = false,
        },
    };

    pub fn init(allocator: std.mem.Allocator, options: ZonLintOptions) ZonLinter {
        return ZonLinter{
            .allocator = allocator,
            .options = options,
            .diagnostics = std.ArrayList(Diagnostic).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.diagnostics.items) |diag| {
            diag.deinit(self.allocator);
        }
        self.diagnostics.deinit();
    }

    /// Lint ZON AST and return diagnostics
    pub fn lint(self: *Self, ast: AST, enabled_rules: []const []const u8) ![]Diagnostic {
        self.diagnostics.clearRetainingCapacity();

        // Check if we should run each rule
        const rules_to_run = try self.filterEnabledRules(enabled_rules);
        defer self.allocator.free(rules_to_run);

        // Run structural analysis
        try self.analyzeStructure(ast.root, 0, rules_to_run);

        // Run semantic analysis for known schemas
        if (self.shouldRunRule("invalid-field-type", rules_to_run) or
            self.shouldRunRule("unknown-field", rules_to_run) or
            self.shouldRunRule("missing-required-field", rules_to_run))
        {
            try self.analyzeSemantics(ast.root);
        }

        return self.diagnostics.toOwnedSlice();
    }

    fn filterEnabledRules(self: *Self, enabled_rules: []const []const u8) ![][]const u8 {
        var result = std.ArrayList([]const u8).init(self.allocator);
        defer result.deinit();

        if (enabled_rules.len == 0) {
            // Use all enabled default rules
            for (RULES) |rule| {
                if (rule.enabled) {
                    try result.append(rule.name);
                }
            }
        } else {
            // Use specified rules
            for (enabled_rules) |rule_name| {
                try result.append(rule_name);
            }
        }

        return result.toOwnedSlice();
    }

    fn shouldRunRule(self: *const Self, rule_name: []const u8, enabled_rules: []const []const u8) bool {
        _ = self;

        for (enabled_rules) |enabled_rule| {
            if (std.mem.eql(u8, rule_name, enabled_rule)) {
                return true;
            }
        }
        return false;
    }

    fn analyzeStructure(self: *Self, node: Node, depth: u32, enabled_rules: []const []const u8) !void {
        // Check depth limits
        if (self.shouldRunRule("max-depth-exceeded", enabled_rules)) {
            if (depth > self.options.max_depth) {
                try self.addDiagnostic("max-depth-exceeded", "Structure exceeds maximum depth limit", node.start_position, node.end_position, .@"error");
                return; // Don't analyze deeper
            }
        }

        // Warn about deep nesting
        if (self.shouldRunRule("deep-nesting", enabled_rules)) {
            if (depth > self.options.warn_on_deep_nesting) {
                try self.addDiagnostic("deep-nesting", "Deep nesting may be hard to read", node.start_position, node.end_position, .warning);
            }
        }

        // Analyze specific node types
        switch (node.node_type) {
            .list => {
                switch (node.rule_id) {
                    ZonRules.object => try self.analyzeObject(node, enabled_rules),
                    ZonRules.array => try self.analyzeArray(node, enabled_rules),
                    else => {},
                }
            },
            .terminal => {
                try self.analyzeTerminal(node, enabled_rules);
            },
            else => {},
        }

        // Recursively analyze children
        for (node.children) |child| {
            try self.analyzeStructure(child, depth + 1, enabled_rules);
        }
    }

    fn analyzeObject(self: *Self, node: Node, enabled_rules: []const []const u8) !void {
        // Check object size
        if (self.shouldRunRule("large-structure", enabled_rules)) {
            const field_count = utils.countFieldAssignments(node);
            if (field_count > self.options.max_field_count) {
                try self.addDiagnostic("large-structure", "Object has too many fields", node.start_position, node.end_position, .warning);
            }
        }

        // Check for duplicate keys
        if (self.shouldRunRule("no-duplicate-keys", enabled_rules) and !self.options.allow_duplicate_keys) {
            try self.checkDuplicateKeys(node);
        }
    }

    fn analyzeArray(self: *Self, node: Node, enabled_rules: []const []const u8) !void {
        // Check array size
        if (self.shouldRunRule("large-structure", enabled_rules)) {
            if (node.children.len > self.options.max_array_size) {
                try self.addDiagnostic("large-structure", "Array has too many elements", node.start_position, node.end_position, .warning);
            }
        }
    }

    fn analyzeTerminal(self: *Self, node: Node, enabled_rules: []const []const u8) !void {
        // Check identifier validity
        if (self.shouldRunRule("invalid-identifier", enabled_rules)) {
            if (node.rule_id == ZonRules.identifier or
                node.rule_id == ZonRules.field_name)
            {
                try self.checkIdentifierValidity(node);
            }
        }
    }

    fn checkDuplicateKeys(self: *Self, object_node: Node) !void {
        var seen_keys = std.StringHashMap(Span).init(self.allocator);
        defer seen_keys.deinit();

        for (object_node.children) |child| {
            if (utils.isFieldAssignment(child) and utils.hasMinimumChildren(child, 1)) {
                const field_name_node = child.children[0];
                const field_text = field_name_node.text;

                // Extract field name using utils
                const key_name = utils.extractFieldName(field_text);

                if (seen_keys.get(key_name)) |previous_span| {
                    // Duplicate key found
                    const message = try std.fmt.allocPrint(self.allocator, "Duplicate key '{s}' (previously defined at position {})", .{ key_name, previous_span.start });

                    try self.addDiagnosticOwned("no-duplicate-keys", message, field_name_node.start_position, field_name_node.end_position, .@"error");
                } else {
                    try seen_keys.put(key_name, Span{ .start = field_name_node.start_position, .end = field_name_node.end_position });
                }
            }
        }
    }

    fn checkIdentifierValidity(self: *Self, node: Node) !void {
        const text = node.text;

        // Check for empty identifier
        if (text.len == 0) {
            try self.addDiagnostic("invalid-identifier", "Empty identifier", node.start_position, node.end_position, .@"error");
            return;
        }

        // Check field name format (.field_name)
        if (node.rule_id == ZonRules.field_name) {
            if (text[0] != '.') {
                try self.addDiagnostic("invalid-identifier", "Field name must start with '.'", node.start_position, node.end_position, .@"error");
                return;
            }

            if (text.len == 1) {
                try self.addDiagnostic("invalid-identifier", "Field name cannot be just '.'", node.start_position, node.end_position, .@"error");
                return;
            }

            // Check the identifier part after the dot
            const identifier_part = text[1..];
            try self.validateIdentifierText(identifier_part, node);
        } else {
            // Regular identifier
            try self.validateIdentifierText(text, node);
        }
    }

    fn validateIdentifierText(self: *Self, text: []const u8, node: Node) !void {
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
            try self.addDiagnostic("invalid-identifier", "Identifier must start with letter or underscore", node.start_position, node.end_position, .@"error");
            return;
        }

        // Remaining characters must be alphanumeric or underscore
        for (text[1..]) |char| {
            if (!char_utils.isAlphaNumeric(char) and char != '_') {
                try self.addDiagnostic("invalid-identifier", "Identifier contains invalid character", node.start_position, node.end_position, .@"error");
                return;
            }
        }
    }

    fn analyzeSemantics(self: *Self, root_node: Node) !void {
        // Try to detect what kind of ZON file this is
        const schema_type = self.detectSchemaType(root_node);

        switch (schema_type) {
            .build_zig_zon => try self.validateBuildZigZon(root_node),
            .zz_zon => try self.validateZzZon(root_node),
            .unknown => {
                // Generic validation - no specific schema
            },
        }
    }

    const SchemaType = enum {
        build_zig_zon,
        zz_zon,
        unknown,
    };

    fn detectSchemaType(self: *const Self, root_node: Node) SchemaType {
        _ = self;

        // Look for known fields to detect schema type
        for (root_node.children) |child| {
            if (utils.isFieldAssignment(child) and utils.hasMinimumChildren(child, 1)) {
                const field_name_node = child.children[0];
                const field_text = field_name_node.text;

                // Extract field name using utils
                const field_name = utils.extractFieldName(field_text);

                // Check for build.zig.zon specific fields
                if (std.mem.eql(u8, field_name, "name") or
                    std.mem.eql(u8, field_name, "version") or
                    std.mem.eql(u8, field_name, "dependencies") or
                    std.mem.eql(u8, field_name, "paths"))
                {
                    return .build_zig_zon;
                }

                // Check for zz.zon specific fields
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

    fn validateBuildZigZon(self: *Self, root_node: Node) !void {
        // Check for required fields in build.zig.zon
        var has_name = false;
        var has_version = false;

        for (root_node.children) |child| {
            if (utils.isFieldAssignment(child) and utils.hasMinimumChildren(child, 2)) {
                const field_name_node = child.children[0];
                const value_node = utils.getFieldValue(child) orelse continue;
                const field_text = field_name_node.text;

                const field_name = if (field_text.len > 0 and field_text[0] == '.')
                    field_text[1..]
                else
                    field_text;

                if (std.mem.eql(u8, field_name, "name")) {
                    has_name = true;
                    // Validate name is a string or identifier
                    if (value_node.rule_id != ZonRules.string_literal and
                        value_node.rule_id != ZonRules.identifier)
                    {
                        try self.addDiagnostic("invalid-field-type", "Package name must be a string or identifier", value_node.start_position, value_node.end_position, .@"error");
                    }
                } else if (std.mem.eql(u8, field_name, "version")) {
                    has_version = true;
                    // Validate version is a string
                    if (value_node.rule_id != ZonRules.string_literal) {
                        try self.addDiagnostic("invalid-field-type", "Version must be a string", value_node.start_position, value_node.end_position, .@"error");
                    }
                } else if (std.mem.eql(u8, field_name, "dependencies")) {
                    // Validate dependencies is an object
                    if (value_node.rule_id != ZonRules.object) {
                        try self.addDiagnostic("invalid-field-type", "Dependencies must be an object", value_node.start_position, value_node.end_position, .@"error");
                    }
                } else if (std.mem.eql(u8, field_name, "paths")) {
                    // Validate paths is an array
                    if (value_node.rule_id != ZonRules.array) {
                        try self.addDiagnostic("invalid-field-type", "Paths must be an array", value_node.start_position, value_node.end_position, .@"error");
                    }
                }
            }
        }

        // Check for required fields
        if (!has_name) {
            try self.addDiagnostic("missing-required-field", "Missing required field 'name' in build.zig.zon", root_node.start_position, root_node.start_position, .@"error");
        }

        if (!has_version) {
            try self.addDiagnostic("missing-required-field", "Missing required field 'version' in build.zig.zon", root_node.start_position, root_node.start_position, .@"error");
        }
    }

    fn validateZzZon(self: *Self, root_node: Node) !void {
        // Validate zz.zon configuration fields
        for (root_node.children) |child| {
            if (utils.isFieldAssignment(child) and utils.hasMinimumChildren(child, 2)) {
                const field_name_node = child.children[0];
                const value_node = utils.getFieldValue(child) orelse continue;
                const field_text = field_name_node.text;

                const field_name = if (field_text.len > 0 and field_text[0] == '.')
                    field_text[1..]
                else
                    field_text;

                if (std.mem.eql(u8, field_name, "base_patterns")) {
                    // Should be a string
                    if (value_node.rule_id != ZonRules.string_literal) {
                        try self.addDiagnostic("invalid-field-type", "base_patterns should be a string", value_node.start_position, value_node.end_position, .warning);
                    }
                } else if (std.mem.eql(u8, field_name, "ignored_patterns")) {
                    // Should be an array
                    if (value_node.rule_id != ZonRules.array) {
                        try self.addDiagnostic("invalid-field-type", "ignored_patterns should be an array", value_node.start_position, value_node.end_position, .warning);
                    }
                } else if (std.mem.eql(u8, field_name, "respect_gitignore")) {
                    // Should be a boolean
                    if (value_node.rule_id != ZonRules.boolean_literal) {
                        try self.addDiagnostic("invalid-field-type", "respect_gitignore should be a boolean", value_node.start_position, value_node.end_position, .warning);
                    }
                }
            }
        }
    }

    fn addDiagnostic(self: *Self, rule_name: []const u8, message: []const u8, start_pos: usize, end_pos: usize, severity: Diagnostic.Severity) !void {
        const owned_message = try self.allocator.dupe(u8, message);
        try self.addDiagnosticOwned(rule_name, owned_message, start_pos, end_pos, severity);
    }

    fn addDiagnosticOwned(self: *Self, rule_name: []const u8, owned_message: []const u8, start_pos: usize, end_pos: usize, severity: Diagnostic.Severity) !void {
        const diagnostic = Diagnostic{
            .message = owned_message,
            .span = Span{
                .start = start_pos,
                .end = end_pos,
            },
            .severity = severity,
            .rule_name = rule_name,
        };

        try self.diagnostics.append(diagnostic);
    }
};

/// Convenience function for linting ZON AST
pub fn lint(allocator: std.mem.Allocator, ast: AST, enabled_rules: []const []const u8) ![]ZonLinter.Diagnostic {
    var linter = ZonLinter.init(allocator, .{});
    defer linter.deinit();
    return linter.lint(ast, enabled_rules);
}

/// Lint ZON string directly (convenience function)
pub fn lintZonString(allocator: std.mem.Allocator, zon_content: []const u8, enabled_rules: []const []const u8) ![]ZonLinter.Diagnostic {
    // Import our lexer and parser
    const ZonLexer = @import("lexer.zig").ZonLexer;
    const ZonParser = @import("parser.zig").ZonParser;

    // Tokenize
    var lexer = ZonLexer.init(allocator, zon_content, .{});
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);

    // Parse
    var parser = ZonParser.init(allocator, tokens, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    // Lint
    var linter = ZonLinter.init(allocator, .{});
    defer linter.deinit();

    return linter.lint(ast, enabled_rules);
}
