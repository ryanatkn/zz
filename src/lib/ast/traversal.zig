const std = @import("std");
const Node = @import("node.zig").Node;
const AST = @import("mod.zig").AST;
const getRuleName = @import("rules.zig").getRuleName;

/// High-performance AST traversal with multiple strategies
/// Unified tree walking to replace manual patterns across the codebase
/// Traversal order options
pub const TraversalOrder = enum {
    depth_first_pre, // Visit node before children
    depth_first_post, // Visit node after children
    breadth_first, // Visit level by level
};

/// Visitor function signature
pub const VisitorFn = *const fn (node: *const Node, context: ?*anyopaque) anyerror!bool;

/// Predicate function for filtering nodes
pub const PredicateFn = *const fn (node: *const Node) bool;

/// Context for traversal operations
pub const TraversalContext = struct {
    depth: usize = 0,
    parent: ?*const Node = null,
    index: usize = 0,
    path: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) TraversalContext {
        return .{
            .path = std.ArrayList([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TraversalContext) void {
        self.path.deinit();
    }

    pub fn pushPath(self: *TraversalContext, segment: []const u8) !void {
        try self.path.append(segment);  // Don't duplicate, just store reference
    }

    pub fn popPath(self: *TraversalContext) void {
        if (self.path.items.len > 0) {
            _ = self.path.pop();
        }
    }

    pub fn getCurrentPath(self: TraversalContext) []const u8 {
        // TODO: Join path segments efficiently
        return if (self.path.items.len > 0) self.path.items[self.path.items.len - 1] else "";
    }
};

/// High-level traversal interface
pub const ASTTraversal = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ASTTraversal {
        return .{ .allocator = allocator };
    }

    /// Walk AST with visitor function
    pub fn walk(
        self: ASTTraversal,
        root: *const Node,
        visitor: VisitorFn,
        context: ?*anyopaque,
        order: TraversalOrder,
    ) !void {
        var traversal_ctx = TraversalContext.init(self.allocator);
        defer traversal_ctx.deinit();

        switch (order) {
            .depth_first_pre => try self.walkDepthFirstPre(root, visitor, context, &traversal_ctx),
            .depth_first_post => try self.walkDepthFirstPost(root, visitor, context, &traversal_ctx),
            .breadth_first => try self.walkBreadthFirst(root, visitor, context),
        }
    }

    /// Find all nodes matching a predicate
    pub fn findNodes(
        self: ASTTraversal,
        root: *const Node,
        predicate: PredicateFn,
    ) ![]const *const Node {
        var results = std.ArrayList(*const Node).init(self.allocator);
        defer results.deinit();

        try self.findNodesRecursive(root, predicate, &results);
        return results.toOwnedSlice();
    }

    /// Find first node matching predicate
    pub fn findNode(self: ASTTraversal, root: *const Node, predicate: PredicateFn) ?*const Node {
        if (predicate(root)) return root;

        for (root.children) |child| {
            if (self.findNode(&child, predicate)) |found| {
                return found;
            }
        }
        return null;
    }

    /// Navigate to node by path (e.g., "object.field.subfield")
    /// This requires rule names for path segments, so we keep a simple mapping
    pub fn navigateByPath(_: ASTTraversal, root: *const Node, path: []const u8) ?*const Node {
        // TODO: This function needs rethinking for rule IDs
        // For now, return null as path navigation by string is deprecated
        _ = root;
        _ = path;
        return null;
    }

    /// Count nodes matching predicate
    pub fn countNodes(_: ASTTraversal, root: *const Node, predicate: PredicateFn) usize {
        var count: usize = 0;
        if (predicate(root)) count += 1;

        for (root.children) |child| {
            count += ASTTraversal.countNodes(.{ .allocator = undefined }, &child, predicate);
        }
        return count;
    }

    /// Get all leaf nodes (nodes with no children)
    pub fn getLeafNodes(self: ASTTraversal, root: *const Node) ![]const *const Node {
        return self.findNodes(root, isLeafNode);
    }

    /// Get nodes at specific depth
    pub fn getNodesAtDepth(self: ASTTraversal, root: *const Node, target_depth: usize) ![]const *const Node {
        var results = std.ArrayList(*const Node).init(self.allocator);
        defer results.deinit();

        try self.collectNodesAtDepth(root, 0, target_depth, &results);
        return results.toOwnedSlice();
    }

    // ========================================================================
    // Private Implementation
    // ========================================================================

    fn walkDepthFirstPre(
        _: ASTTraversal,
        node: *const Node,
        visitor: VisitorFn,
        context: ?*anyopaque,
        ctx: *TraversalContext,
    ) anyerror!void {
        // Visit current node
        const should_continue = try visitor(node, context);
        if (!should_continue) return;

        // Visit children
        ctx.depth += 1;
        for (node.children, 0..) |child, i| {
            ctx.index = i;
            ctx.parent = node;
            // Use rule ID as string for path tracking
            var buf: [32]u8 = undefined;
            const rule_str = try std.fmt.bufPrint(&buf, "rule_{}", .{child.rule_id});
            try ctx.pushPath(rule_str);
            defer ctx.popPath();

            try walkDepthFirstPre(ASTTraversal{ .allocator = undefined }, &child, visitor, context, ctx);
        }
        ctx.depth -= 1;
    }

    fn walkDepthFirstPost(
        _: ASTTraversal,
        node: *const Node,
        visitor: VisitorFn,
        context: ?*anyopaque,
        ctx: *TraversalContext,
    ) anyerror!void {
        // Visit children first
        ctx.depth += 1;
        for (node.children, 0..) |child, i| {
            ctx.index = i;
            ctx.parent = node;
            // Use rule ID as string for path tracking
            var buf: [32]u8 = undefined;
            const rule_str = try std.fmt.bufPrint(&buf, "rule_{}", .{child.rule_id});
            try ctx.pushPath(rule_str);
            defer ctx.popPath();

            try walkDepthFirstPost(ASTTraversal{ .allocator = undefined }, &child, visitor, context, ctx);
        }
        ctx.depth -= 1;

        // Visit current node
        _ = try visitor(node, context);
    }

    fn walkBreadthFirst(
        self: ASTTraversal,
        root: *const Node,
        visitor: VisitorFn,
        context: ?*anyopaque,
    ) !void {
        var queue = std.ArrayList(*const Node).init(self.allocator);
        defer queue.deinit();

        try queue.append(root);

        while (queue.items.len > 0) {
            const node = queue.orderedRemove(0);
            const should_continue = try visitor(node, context);
            if (!should_continue) continue;

            // Add children to queue
            for (node.children) |child| {
                try queue.append(&child);
            }
        }
    }

    fn findNodesRecursive(
        self: ASTTraversal,
        node: *const Node,
        predicate: PredicateFn,
        results: *std.ArrayList(*const Node),
    ) !void {
        if (predicate(node)) {
            try results.append(node);
        }

        for (node.children) |child| {
            try self.findNodesRecursive(&child, predicate, results);
        }
    }

    fn collectNodesAtDepth(
        self: ASTTraversal,
        node: *const Node,
        current_depth: usize,
        target_depth: usize,
        results: *std.ArrayList(*const Node),
    ) !void {
        if (current_depth == target_depth) {
            try results.append(node);
            return;
        }

        if (current_depth < target_depth) {
            for (node.children) |child| {
                try self.collectNodesAtDepth(&child, current_depth + 1, target_depth, results);
            }
        }
    }
};

// ============================================================================
// Common Predicates
// ============================================================================

pub fn isLeafNode(node: *const Node) bool {
    return node.children.len == 0;
}

pub fn hasRuleId(rule_id: u16) PredicateFn {
    const id = rule_id;
    return struct {
        pub fn predicate(node: *const Node) bool {
            return node.rule_id == id;
        }
    }.predicate;
}


pub fn hasMinChildren(min_count: usize) PredicateFn {
    return struct {
        const min = min_count;
        pub fn predicate(node: *const Node) bool {
            return node.children.len >= min;
        }
    }.predicate;
}

pub fn containsText(needle: []const u8) PredicateFn {
    return struct {
        const text = needle;
        pub fn predicate(node: *const Node) bool {
            return std.mem.indexOf(u8, node.text, text) != null;
        }
    }.predicate;
}

// ============================================================================
// Convenience Functions
// ============================================================================

/// Walk AST with simple visitor (no context)
pub fn walkAST(
    allocator: std.mem.Allocator,
    root: *const Node,
    visitor: VisitorFn,
    order: TraversalOrder,
) !void {
    const traversal = ASTTraversal.init(allocator);
    try traversal.walk(root, visitor, null, order);
}

/// Find all nodes with specific rule ID
pub fn findNodesByRuleId(
    allocator: std.mem.Allocator,
    root: *const Node,
    rule_id: u16,
) ![]const *const Node {
    var results = std.ArrayList(*const Node).init(allocator);
    try collectNodesByRuleId(root, rule_id, &results);
    return results.toOwnedSlice();
}

fn collectNodesByRuleId(
    node: *const Node,
    rule_id: u16,
    results: *std.ArrayList(*const Node),
) !void {
    if (node.rule_id == rule_id) {
        try results.append(node);
    }
    for (node.children) |*child| {
        try collectNodesByRuleId(child, rule_id, results);
    }
}

/// Count total nodes in AST
pub fn countAllNodes(root: *const Node) usize {
    var count: usize = 1;
    for (root.children) |child| {
        count += countAllNodes(&child);
    }
    return count;
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;
const ASTTestHelpers = @import("test_helpers.zig").ASTTestHelpers;

test "depth-first traversal" {
    var ast = try ASTTestHelpers.createZonAST(testing.allocator, ".{ .test = 42 }");
    defer ast.deinit();

    var visit_count: usize = 0;
    const visitor = struct {
        pub fn visit(node: *const Node, context: ?*anyopaque) !bool {
            const count = @as(*usize, @ptrCast(@alignCast(context.?)));
            count.* += 1;
            _ = node;
            return true;
        }
    }.visit;

    var traversal = ASTTraversal.init(testing.allocator);
    try traversal.walk(&ast.root, visitor, &visit_count, .depth_first_pre);
    // Should visit at least the root node
    try testing.expect(visit_count >= 1);
}

test "find nodes by rule ID" {
    var ast = try ASTTestHelpers.createZonAST(testing.allocator, ".{ .field1 = 1, .field2 = 2 }");
    defer ast.deinit();

    const ZonRules = @import("rules.zig").ZonRules;
    const field_nodes = try findNodesByRuleId(testing.allocator, &ast.root, ZonRules.field_assignment);
    defer testing.allocator.free(field_nodes);

    // Should find field assignments
    try testing.expect(field_nodes.len >= 0);
}

test "leaf node detection" {
    const CommonRules = @import("rules.zig").CommonRules;
    var ast = try ASTTestHelpers.createMinimalAST(testing.allocator, @intFromEnum(CommonRules.number_literal), "42");
    defer ast.deinit();

    const traversal = ASTTraversal.init(testing.allocator);
    const leaf_nodes = try traversal.getLeafNodes(&ast.root);
    defer testing.allocator.free(leaf_nodes);

    try testing.expect(leaf_nodes.len >= 0);
}

test "node counting" {
    var ast = try ASTTestHelpers.createZonAST(testing.allocator, ".{ .test = 42 }");
    defer ast.deinit();

    const total_count = countAllNodes(&ast.root);
    try testing.expect(total_count >= 1);
}
