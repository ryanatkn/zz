const std = @import("std");

const common = @import("common.zig");
const char_utils = @import("../../char/mod.zig");
// Using local enum-based rule system (ZonRuleType defined below)
const ZonLexer = @import("lexer.zig").ZonLexer;
const ZonParser = @import("parser.zig").ZonParser;

// Import interface types
const interface_types = @import("../interface.zig");
const InterfaceSeverity = interface_types.RuleInfo.Severity;

/// ZON-specific linting rules
///
/// Performance Notes - Enum Rule System:
/// - enum(u8) supports up to 256 rules per language
/// - Current usage: ZON=9 rules (well under limit)
/// - EnumSet performance characteristics:
///   * ≤64 rules: Single u64 register, 1-2 CPU cycles for checks
///   * ≤128 rules: Single u128, 2-3 CPU cycles
///   * >128 rules: Bit array, 3-5 CPU cycles
/// - Future expansion: Change to enum(u16) if >256 rules needed
pub const ZonRuleType = enum(u8) {
    no_duplicate_keys,
    max_depth_exceeded,
    large_structure,
    deep_nesting,
    invalid_field_type,
    unknown_field,
    missing_required_field,
    invalid_identifier,
    prefer_explicit_type,
};

/// Efficient rule set using bitflags for O(1) lookups
pub const EnabledRules = std.EnumSet(ZonRuleType);

const AST = common.AST;
const Node = common.Node;
const Span = common.Span;
const utils = common.utils;

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
            err,
            warning,
            info,
            hint,
        };

        pub fn deinit(self: Diagnostic, allocator: std.mem.Allocator) void {
            allocator.free(self.message);
        }
    };

    /// Rule metadata for each enum value
    pub const RuleInfo = struct {
        name: []const u8,
        description: []const u8,
        severity: InterfaceSeverity,
        enabled_by_default: bool,
    };

    /// Built-in linting rules metadata
    pub const RULE_INFO = std.EnumArray(ZonRuleType, RuleInfo).init(.{
        .no_duplicate_keys = .{
            .name = "no-duplicate-keys",
            .description = "Object keys must be unique",
            .severity = .err,
            .enabled_by_default = true,
        },
        .max_depth_exceeded = .{
            .name = "max-depth-exceeded",
            .description = "ZON structure exceeds maximum nesting depth",
            .severity = .err,
            .enabled_by_default = true,
        },
        .large_structure = .{
            .name = "large-structure",
            .description = "ZON structure is very large",
            .severity = .warning,
            .enabled_by_default = false,
        },
        .deep_nesting = .{
            .name = "deep-nesting",
            .description = "ZON has deep nesting that may be hard to read",
            .severity = .warning,
            .enabled_by_default = true,
        },
        .invalid_field_type = .{
            .name = "invalid-field-type",
            .description = "Field has invalid type for known schema",
            .severity = .err,
            .enabled_by_default = false,
        },
        .unknown_field = .{
            .name = "unknown-field",
            .description = "Field is not recognized in known schema",
            .severity = .warning,
            .enabled_by_default = false, // Disabled by default - too aggressive for general use
        },
        .missing_required_field = .{
            .name = "missing-required-field",
            .description = "Required field is missing from object",
            .severity = .err,
            .enabled_by_default = false,
        },
        .invalid_identifier = .{
            .name = "invalid-identifier",
            .description = "Identifier uses invalid ZON syntax",
            .severity = .err,
            .enabled_by_default = true,
        },
        .prefer_explicit_type = .{
            .name = "prefer-explicit-type",
            .description = "Consider using explicit type annotation",
            .severity = .hint,
            .enabled_by_default = false,
        },
    });

    /// Get default enabled rules
    pub fn getDefaultRules() EnabledRules {
        var rules = EnabledRules.initEmpty();
        inline for (std.meta.fields(ZonRuleType)) |field| {
            const rule_type = @field(ZonRuleType, field.name);
            if (RULE_INFO.get(rule_type).enabled_by_default) {
                rules.insert(rule_type);
            }
        }
        return rules;
    }

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
    pub fn lint(self: *Self, ast: AST, enabled_rules: EnabledRules) ![]Diagnostic {
        self.diagnostics.clearRetainingCapacity();

        // Run structural analysis
        if (ast.root) |root| {
            try self.analyzeStructure(root.*, 0, enabled_rules);
        }

        // Run semantic analysis for known schemas
        if (enabled_rules.contains(.invalid_field_type) or
            enabled_rules.contains(.unknown_field) or
            enabled_rules.contains(.missing_required_field))
        {
            if (ast.root) |root| {
                try self.analyzeSemantics(root.*);
            }
        }

        return self.diagnostics.toOwnedSlice();
    }

    fn analyzeStructure(self: *Self, node: Node, depth: u32, enabled_rules: EnabledRules) !void {
        // Check depth limits
        if (enabled_rules.contains(.max_depth_exceeded)) {
            if (depth > self.options.max_depth) {
                const node_span = node.span();
                try self.addDiagnostic("max-depth-exceeded", "Structure exceeds maximum depth limit", node_span.start, node_span.end, .err);
                return; // Don't analyze deeper
            }
        }

        // Warn about deep nesting
        if (enabled_rules.contains(.deep_nesting)) {
            if (depth > self.options.warn_on_deep_nesting) {
                const span = node.span();
                try self.addDiagnostic("deep-nesting", "Deep nesting may be hard to read", span.start, span.end, .warning);
            }
        }

        // Analyze specific node types using tagged union matching
        switch (node) {
            .object => try self.analyzeObject(node, enabled_rules),
            .array => try self.analyzeArray(node, enabled_rules),
            .string, .number, .boolean, .null, .identifier, .field_name => try self.analyzeTerminal(node, enabled_rules),
            .field => try self.analyzeField(node, enabled_rules),
            else => {}, // Handle other node types as needed
        }

        // Recursively analyze children based on node type
        switch (node) {
            .object => |obj| {
                for (obj.fields) |child| {
                    try self.analyzeStructure(child, depth + 1, enabled_rules);
                }
            },
            .array => |arr| {
                for (arr.elements) |child| {
                    try self.analyzeStructure(child, depth + 1, enabled_rules);
                }
            },
            .field => |field| {
                try self.analyzeStructure(field.name.*, depth + 1, enabled_rules);
                try self.analyzeStructure(field.value.*, depth + 1, enabled_rules);
            },
            else => {}, // Leaf nodes have no children
        }
    }

    fn analyzeObject(self: *Self, node: Node, enabled_rules: EnabledRules) !void {
        // Check object size
        if (enabled_rules.contains(.large_structure)) {
            const field_count = utils.countFieldAssignments(node);
            if (field_count > self.options.max_field_count) {
                const span = node.span();
                try self.addDiagnostic("large-structure", "Object has too many fields", span.start, span.end, .warning);
            }
        }

        // Check for duplicate keys
        if (enabled_rules.contains(.no_duplicate_keys) and !self.options.allow_duplicate_keys) {
            try self.checkDuplicateKeys(node);
        }
    }

    fn analyzeArray(self: *Self, node: Node, enabled_rules: EnabledRules) !void {
        // Check array size
        if (enabled_rules.contains(.large_structure)) {
            if (node == .array) {
                const arr = node.array;
                if (arr.elements.len > self.options.max_array_size) {
                    try self.addDiagnostic("large-structure", "Array has too many elements", arr.span.start, arr.span.end, .warning);
                }
            }
        }
    }

    fn analyzeTerminal(self: *Self, node: Node, enabled_rules: EnabledRules) !void {
        // Check identifier validity
        if (enabled_rules.contains(.invalid_identifier)) {
            switch (node) {
                .identifier, .field_name => try self.checkIdentifierValidity(node),
                else => {},
            }
        }
    }

    fn analyzeField(self: *Self, node: Node, enabled_rules: EnabledRules) !void {
        // Analyze field assignments
        if (node == .field) {
            // Could add field-specific linting rules here
            _ = self;
            _ = enabled_rules;
        }
    }

    fn checkDuplicateKeys(self: *Self, object_node: Node) !void {
        if (object_node != .object) return; // Only check objects

        var seen_keys = std.StringHashMap(Span).init(self.allocator);
        defer seen_keys.deinit();

        const obj = object_node.object;
        for (obj.fields) |field| {
            if (field == .field) {
                const field_data = field.field;
                const field_name = utils.getFieldName(field) orelse continue;
                const key_name = utils.extractFieldName(field_name);
                const field_span = field_data.name.span();

                if (seen_keys.get(key_name)) |previous_span| {
                    // Duplicate key found
                    const message = try std.fmt.allocPrint(self.allocator, "Duplicate key '{s}' (previously defined at position {})", .{ key_name, previous_span.start });

                    try self.addDiagnosticOwned("no-duplicate-keys", message, field_span.start, field_span.end, .err);
                } else {
                    try seen_keys.put(key_name, field_span);
                }
            }
        }
    }

    fn checkIdentifierValidity(self: *Self, node: Node) !void {
        const text = utils.getNodeText(node, "");

        // Check for empty identifier
        if (text.len == 0) {
            const span = node.span();
            try self.addDiagnostic("invalid-identifier", "Empty identifier", span.start, span.end, .err);
            return;
        }

        // Check field name format (.field_name)
        switch (node) {
            .field_name => |field_name| {
                if (text[0] != '.') {
                    try self.addDiagnostic("invalid-identifier", "Field name must start with '.'", field_name.span.start, field_name.span.end, .err);
                    return;
                }

                if (text.len == 1) {
                    try self.addDiagnostic("invalid-identifier", "Field name cannot be just '.'", field_name.span.start, field_name.span.end, .err);
                    return;
                }

                // Check the identifier part after the dot
                const identifier_part = text[1..];
                try self.validateIdentifierText(identifier_part, node);
            },
            else => {
                // Regular identifier
                try self.validateIdentifierText(text, node);
            },
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
            const span = node.span();
            try self.addDiagnostic("invalid-identifier", "Identifier must start with letter or underscore", span.start, span.end, .err);
            return;
        }

        // Remaining characters must be alphanumeric or underscore
        for (text[1..]) |char| {
            if (!char_utils.isAlphaNumeric(char) and char != '_') {
                const span = node.span();
                try self.addDiagnostic("invalid-identifier", "Identifier contains invalid character", span.start, span.end, .err);
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

        // Get the actual object from root
        const object_node = switch (root_node) {
            .root => |root| root.value.*,
            .object => root_node,
            else => return .unknown,
        };

        if (object_node != .object) return .unknown;

        // Look for known fields to detect schema type
        const obj = object_node.object;
        for (obj.fields) |field| {
            if (field == .field) {
                const field_name = utils.getFieldName(field) orelse continue;
                const extracted_name = utils.extractFieldName(field_name);

                // Check for build.zig.zon specific fields
                if (std.mem.eql(u8, extracted_name, "name") or
                    std.mem.eql(u8, extracted_name, "version") or
                    std.mem.eql(u8, extracted_name, "dependencies") or
                    std.mem.eql(u8, extracted_name, "paths"))
                {
                    return .build_zig_zon;
                }

                // Check for zz.zon specific fields
                if (std.mem.eql(u8, extracted_name, "base_patterns") or
                    std.mem.eql(u8, extracted_name, "ignored_patterns") or
                    std.mem.eql(u8, extracted_name, "symlink_behavior"))
                {
                    return .zz_zon;
                }
            }
        }

        return .unknown;
    }

    fn validateBuildZigZon(self: *Self, root_node: Node) !void {
        // Get the actual object from root
        const object_node = switch (root_node) {
            .root => |root| root.value.*,
            .object => root_node,
            else => return,
        };

        if (object_node != .object) return;

        // Check for required fields in build.zig.zon
        var has_name = false;
        var has_version = false;
        const obj = object_node.object;

        for (obj.fields) |field| {
            if (field == .field) {
                const field_data = field.field;
                const value_node = field_data.value.*;
                const field_name = utils.getFieldName(field) orelse continue;
                const extracted_name = utils.extractFieldName(field_name);

                if (std.mem.eql(u8, extracted_name, "name")) {
                    has_name = true;
                    // Validate name is a string or identifier
                    switch (value_node) {
                        .string, .identifier => {}, // Valid types
                        else => try self.addDiagnostic("invalid-field-type", "Package name must be a string or identifier", value_node.span().start, value_node.span().end, .err),
                    }
                } else if (std.mem.eql(u8, extracted_name, "version")) {
                    has_version = true;
                    // Validate version is a string
                    switch (value_node) {
                        .string => {}, // Valid type
                        else => try self.addDiagnostic("invalid-field-type", "Version must be a string", value_node.span().start, value_node.span().end, .err),
                    }
                } else if (std.mem.eql(u8, extracted_name, "dependencies")) {
                    // Validate dependencies is an object
                    switch (value_node) {
                        .object => {}, // Valid type
                        else => try self.addDiagnostic("invalid-field-type", "Dependencies must be an object", value_node.span().start, value_node.span().end, .err),
                    }
                } else if (std.mem.eql(u8, extracted_name, "paths")) {
                    // Validate paths is an array
                    switch (value_node) {
                        .array => {}, // Valid type
                        else => try self.addDiagnostic("invalid-field-type", "Paths must be an array", value_node.span().start, value_node.span().end, .err),
                    }
                }
            }
        }

        // Check for required fields
        if (!has_name) {
            const span = root_node.span();
            try self.addDiagnostic("missing-required-field", "Missing required field 'name' in build.zig.zon", span.start, span.start, .err);
        }

        if (!has_version) {
            const span = root_node.span();
            try self.addDiagnostic("missing-required-field", "Missing required field 'version' in build.zig.zon", span.start, span.start, .err);
        }
    }

    fn validateZzZon(self: *Self, root_node: Node) !void {
        // Get the actual object from root
        const object_node = switch (root_node) {
            .root => |root| root.value.*,
            .object => root_node,
            else => return,
        };

        if (object_node != .object) return;

        // Validate zz.zon configuration fields
        const obj = object_node.object;
        for (obj.fields) |field| {
            if (field == .field) {
                const field_data = field.field;
                const value_node = field_data.value.*;
                const field_name = utils.getFieldName(field) orelse continue;
                const extracted_name = utils.extractFieldName(field_name);

                if (std.mem.eql(u8, extracted_name, "base_patterns")) {
                    // Should be a string
                    switch (value_node) {
                        .string => {}, // Valid type
                        else => try self.addDiagnostic("invalid-field-type", "base_patterns should be a string", value_node.span().start, value_node.span().end, .warning),
                    }
                } else if (std.mem.eql(u8, extracted_name, "ignored_patterns")) {
                    // Should be an array
                    switch (value_node) {
                        .array => {}, // Valid type
                        else => try self.addDiagnostic("invalid-field-type", "ignored_patterns should be an array", value_node.span().start, value_node.span().end, .warning),
                    }
                } else if (std.mem.eql(u8, extracted_name, "respect_gitignore")) {
                    // Should be a boolean
                    switch (value_node) {
                        .boolean => {}, // Valid type
                        else => try self.addDiagnostic("invalid-field-type", "respect_gitignore should be a boolean", value_node.span().start, value_node.span().end, .warning),
                    }
                }
            }
        }
    }

    fn addDiagnostic(self: *Self, rule_name: []const u8, message: []const u8, start_pos: u32, end_pos: u32, severity: Diagnostic.Severity) !void {
        const owned_message = try self.allocator.dupe(u8, message);
        try self.addDiagnosticOwned(rule_name, owned_message, start_pos, end_pos, severity);
    }

    fn addDiagnosticOwned(self: *Self, rule_name: []const u8, owned_message: []const u8, start_pos: u32, end_pos: u32, severity: Diagnostic.Severity) !void {
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
