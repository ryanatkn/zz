const std = @import("std");
const Node = @import("node.zig").Node;
const NodeType = @import("node.zig").NodeType;
const AST = @import("mod.zig").AST;
const Walker = @import("walker.zig").Walker;

/// Common AST manipulation and query utilities
/// These functions work with any AST regardless of the source language
pub const ASTUtils = struct {
    /// Find a node by following a dot-separated path
    /// Example: findNodeByPath(root, "object.dependencies.package")
    /// Returns the first matching node or null if not found
    pub fn findNodeByPath(root: *const Node, path: []const u8) ?*const Node {
        var current_node = root;
        var path_iter = std.mem.split(u8, path, ".");

        while (path_iter.next()) |segment| {
            var found = false;
            for (current_node.children) |*child| {
                // Check for direct rule name match
                if (std.mem.eql(u8, child.rule_name, segment)) {
                    current_node = child;
                    found = true;
                    break;
                }

                // For field assignments, check the field name
                if (std.mem.eql(u8, child.rule_name, "field_assignment") and child.children.len >= 2) {
                    const field_name_node = &child.children[0];
                    var field_name = field_name_node.text;

                    // Handle dot prefix in field names
                    if (field_name.len > 0 and field_name[0] == '.') {
                        field_name = field_name[1..];
                    }

                    if (std.mem.eql(u8, field_name, segment)) {
                        // Return the value node for field assignments
                        if (child.children.len >= 3) {
                            current_node = &child.children[2]; // value after equals
                        } else if (child.children.len >= 2) {
                            current_node = &child.children[1]; // value without equals
                        } else {
                            return null;
                        }
                        found = true;
                        break;
                    }
                }
            }

            if (!found) return null;
        }

        return current_node;
    }

    /// Collect all nodes matching a predicate function
    pub fn collectNodes(
        allocator: std.mem.Allocator,
        root: *const Node,
        predicate: *const fn (node: *const Node) bool,
    ) ![]const *const Node {
        var result = std.ArrayList(*const Node).init(allocator);
        defer result.deinit();

        try collectNodesRecursive(&result, root, predicate);
        return result.toOwnedSlice();
    }

    fn collectNodesRecursive(
        result: *std.ArrayList(*const Node),
        node: *const Node,
        predicate: *const fn (node: *const Node) bool,
    ) !void {
        if (predicate(node)) {
            try result.append(node);
        }

        for (node.children) |*child| {
            try collectNodesRecursive(result, child, predicate);
        }
    }

    /// Collect all nodes with a specific rule name
    pub fn collectNodesByRule(
        allocator: std.mem.Allocator,
        root: *const Node,
        rule_name: []const u8,
    ) ![]const *const Node {
        const Predicate = struct {
            target_rule: []const u8,

            fn matches(node: *const Node, self: *const @This()) bool {
                return std.mem.eql(u8, node.rule_name, self.target_rule);
            }
        };

        const predicate = Predicate{ .target_rule = rule_name };
        return collectNodes(allocator, root, struct {
            fn pred(node: *const Node) bool {
                return std.mem.eql(u8, node.rule_name, predicate.target_rule);
            }
        }.pred);
    }

    /// Transform an AST by applying a transformer function to each node
    pub fn transformAST(
        allocator: std.mem.Allocator,
        root: *const Node,
        transformer: *const fn (node: *const Node, allocator: std.mem.Allocator) anyerror!Node,
    ) !Node {
        // Transform children first (post-order traversal)
        var transformed_children = std.ArrayList(Node).init(allocator);
        defer transformed_children.deinit();

        for (root.children) |*child| {
            const transformed_child = try transformAST(allocator, child, transformer);
            try transformed_children.append(transformed_child);
        }

        // Create a new node with transformed children
        var new_node = root.*;
        new_node.children = try transformed_children.toOwnedSlice();

        // Apply the transformer to this node
        return try transformer(&new_node, allocator);
    }

    /// Deep clone an AST with a new allocator
    pub fn cloneAST(allocator: std.mem.Allocator, ast: *const AST) !AST {
        const cloned_root = try cloneNode(allocator, &ast.root);

        // Clone owned_texts array
        var cloned_texts = std.ArrayList([]const u8).init(allocator);
        defer cloned_texts.deinit();

        for (ast.owned_texts) |text| {
            const cloned_text = try allocator.dupe(u8, text);
            try cloned_texts.append(cloned_text);
        }

        const cloned_source = try allocator.dupe(u8, ast.source);

        return AST{
            .root = cloned_root,
            .allocator = allocator,
            .owned_texts = try cloned_texts.toOwnedSlice(),
            .source = cloned_source,
        };
    }

    /// Deep clone a single node
    pub fn cloneNode(allocator: std.mem.Allocator, node: *const Node) !Node {
        // Clone children recursively
        var cloned_children = std.ArrayList(Node).init(allocator);
        defer cloned_children.deinit();

        for (node.children) |*child| {
            const cloned_child = try cloneNode(allocator, child);
            try cloned_children.append(cloned_child);
        }

        // Clone string fields
        const cloned_rule_name = try allocator.dupe(u8, node.rule_name);
        const cloned_text = try allocator.dupe(u8, node.text);

        // Clone attributes if present
        var cloned_attributes: ?std.StringHashMap([]const u8) = null;
        if (node.attributes) |attrs| {
            cloned_attributes = std.StringHashMap([]const u8).init(allocator);
            var iter = attrs.iterator();
            while (iter.next()) |entry| {
                const cloned_key = try allocator.dupe(u8, entry.key_ptr.*);
                const cloned_value = try allocator.dupe(u8, entry.value_ptr.*);
                try cloned_attributes.?.put(cloned_key, cloned_value);
            }
        }

        return Node{
            .rule_name = cloned_rule_name,
            .node_type = node.node_type,
            .text = cloned_text,
            .start_position = node.start_position,
            .end_position = node.end_position,
            .children = try cloned_children.toOwnedSlice(),
            .attributes = cloned_attributes,
            .parent = null, // Parent will be set when this node is added to a tree
        };
    }

    /// Validate AST structure against a schema
    pub fn validateStructure(node: *const Node, schema: ASTSchema) ValidationResult {
        return validateNodeSchema(node, schema);
    }

    fn validateNodeSchema(node: *const Node, schema: ASTSchema) ValidationResult {
        // Check rule name
        if (schema.rule_name) |expected_rule| {
            if (!std.mem.eql(u8, node.rule_name, expected_rule)) {
                return ValidationResult{
                    .valid = false,
                    .error_message = "Rule name mismatch",
                };
            }
        }

        // Check node type
        if (schema.node_type) |expected_type| {
            if (node.node_type != expected_type) {
                return ValidationResult{
                    .valid = false,
                    .error_message = "Node type mismatch",
                };
            }
        }

        // Check children count
        if (schema.min_children) |min| {
            if (node.children.len < min) {
                return ValidationResult{
                    .valid = false,
                    .error_message = "Too few children",
                };
            }
        }

        if (schema.max_children) |max| {
            if (node.children.len > max) {
                return ValidationResult{
                    .valid = false,
                    .error_message = "Too many children",
                };
            }
        }

        // Validate children recursively if child schemas are provided
        if (schema.children_schemas) |child_schemas| {
            if (child_schemas.len != node.children.len) {
                return ValidationResult{
                    .valid = false,
                    .error_message = "Child count doesn't match schema",
                };
            }

            for (node.children, child_schemas) |*child, child_schema| {
                const child_result = validateNodeSchema(child, child_schema);
                if (!child_result.valid) {
                    return child_result;
                }
            }
        }

        return ValidationResult{ .valid = true, .error_message = null };
    }

    /// Get all field names from an object-like node
    pub fn extractFieldNames(
        allocator: std.mem.Allocator,
        object_node: *const Node,
    ) ![][]const u8 {
        var field_names = std.ArrayList([]const u8).init(allocator);
        defer field_names.deinit();

        for (object_node.children) |*child| {
            if (std.mem.eql(u8, child.rule_name, "field_assignment") and child.children.len >= 1) {
                const field_name_node = &child.children[0];
                var field_name = field_name_node.text;

                // Handle dot prefix and quoted identifiers
                if (field_name.len > 0 and field_name[0] == '.') {
                    field_name = field_name[1..];
                }

                // Handle @"..." quoted identifiers
                if (field_name.len >= 4 and
                    field_name[0] == '@' and
                    field_name[1] == '"' and
                    field_name[field_name.len - 1] == '"')
                {
                    field_name = field_name[2 .. field_name.len - 1];
                }

                const owned_name = try allocator.dupe(u8, field_name);
                try field_names.append(owned_name);
            }
        }

        return field_names.toOwnedSlice();
    }

    /// Get a field value by name from an object-like node
    pub fn getFieldValue(object_node: *const Node, field_name: []const u8) ?*const Node {
        for (object_node.children) |*child| {
            if (std.mem.eql(u8, child.rule_name, "field_assignment") and child.children.len >= 2) {
                const field_name_node = &child.children[0];
                var current_field_name = field_name_node.text;

                // Handle dot prefix
                if (current_field_name.len > 0 and current_field_name[0] == '.') {
                    current_field_name = current_field_name[1..];
                }

                // Handle quoted identifiers
                if (current_field_name.len >= 4 and
                    current_field_name[0] == '@' and
                    current_field_name[1] == '"' and
                    current_field_name[current_field_name.len - 1] == '"')
                {
                    current_field_name = current_field_name[2 .. current_field_name.len - 1];
                }

                if (std.mem.eql(u8, current_field_name, field_name)) {
                    // Return value node (skip equals token if present)
                    if (child.children.len >= 3) {
                        return &child.children[2]; // field = value
                    } else {
                        return &child.children[1]; // field value
                    }
                }
            }
        }

        return null;
    }

    /// Check if a node represents a specific type of literal
    pub fn isLiteralOfType(node: *const Node, literal_type: []const u8) bool {
        return node.node_type == .terminal and std.mem.eql(u8, node.rule_name, literal_type);
    }

    /// Extract literal value as string (removes quotes for strings)
    pub fn extractLiteralValue(node: *const Node) []const u8 {
        if (isLiteralOfType(node, "string_literal")) {
            const text = node.text;
            if (text.len >= 2 and text[0] == '"' and text[text.len - 1] == '"') {
                return text[1 .. text.len - 1];
            }
        }
        return node.text;
    }

    /// Calculate the depth of nesting in the AST
    pub fn calculateMaxNestingDepth(node: *const Node) usize {
        var max_depth: usize = 0;
        for (node.children) |*child| {
            const child_depth = 1 + calculateMaxNestingDepth(child);
            max_depth = @max(max_depth, child_depth);
        }
        return max_depth;
    }

    /// Get statistics about the AST
    pub fn getASTStatistics(node: *const Node) ASTStatistics {
        var stats = ASTStatistics{};
        collectStatistics(node, &stats);
        return stats;
    }

    fn collectStatistics(node: *const Node, stats: *ASTStatistics) void {
        stats.total_nodes += 1;

        switch (node.node_type) {
            .terminal => stats.terminal_nodes += 1,
            .rule => stats.rule_nodes += 1,
            .list => stats.list_nodes += 1,
            .optional => stats.optional_nodes += 1,
            .error_recovery => stats.error_nodes += 1,
        }

        if (node.children.len == 0) {
            stats.leaf_nodes += 1;
        }

        const depth = Walker.getDepth(node);
        stats.max_depth = @max(stats.max_depth, depth);

        for (node.children) |*child| {
            collectStatistics(child, stats);
        }
    }
};

/// Schema for validating AST structure
pub const ASTSchema = struct {
    rule_name: ?[]const u8 = null,
    node_type: ?NodeType = null,
    min_children: ?usize = null,
    max_children: ?usize = null,
    children_schemas: ?[]const ASTSchema = null,
};

/// Result of structure validation
pub const ValidationResult = struct {
    valid: bool,
    error_message: ?[]const u8 = null,
};

/// Statistics about AST structure
pub const ASTStatistics = struct {
    total_nodes: usize = 0,
    terminal_nodes: usize = 0,
    rule_nodes: usize = 0,
    list_nodes: usize = 0,
    optional_nodes: usize = 0,
    error_nodes: usize = 0,
    leaf_nodes: usize = 0,
    max_depth: usize = 0,

    pub fn format(
        self: ASTStatistics,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("ASTStatistics{{ total: {}, terminals: {}, rules: {}, lists: {}, leaves: {}, depth: {} }}", .{
            self.total_nodes,
            self.terminal_nodes,
            self.rule_nodes,
            self.list_nodes,
            self.leaf_nodes,
            self.max_depth,
        });
    }
};

// Convenience functions are directly accessible via the ASTUtils struct

// ============================================================================
// Common predicates for node collection
// ============================================================================

pub const Predicates = struct {
    pub fn isLiteralNode(node: *const Node) bool {
        return node.node_type == .terminal;
    }

    pub fn isObjectNode(node: *const Node) bool {
        return std.mem.eql(u8, node.rule_name, "object");
    }

    pub fn isArrayNode(node: *const Node) bool {
        return std.mem.eql(u8, node.rule_name, "array");
    }

    pub fn isFieldAssignmentNode(node: *const Node) bool {
        return std.mem.eql(u8, node.rule_name, "field_assignment");
    }

    pub fn isStringLiteralNode(node: *const Node) bool {
        return ASTUtils.isLiteralOfType(node, "string_literal");
    }

    pub fn isNumberLiteralNode(node: *const Node) bool {
        return ASTUtils.isLiteralOfType(node, "number_literal");
    }
};
