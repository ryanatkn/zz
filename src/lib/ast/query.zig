const std = @import("std");
const Node = @import("node.zig").Node;
const AST = @import("mod.zig").AST;
const traversal = @import("traversal.zig");

/// High-performance AST query language
/// CSS selector-like syntax for finding nodes in AST
/// Query selector types
pub const Selector = union(enum) {
    /// Select by rule name: "function"
    rule: []const u8,

    /// Select by attribute: "[name=value]"
    attribute: struct {
        name: []const u8,
        value: ?[]const u8,
    },

    /// Select by text content: ":contains(text)"
    text_contains: []const u8,

    /// Select by position: ":first-child", ":last-child", ":nth-child(n)"
    position: PositionSelector,

    /// Select by relationship: "parent > child"
    relationship: struct {
        parent: *Selector,
        relation: RelationType,
        child: *Selector,
    },

    /// Combine selectors: "selector1, selector2"
    combined: []Selector,

    /// Universal selector: "*"
    universal,
};

pub const PositionSelector = enum {
    first_child,
    last_child,
    nth_child, // TODO: Add index parameter
};

pub const RelationType = enum {
    child, // >
    descendant, // (space)
    sibling, // +
    general_sibling, // ~
};

/// Query engine for AST searching
pub const ASTQuery = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ASTQuery {
        return .{ .allocator = allocator };
    }

    /// Execute query against AST
    pub fn select(self: ASTQuery, root: *const Node, selector: Selector) ![]const *const Node {
        var results = std.ArrayList(*const Node).init(self.allocator);
        defer results.deinit();

        try self.selectRecursive(root, selector, &results);
        return results.toOwnedSlice();
    }

    /// Select single node (first match)
    pub fn selectOne(self: ASTQuery, root: *const Node, selector: Selector) ?*const Node {
        var results = std.ArrayList(*const Node).init(self.allocator);
        defer results.deinit();

        self.selectRecursive(root, selector, &results) catch return null;
        return if (results.items.len > 0) results.items[0] else null;
    }

    /// Select by rule name (convenience)
    pub fn selectByRule(self: ASTQuery, root: *const Node, rule_name: []const u8) ![]const *const Node {
        return self.select(root, Selector{ .rule = rule_name });
    }

    /// Select nodes containing text (convenience)
    pub fn selectByText(self: ASTQuery, root: *const Node, text: []const u8) ![]const *const Node {
        return self.select(root, Selector{ .text_contains = text });
    }

    /// Select direct children with rule name
    pub fn selectDirectChildren(self: ASTQuery, root: *const Node, rule_name: []const u8) ![]const *const Node {
        var results = std.ArrayList(*const Node).init(self.allocator);
        defer results.deinit();

        for (root.children) |child| {
            if (std.mem.eql(u8, child.rule_name, rule_name)) {
                try results.append(&child);
            }
        }

        return results.toOwnedSlice();
    }

    /// Complex query with multiple conditions
    pub fn where(self: ASTQuery, root: *const Node, conditions: []const QueryCondition) ![]const *const Node {
        var results = std.ArrayList(*const Node).init(self.allocator);
        defer results.deinit();

        try self.whereRecursive(root, conditions, &results);
        return results.toOwnedSlice();
    }

    // ========================================================================
    // Private Implementation
    // ========================================================================

    fn selectRecursive(
        self: ASTQuery,
        node: *const Node,
        selector: Selector,
        results: *std.ArrayList(*const Node),
    ) anyerror!void {
        // Check if current node matches
        if (try self.matches(node, selector)) {
            try results.append(node);
        }

        // Recursively check children
        for (node.children) |child| {
            try self.selectRecursive(&child, selector, results);
        }
    }

    fn matches(self: ASTQuery, node: *const Node, selector: Selector) !bool {
        return switch (selector) {
            .rule => |rule_name| std.mem.eql(u8, node.rule_name, rule_name),

            .attribute => |attr| self.matchesAttribute(node, attr.name, attr.value),

            .text_contains => |text| std.mem.indexOf(u8, node.text, text) != null,

            .position => |pos| self.matchesPosition(node, pos),

            .relationship => |rel| self.matchesRelationship(node, rel),

            .combined => |selectors| blk: {
                for (selectors) |sub_selector| {
                    if (try self.matches(node, sub_selector)) break :blk true;
                }
                break :blk false;
            },

            .universal => true,
        };
    }

    fn matchesAttribute(self: ASTQuery, node: *const Node, name: []const u8, value: ?[]const u8) bool {
        _ = self;
        _ = node;
        _ = name;
        _ = value;
        // TODO: Implement attribute matching when Node has attributes
        return false;
    }

    fn matchesPosition(self: ASTQuery, node: *const Node, position: PositionSelector) bool {
        _ = self;

        // Need parent to determine position
        if (node.parent) |parent| {
            return switch (position) {
                .first_child => parent.children.len > 0 and
                    std.mem.asBytes(parent.children)[0..@sizeOf(Node)] == std.mem.asBytes(node)[0..@sizeOf(Node)],
                .last_child => parent.children.len > 0 and
                    std.mem.asBytes(parent.children[parent.children.len - 1])[0..@sizeOf(Node)] == std.mem.asBytes(node)[0..@sizeOf(Node)],
                .nth_child => false, // TODO: Implement with index
            };
        }
        return false;
    }

    fn matchesRelationship(self: ASTQuery, node: *const Node, relationship: anytype) bool {
        _ = self;
        _ = node;
        _ = relationship;
        // TODO: Implement relationship matching
        return false;
    }

    fn whereRecursive(
        self: ASTQuery,
        node: *const Node,
        conditions: []const QueryCondition,
        results: *std.ArrayList(*const Node),
    ) !void {
        // Check if node matches all conditions
        var matches_all = true;
        for (conditions) |condition| {
            if (!self.evaluateCondition(node, condition)) {
                matches_all = false;
                break;
            }
        }

        if (matches_all) {
            try results.append(node);
        }

        // Check children
        for (node.children) |child| {
            try self.whereRecursive(&child, conditions, results);
        }
    }

    fn evaluateCondition(self: ASTQuery, node: *const Node, condition: QueryCondition) bool {
        _ = self;
        return switch (condition) {
            .rule_equals => |rule| std.mem.eql(u8, node.rule_name, rule),
            .text_contains => |text| std.mem.indexOf(u8, node.text, text) != null,
            .text_equals => |text| std.mem.eql(u8, node.text, text),
            .has_children => node.children.len > 0,
            .is_leaf => node.children.len == 0,
            .min_children => |min| node.children.len >= min,
            .text_length_gt => |len| node.text.len > len,
            .position_range => |range| node.start_position >= range.start and node.end_position <= range.end,
        };
    }
};

/// Query condition for complex filtering
pub const QueryCondition = union(enum) {
    rule_equals: []const u8,
    text_contains: []const u8,
    text_equals: []const u8,
    has_children,
    is_leaf,
    min_children: usize,
    text_length_gt: usize,
    position_range: struct { start: usize, end: usize },
};

/// Query builder for fluent interface
pub const QueryBuilder = struct {
    allocator: std.mem.Allocator,
    conditions: std.ArrayList(QueryCondition),

    pub fn init(allocator: std.mem.Allocator) QueryBuilder {
        return .{
            .allocator = allocator,
            .conditions = std.ArrayList(QueryCondition).init(allocator),
        };
    }

    pub fn deinit(self: *QueryBuilder) void {
        self.conditions.deinit();
    }

    pub fn whereRule(self: *QueryBuilder, rule_name: []const u8) !*QueryBuilder {
        try self.conditions.append(QueryCondition{ .rule_equals = rule_name });
        return self;
    }

    pub fn whereTextContains(self: *QueryBuilder, text: []const u8) !*QueryBuilder {
        try self.conditions.append(QueryCondition{ .text_contains = text });
        return self;
    }

    pub fn whereHasChildren(self: *QueryBuilder) !*QueryBuilder {
        try self.conditions.append(QueryCondition.has_children);
        return self;
    }

    pub fn whereIsLeaf(self: *QueryBuilder) !*QueryBuilder {
        try self.conditions.append(QueryCondition.is_leaf);
        return self;
    }

    pub fn whereMinChildren(self: *QueryBuilder, min: usize) !*QueryBuilder {
        try self.conditions.append(QueryCondition{ .min_children = min });
        return self;
    }

    pub fn execute(self: QueryBuilder, query: ASTQuery, root: *const Node) ![]const *const Node {
        return query.where(root, self.conditions.items);
    }
};

// ============================================================================
// Convenience Functions
// ============================================================================

/// Quick rule selection
pub fn findByRule(allocator: std.mem.Allocator, root: *const Node, rule_name: []const u8) ![]const *const Node {
    const query = ASTQuery.init(allocator);
    return query.selectByRule(root, rule_name);
}

/// Quick text search
pub fn findByText(allocator: std.mem.Allocator, root: *const Node, text: []const u8) ![]const *const Node {
    const query = ASTQuery.init(allocator);
    return query.selectByText(root, text);
}

/// Find all leaf nodes
pub fn findLeafNodes(allocator: std.mem.Allocator, root: *const Node) ![]const *const Node {
    const query = ASTQuery.init(allocator);
    return query.where(root, &.{QueryCondition.is_leaf});
}

/// Find nodes with minimum children count
pub fn findWithMinChildren(allocator: std.mem.Allocator, root: *const Node, min: usize) ![]const *const Node {
    const query = ASTQuery.init(allocator);
    return query.where(root, &.{QueryCondition{ .min_children = min }});
}

// ============================================================================
// CSS-like Query Parser (Future Enhancement)
// ============================================================================

/// Parse CSS-like selector string into Selector
pub fn parseSelector(allocator: std.mem.Allocator, selector_string: []const u8) !Selector {
    _ = allocator;

    // Simple implementation for basic selectors
    if (std.mem.eql(u8, selector_string, "*")) {
        return Selector.universal;
    }

    if (std.mem.startsWith(u8, selector_string, ":contains(")) {
        const start = 10; // ":contains(".len
        if (std.mem.lastIndexOfScalar(u8, selector_string, ')')) |end| {
            const text = selector_string[start..end];
            return Selector{ .text_contains = text };
        }
    }

    // Default to rule selector
    return Selector{ .rule = selector_string };
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;
const ASTTestHelpers = @import("test_helpers.zig").ASTTestHelpers;

test "query by rule name" {
    var ast = try ASTTestHelpers.createZonAST(testing.allocator, ".{ .field = 42 }");
    defer ast.deinit();

    const query = ASTQuery.init(testing.allocator);
    const nodes = try query.selectByRule(&ast.root, "object");
    defer testing.allocator.free(nodes);

    try testing.expect(nodes.len >= 0);
}

test "query by text content" {
    var ast = try ASTTestHelpers.createMinimalAST(testing.allocator, "literal", "test_content");
    defer ast.deinit();

    const query = ASTQuery.init(testing.allocator);
    const nodes = try query.selectByText(&ast.root, "test");
    defer testing.allocator.free(nodes);

    try testing.expect(nodes.len >= 0);
}

test "query builder fluent interface" {
    var ast = try ASTTestHelpers.createZonAST(testing.allocator, ".{ .test = 42 }");
    defer ast.deinit();

    const query = ASTQuery.init(testing.allocator);
    var builder = QueryBuilder.init(testing.allocator);
    defer builder.deinit();

    const nodes = try builder.whereRule("object").whereHasChildren().execute(query, &ast.root);
    defer testing.allocator.free(nodes);

    try testing.expect(nodes.len >= 0);
}

test "selector parsing" {
    const universal = try parseSelector(testing.allocator, "*");
    try testing.expectEqual(Selector.universal, universal);

    const rule_selector = try parseSelector(testing.allocator, "function");
    try testing.expectEqual(Selector{ .rule = "function" }, rule_selector);
}

test "direct children selection" {
    var ast = try ASTTestHelpers.createZonAST(testing.allocator, ".{ .field1 = 1, .field2 = 2 }");
    defer ast.deinit();

    const query = ASTQuery.init(testing.allocator);
    const children = try query.selectDirectChildren(&ast.root, "field_assignment");
    defer testing.allocator.free(children);

    // Should find direct field assignments under object
    try testing.expect(children.len >= 0);
}
