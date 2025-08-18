const std = @import("std");
const Node = @import("node.zig").Node;

/// Tree walker utilities for AST traversal
pub const Walker = struct {
    /// Walk the tree depth-first, pre-order
    pub fn walkPreOrder(node: *const Node, context: anytype, visitFn: *const fn (node: *const Node, ctx: @TypeOf(context)) void) void {
        visitFn(node, context);
        for (node.children) |*child| {
            walkPreOrder(child, context, visitFn);
        }
    }

    /// Walk the tree depth-first, post-order
    pub fn walkPostOrder(node: *const Node, context: anytype, visitFn: *const fn (node: *const Node, ctx: @TypeOf(context)) void) void {
        for (node.children) |*child| {
            walkPostOrder(child, context, visitFn);
        }
        visitFn(node, context);
    }

    /// Walk the tree breadth-first
    pub fn walkBreadthFirst(allocator: std.mem.Allocator, node: *const Node, context: anytype, visitFn: *const fn (node: *const Node, ctx: @TypeOf(context)) void) !void {
        var queue = std.ArrayList(*const Node).init(allocator);
        defer queue.deinit();

        try queue.append(node);

        while (queue.items.len > 0) {
            const current = queue.orderedRemove(0);
            visitFn(current, context);

            for (current.children) |*child| {
                try queue.append(child);
            }
        }
    }

    /// Walk only leaf nodes
    pub fn walkLeaves(node: *const Node, context: anytype, visitFn: *const fn (node: *const Node, ctx: @TypeOf(context)) void) void {
        if (node.isLeaf()) {
            visitFn(node, context);
        } else {
            for (node.children) |*child| {
                walkLeaves(child, context, visitFn);
            }
        }
    }

    /// Walk up the tree from a node to the root
    pub fn walkAncestors(node: *const Node, context: anytype, visitFn: *const fn (node: *const Node, ctx: @TypeOf(context)) void) void {
        var current = node.parent;
        while (current) |parent| {
            visitFn(parent, context);
            current = parent.parent;
        }
    }

    /// Get the path from root to a specific node
    pub fn getPath(allocator: std.mem.Allocator, node: *const Node) ![]const Node {
        var path = std.ArrayList(Node).init(allocator);
        defer path.deinit();

        var current: ?*const Node = node;
        while (current) |n| {
            try path.insert(0, n.*);
            current = n.parent;
        }

        return path.toOwnedSlice();
    }

    /// Get the depth of a node (distance from root)
    pub fn getDepth(node: *const Node) usize {
        var depth: usize = 0;
        var current = node.parent;
        while (current) |parent| {
            depth += 1;
            current = parent.parent;
        }
        return depth;
    }

    /// Get the maximum depth of the tree
    pub fn getMaxDepth(node: *const Node) usize {
        var max_depth: usize = 0;
        for (node.children) |*child| {
            const child_depth = 1 + getMaxDepth(child);
            max_depth = @max(max_depth, child_depth);
        }
        return max_depth;
    }

    /// Count total nodes in the tree
    pub fn countNodes(node: *const Node) usize {
        var count: usize = 1; // Count this node
        for (node.children) |*child| {
            count += countNodes(child);
        }
        return count;
    }

    /// Pretty print the tree structure
    pub fn printTree(node: *const Node, writer: anytype, indent: usize) !void {
        // Print indentation
        for (0..indent) |_| {
            try writer.print("  ");
        }

        // Print node info
        try writer.print("{s}: '{s}' ({}-{})\n", .{ node.rule_name, node.text, node.start_position, node.end_position });

        // Print children
        for (node.children) |*child| {
            try printTree(child, writer, indent + 1);
        }
    }
};
