/// Generic AST Walker - Works with any AST via comptime duck typing
///
/// Efficient tree walking without recursion to avoid stack overflow.
/// Supports multiple traversal orders and filtering operations.
/// Uses comptime duck typing to work with any Node type that implements:
/// - .children() []NodeType
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Generic Walker factory that works with any Node type
pub fn Walker(comptime NodeType: type) type {
    return struct {
        /// Visit order
        pub const Order = enum {
            pre_order, // Parent before children (top-down)
            post_order, // Children before parent (bottom-up)
            level_order, // Breadth-first (level by level)
        };

        /// Walk context for tracking position
        const WalkContext = struct {
            node: *NodeType,
            depth: u32,
            index: u32, // Child index for post-order
            parent: ?*NodeType = null,
        };

        /// Walk result for early termination
        pub const WalkResult = enum {
            continue_walk,
            skip_children, // Skip children of current node
            stop_walk, // Stop entire walk
        };

        /// Visitor function signature
        pub const VisitorFn = fn (node: *NodeType, depth: u32, parent: ?*NodeType) WalkResult;

        /// Iterative walk with visitor pattern
        pub fn walk(
            allocator: Allocator,
            root: *NodeType,
            order: Order,
            visitor: VisitorFn,
        ) !void {
            var stack = std.ArrayList(WalkContext).init(allocator);
            defer stack.deinit();

            try stack.append(.{ .node = root, .depth = 0, .index = 0 });

            while (stack.items.len > 0) {
                switch (order) {
                    .pre_order => {
                        const ctx = stack.pop();
                        const result = visitor(ctx.node, ctx.depth, ctx.parent);

                        switch (result) {
                            .stop_walk => return,
                            .skip_children => continue,
                            .continue_walk => {},
                        }

                        // Add children in reverse order for correct traversal
                        const children = ctx.node.children();
                        var i = children.len;
                        while (i > 0) : (i -= 1) {
                            try stack.append(.{
                                .node = &children[i - 1],
                                .depth = ctx.depth + 1,
                                .index = 0,
                                .parent = ctx.node,
                            });
                        }
                    },
                    .post_order => {
                        var ctx = &stack.items[stack.items.len - 1];
                        const children = ctx.node.children();

                        // Process all children first
                        if (ctx.index < children.len) {
                            const child_idx = ctx.index;
                            ctx.index += 1;
                            try stack.append(.{
                                .node = &children[child_idx],
                                .depth = ctx.depth + 1,
                                .index = 0,
                                .parent = ctx.node,
                            });
                            continue;
                        }

                        // All children processed, visit node
                        const completed = stack.pop();
                        const result = visitor(completed.node, completed.depth, completed.parent);
                        if (result == .stop_walk) return;
                    },
                    .level_order => {
                        const ctx = stack.orderedRemove(0);
                        const result = visitor(ctx.node, ctx.depth, ctx.parent);

                        switch (result) {
                            .stop_walk => return,
                            .skip_children => continue,
                            .continue_walk => {},
                        }

                        // Add children to end of queue
                        const children = ctx.node.children();
                        for (children) |*child| {
                            try stack.append(.{
                                .node = child,
                                .depth = ctx.depth + 1,
                                .index = 0,
                                .parent = ctx.node,
                            });
                        }
                    },
                }
            }
        }

        /// Find first node matching predicate
        pub fn find(
            allocator: Allocator,
            root: *NodeType,
            predicate: fn (*NodeType) bool,
        ) !?*NodeType {
            var result: ?*NodeType = null;

            const FindVisitor = struct {
                pred: fn (*NodeType) bool,
                found: *?*NodeType,

                fn visit(self: @This(), node: *NodeType, depth: u32, parent: ?*NodeType) WalkResult {
                    _ = depth;
                    _ = parent;
                    if (self.pred(node)) {
                        self.found.* = node;
                        return .stop_walk;
                    }
                    return .continue_walk;
                }
            };

            const find_visitor = FindVisitor{ .pred = predicate, .found = &result };
            try walk(allocator, root, .pre_order, find_visitor.visit);
            return result;
        }

        /// Collect all nodes matching predicate
        pub fn collect(
            allocator: Allocator,
            root: *NodeType,
            predicate: fn (*NodeType) bool,
        ) !std.ArrayList(*NodeType) {
            var results = std.ArrayList(*NodeType).init(allocator);

            const CollectVisitor = struct {
                pred: fn (*NodeType) bool,
                list: *std.ArrayList(*NodeType),

                fn visit(self: @This(), node: *NodeType, depth: u32, parent: ?*NodeType) WalkResult {
                    _ = depth;
                    _ = parent;
                    if (self.pred(node)) {
                        self.list.append(node) catch unreachable; // TODO: proper error handling
                    }
                    return .continue_walk;
                }
            };

            const collect_visitor = CollectVisitor{ .pred = predicate, .list = &results };
            try walk(allocator, root, .pre_order, collect_visitor.visit);
            return results;
        }
    };
}

/// Convenience function - creates a Walker for given node type
pub fn walkAST(
    comptime NodeType: type,
    allocator: Allocator,
    root: *NodeType,
    order: Walker(NodeType).Order,
    visitor: Walker(NodeType).VisitorFn,
) !void {
    const WalkerType = Walker(NodeType);
    return WalkerType.walk(allocator, root, order, visitor);
}

/// Convenience function - finds first matching node
pub fn findInAST(
    comptime NodeType: type,
    allocator: Allocator,
    root: *NodeType,
    predicate: fn (*NodeType) bool,
) !?*NodeType {
    const WalkerType = Walker(NodeType);
    return WalkerType.find(allocator, root, predicate);
}

/// Convenience function - collects all matching nodes
pub fn collectInAST(
    comptime NodeType: type,
    allocator: Allocator,
    root: *NodeType,
    predicate: fn (*NodeType) bool,
) !std.ArrayList(*NodeType) {
    const WalkerType = Walker(NodeType);
    return WalkerType.collect(allocator, root, predicate);
}
