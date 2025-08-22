const common = @import("common.zig");
const std = common.std;
const Node = common.Node;
const AST = common.AST;
const utils = common.utils;
// ZonNodeRule removed - using tagged unions now

/// Validate ZON content against known schemas
/// This module provides schema validation for common ZON configuration files
pub const ZonValidator = struct {
    allocator: std.mem.Allocator,
    errors: std.ArrayList(ValidationError),

    const Self = @This();

    pub const ValidationError = struct {
        field_path: []const u8,
        message: []const u8,
        severity: Severity,

        pub const Severity = enum {
            err,
            warning,
            info,
        };

        pub fn deinit(self: ValidationError, allocator: std.mem.Allocator) void {
            allocator.free(self.field_path);
            allocator.free(self.message);
        }
    };

    pub fn init(allocator: std.mem.Allocator) ZonValidator {
        return .{
            .allocator = allocator,
            .errors = std.ArrayList(ValidationError).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.errors.items) |error_item| {
            error_item.deinit(self.allocator);
        }
        self.errors.deinit();
    }

    /// Get the list of validation errors
    pub fn getErrors(self: *const Self) []const ValidationError {
        return self.errors.items;
    }

    /// Clear all validation errors
    pub fn clearErrors(self: *Self) void {
        for (self.errors.items) |error_item| {
            error_item.deinit(self.allocator);
        }
        self.errors.clearRetainingCapacity();
    }

    /// Validate build.zig.zon file
    pub fn validateBuildZon(self: *Self, ast: AST) !void {
        self.clearErrors();
        try self.validateAgainstSchema(ast.root, &BUILD_ZON_SCHEMA, "");
    }

    /// Validate zz.zon configuration file
    pub fn validateZzConfig(self: *Self, ast: AST) !void {
        self.clearErrors();
        try self.validateAgainstSchema(ast.root, &ZZ_CONFIG_SCHEMA, "");
    }

    /// Validate package manager dependencies
    pub fn validateDependencies(self: *Self, ast: AST) !void {
        self.clearErrors();

        // Find dependencies field
        const deps_node = self.findField(ast.root, "dependencies") orelse {
            try self.addError("", "Missing 'dependencies' field", .warning);
            return;
        };

        // Validate each dependency
        for (deps_node.children) |child| {
            if (utils.isFieldAssignment(child)) {
                try self.validateDependency(child);
            }
        }
    }

    /// Validate against a specific schema
    fn validateAgainstSchema(self: *Self, node: Node, schema: *const Schema, path: []const u8) !void {
        // Find the object node
        const object_node = self.findObjectNode(node) orelse {
            try self.addError(path, "Expected object", .err);
            return;
        };

        // Check required fields
        for (schema.required_fields) |required_field| {
            if (self.findField(object_node, required_field.name) == null) {
                const field_path = try std.fmt.allocPrint(self.allocator, "{s}{s}{s}", .{
                    path,
                    if (path.len > 0) "." else "",
                    required_field.name,
                });
                defer self.allocator.free(field_path);

                const message = try std.fmt.allocPrint(self.allocator, "Missing required field '{s}'", .{required_field.name});
                try self.addError(field_path, message, .err);
            }
        }

        // Validate present fields
        for (object_node.children) |child| {
            if (utils.isFieldAssignment(child)) {
                try self.validateField(child, schema, path);
            }
        }
    }

    /// Validate a single field
    fn validateField(self: *Self, node: Node, schema: *const Schema, parent_path: []const u8) !void {
        if (!utils.hasMinimumChildren(node, 2)) return;

        const field_name_node = node.children[0];
        var field_name = field_name_node.text;

        // Extract field name using utils
        field_name = utils.extractFieldName(field_name);

        // Handle @"..." quoted names
        if (std.mem.indexOf(u8, field_name, "@\"")) |at_pos| {
            const start = at_pos + 2;
            if (std.mem.indexOf(u8, field_name[start..], "\"")) |end_quote| {
                field_name = field_name[start..][0..end_quote];
            }
        }

        const field_path = try std.fmt.allocPrint(self.allocator, "{s}{s}{s}", .{
            parent_path,
            if (parent_path.len > 0) "." else "",
            field_name,
        });
        defer self.allocator.free(field_path);

        // Check if field is known
        var field_spec: ?FieldSpec = null;

        for (schema.required_fields) |spec| {
            if (std.mem.eql(u8, spec.name, field_name)) {
                field_spec = spec;
                break;
            }
        }

        if (field_spec == null) {
            for (schema.optional_fields) |spec| {
                if (std.mem.eql(u8, spec.name, field_name)) {
                    field_spec = spec;
                    break;
                }
            }
        }

        if (field_spec == null and !schema.allow_unknown_fields) {
            const message = try std.fmt.allocPrint(self.allocator, "Unknown field '{s}'", .{field_name});
            try self.addError(field_path, message, .warning);
            return;
        }

        // Validate field type if spec is found
        if (field_spec) |spec| {
            const value_node = utils.getFieldValue(node) orelse return;
            try self.validateFieldType(value_node, spec, field_path);
        }
    }

    /// Validate field type matches specification
    fn validateFieldType(self: *Self, node: Node, spec: FieldSpec, path: []const u8) !void {
        switch (spec.field_type) {
            .string => {
                switch (node) {
                    .string => {}, // Valid type
                    else => {
                        const message = try std.fmt.allocPrint(self.allocator, "Expected string, got {s}", .{@tagName(node)});
                        try self.addError(path, message, .err);
                    },
                }
            },
            .number => {
                switch (node) {
                    .number => {}, // Valid type
                    else => {
                        const message = try std.fmt.allocPrint(self.allocator, "Expected number, got {s}", .{@tagName(node)});
                        try self.addError(path, message, .err);
                    },
                }
            },
            .boolean => {
                switch (node) {
                    .boolean => {}, // Valid type
                    else => {
                        const message = try std.fmt.allocPrint(self.allocator, "Expected boolean, got {s}", .{@tagName(node)});
                        try self.addError(path, message, .err);
                    },
                }
            },
            .object => {
                switch (node) {
                    .object => {
                        if (spec.nested_schema) |nested_schema| {
                            try self.validateAgainstSchema(node, nested_schema, path);
                        }
                    },
                    else => {
                        const message = try std.fmt.allocPrint(self.allocator, "Expected object, got {s}", .{@tagName(node)});
                        try self.addError(path, message, .err);
                    },
                }
            },
            .array => {
                switch (node) {
                    .array => {}, // Valid type
                    else => {
                        const message = try std.fmt.allocPrint(self.allocator, "Expected array, got {s}", .{@tagName(node)});
                        try self.addError(path, message, .err);
                    },
                }
            },
            .@"enum" => {
                if (spec.enum_values) |values| {
                    var valid = false;
                    const text = node.text;

                    for (values) |allowed_value| {
                        if (std.mem.eql(u8, text, allowed_value)) {
                            valid = true;
                            break;
                        }
                    }

                    if (!valid) {
                        const message = try std.fmt.allocPrint(self.allocator, "Invalid enum value '{s}'", .{text});
                        try self.addError(path, message, .err);
                    }
                }
            },
        }
    }

    /// Validate a single dependency entry
    fn validateDependency(self: *Self, node: Node) !void {
        if (!utils.hasMinimumChildren(node, 2)) return;

        const name_node = node.children[0];
        var dep_name = name_node.text;

        // Clean up dependency name
        if (dep_name.len > 0 and dep_name[0] == '.') {
            dep_name = dep_name[1..];
        }

        const value_node = utils.getFieldValue(node) orelse return;

        // Check for required dependency fields
        const url_field = self.findField(value_node, "url");
        const path_field = self.findField(value_node, "path");

        if (url_field == null and path_field == null) {
            const message = try std.fmt.allocPrint(self.allocator, "Dependency '{s}' must have either 'url' or 'path' field", .{dep_name});
            try self.addError(dep_name, message, .err);
        }

        if (url_field != null and path_field != null) {
            const message = try std.fmt.allocPrint(self.allocator, "Dependency '{s}' cannot have both 'url' and 'path' fields", .{dep_name});
            try self.addError(dep_name, message, .err);
        }

        // TODO: Rewrite URL validation for tagged union AST
        // Validate URL format if present
        // if (url_field) |url_node| {
        //     if (utils.hasMinimumChildren(url_node, 2)) {
        //         const url_value = url_node.children[1];
        //         if (utils.isTerminalOfType(url_value, ZonNodeRule.string_literal.toU16())) {
        //             try self.validateUrl(url_value.text, dep_name);
        //         }
        //     }
        // }
    }

    /// Validate URL format
    fn validateUrl(self: *Self, url: []const u8, context: []const u8) !void {
        // Remove quotes if present
        var clean_url = url;
        if (clean_url.len >= 2 and clean_url[0] == '"' and clean_url[clean_url.len - 1] == '"') {
            clean_url = clean_url[1 .. clean_url.len - 1];
        }

        // Basic URL validation
        if (!std.mem.startsWith(u8, clean_url, "https://") and
            !std.mem.startsWith(u8, clean_url, "http://") and
            !std.mem.startsWith(u8, clean_url, "git://") and
            !std.mem.startsWith(u8, clean_url, "file://"))
        {
            const message = try std.fmt.allocPrint(self.allocator, "Invalid URL format in '{s}': {s}", .{ context, clean_url });
            try self.addError(context, message, .warning);
        }
    }

    /// Add a validation error
    fn addError(self: *Self, path: []const u8, message: []const u8, severity: ValidationError.Severity) !void {
        try self.errors.append(.{
            .field_path = try self.allocator.dupe(u8, path),
            .message = try self.allocator.dupe(u8, message),
            .severity = severity,
        });
    }

    /// Find a field in an object node
    fn findField(self: *Self, node: Node, field_name: []const u8) ?Node {
        _ = self;

        for (node.children) |child| {
            if (utils.isFieldAssignment(child)) {
                if (utils.hasMinimumChildren(child, 1)) {
                    var name = child.children[0].text;

                    // Clean up field name
                    if (name.len > 0 and name[0] == '.') {
                        name = name[1..];
                    }

                    // Handle @"..." format
                    if (std.mem.indexOf(u8, name, "@\"")) |at_pos| {
                        const start = at_pos + 2;
                        if (std.mem.indexOf(u8, name[start..], "\"")) |end_quote| {
                            name = name[start..][0..end_quote];
                        }
                    }

                    if (std.mem.eql(u8, name, field_name)) {
                        return utils.getFieldValue(child) orelse child;
                    }
                }
            }
        }

        return null;
    }

    /// Find an object node in the AST
    fn findObjectNode(self: *Self, node: Node) ?Node {
        switch (node) {
            .object => return node,
            .root => |root| return self.findObjectNode(root.value.*),
            else => return null,
        }

        // Search in children
        for (node.children) |child| {
            if (self.findObjectNode(child)) |obj| {
                return obj;
            }
        }

        return null;
    }
};

/// Schema definition for validation
const Schema = struct {
    required_fields: []const FieldSpec,
    optional_fields: []const FieldSpec,
    allow_unknown_fields: bool = false,
};

/// Field specification
const FieldSpec = struct {
    name: []const u8,
    field_type: FieldType,
    nested_schema: ?*const Schema = null,
    enum_values: ?[]const []const u8 = null,
    description: ?[]const u8 = null,
};

/// Supported field types
const FieldType = enum {
    string,
    number,
    boolean,
    object,
    array,
    @"enum",
};

// ============================================================================
// Predefined Schemas
// ============================================================================

/// Schema for build.zig.zon files
const BUILD_ZON_SCHEMA = Schema{
    .required_fields = &[_]FieldSpec{
        .{ .name = "name", .field_type = .string, .description = "Package name" },
        .{ .name = "version", .field_type = .string, .description = "Package version" },
    },
    .optional_fields = &[_]FieldSpec{
        .{ .name = "dependencies", .field_type = .object, .description = "Package dependencies" },
        .{ .name = "paths", .field_type = .array, .description = "Source paths" },
        .{ .name = "description", .field_type = .string, .description = "Package description" },
        .{ .name = "license", .field_type = .string, .description = "License identifier" },
        .{ .name = "homepage", .field_type = .string, .description = "Project homepage" },
        .{ .name = "min_zig_version", .field_type = .string, .description = "Minimum Zig version" },
    },
    .allow_unknown_fields = true, // Allow custom fields
};

/// Schema for zz.zon configuration files
const ZZ_CONFIG_SCHEMA = Schema{
    .required_fields = &[_]FieldSpec{},
    .optional_fields = &[_]FieldSpec{
        .{ .name = "format", .field_type = .object, .nested_schema = &FORMAT_CONFIG_SCHEMA, .description = "Formatting configuration" },
        .{ .name = "lint", .field_type = .object, .nested_schema = &LINT_CONFIG_SCHEMA, .description = "Linting configuration" },
        .{ .name = "ignore", .field_type = .array, .description = "Patterns to ignore" },
        .{ .name = "include", .field_type = .array, .description = "Patterns to include" },
    },
    .allow_unknown_fields = false,
};

/// Schema for format configuration
const FORMAT_CONFIG_SCHEMA = Schema{
    .required_fields = &[_]FieldSpec{},
    .optional_fields = &[_]FieldSpec{
        .{ .name = "indent_size", .field_type = .number, .description = "Number of spaces per indent" },
        .{ .name = "indent_style", .field_type = .@"enum", .enum_values = &[_][]const u8{ "space", "tab" }, .description = "Indentation style" },
        .{ .name = "line_width", .field_type = .number, .description = "Maximum line width" },
        .{ .name = "trailing_comma", .field_type = .boolean, .description = "Add trailing commas" },
        .{ .name = "sort_keys", .field_type = .boolean, .description = "Sort object keys" },
        .{ .name = "quote_style", .field_type = .@"enum", .enum_values = &[_][]const u8{ "single", "double", "preserve" }, .description = "Quote style for strings" },
    },
    .allow_unknown_fields = false,
};

/// Schema for lint configuration
const LINT_CONFIG_SCHEMA = Schema{
    .required_fields = &[_]FieldSpec{},
    .optional_fields = &[_]FieldSpec{
        .{ .name = "rules", .field_type = .object, .description = "Linting rules configuration" },
        .{ .name = "severity", .field_type = .@"enum", .enum_values = &[_][]const u8{ "error", "warning", "info", "off" }, .description = "Default severity level" },
    },
    .allow_unknown_fields = true, // Allow custom lint rules
};

// ============================================================================
// Tests
// ============================================================================

// TODO: Rewrite test for tagged union AST
// test "ZonValidator - validate build.zig.zon" {
//     const testing = std.testing;
//     const allocator = testing.allocator;
//
//     // Create a mock AST
//     const root = Node{
//         .rule_id = @intFromEnum(CommonRules.object),
//         .node_type = .list,
//         .text = "",
//         .start_position = 0,
//         .end_position = 100,
//         .children = &[_]Node{
//             Node{
//                 .rule_id = ZonNodeRule.field_assignment.toU16(),
//                 .node_type = .rule,
//                 .text = "",
//                 .start_position = 0,
//                 .end_position = 20,
//                 .children = &[_]Node{
//                     Node{
//                         .rule_id = ZonNodeRule.field_name.toU16(),
//                         .node_type = .terminal,
//                         .text = ".name",
//                         .start_position = 0,
//                         .end_position = 5,
//                         .children = &[_]Node{},
//                         .attributes = null,
//                         .parent = null,
//                     },
//                     Node{
//                         .rule_id = @intFromEnum(CommonRules.string_literal),
//                         .node_type = .terminal,
//                         .text = "\"my-package\"",
//                         .start_position = 8,
//                         .end_position = 20,
//                         .children = &[_]Node{},
//                         .attributes = null,
//                         .parent = null,
//                     },
//                 },
//                 .attributes = null,
//                 .parent = null,
//             },
//         },
//         .attributes = null,
//         .parent = null,
//     };
//
//     const ast = AST{
//         .root = root,
//         .allocator = allocator,
//         .owned_texts = &[_][]const u8{}, // No owned texts for test AST
//         .source = "",
//     };
//
//     var validator = ZonValidator.init(allocator);
//     defer validator.deinit();
//
//     try validator.validateBuildZon(ast);
//
//     const errors = validator.getErrors();
//
//     // Should have an error for missing 'version' field
//     try testing.expect(errors.len > 0);
//
//     var found_version_error = false;
//     for (errors) |err| {
//         if (std.mem.indexOf(u8, err.message, "version") != null) {
//             found_version_error = true;
//             break;
//         }
//     }
//     try testing.expect(found_version_error);
// }

// TODO: Rewrite test for tagged union AST
// test "ZonValidator - validate dependencies" {
//     const testing = std.testing;
//     const allocator = testing.allocator;
//
//     var validator = ZonValidator.init(allocator);
//     defer validator.deinit();
//
//     // Test URL validation
//     try validator.validateUrl("https://github.com/user/repo.git", "test-dep");
//     try testing.expect(validator.getErrors().len == 0);
//
//     validator.clearErrors();
//     try validator.validateUrl("not-a-url", "test-dep");
//     try testing.expect(validator.getErrors().len > 0);
// }

// TODO: Rewrite test for tagged union AST
// test "ZonValidator - field type validation" {
//     const testing = std.testing;
//     const allocator = testing.allocator;
//
//     var validator = ZonValidator.init(allocator);
//     defer validator.deinit();
//
//     const spec = FieldSpec{
//         .name = "test_field",
//         .field_type = .string,
//     };
//
//     const string_node = Node{
//         .rule_id = @intFromEnum(CommonRules.string_literal),
//         .node_type = .terminal,
//         .text = "\"value\"",
//         .start_position = 0,
//         .end_position = 7,
//         .children = &[_]Node{},
//         .attributes = null,
//         .parent = null,
//     };
//
//     try validator.validateFieldType(string_node, spec, "test_field");
//     try testing.expect(validator.getErrors().len == 0);
//
//     const number_node = Node{
//         .rule_id = @intFromEnum(CommonRules.number_literal),
//         .node_type = .terminal,
//         .text = "42",
//         .start_position = 0,
//         .end_position = 2,
//         .children = &[_]Node{},
//         .attributes = null,
//         .parent = null,
//     };
//
//     validator.clearErrors();
//     try validator.validateFieldType(number_node, spec, "test_field");
//     try testing.expect(validator.getErrors().len > 0); // Type mismatch
// }
