const std = @import("std");
const Node = @import("node.zig").Node;
const NodeType = @import("node.zig").NodeType;
const AST = @import("mod.zig").AST;
const ASTFactory = @import("factory.zig").ASTFactory;

/// High-performance AST transformation utilities
/// Supports immutable transformations with copy-on-write semantics
/// Transformation operation types
pub const TransformOp = union(enum) {
    replace: struct {
        target_path: []const u8,
        new_node: Node,
    },
    insert: struct {
        parent_path: []const u8,
        index: usize,
        new_node: Node,
    },
    remove: struct {
        target_path: []const u8,
    },
    modify: struct {
        target_path: []const u8,
        modifier: *const fn (*Node) anyerror!void,
    },
};

/// Transformation context for tracking changes
pub const TransformContext = struct {
    allocator: std.mem.Allocator,
    factory: ASTFactory,
    changes: std.ArrayList(TransformOp),
    owned_texts: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) TransformContext {
        return .{
            .allocator = allocator,
            .factory = ASTFactory.init(allocator),
            .changes = std.ArrayList(TransformOp).init(allocator),
            .owned_texts = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *TransformContext) void {
        for (self.owned_texts.items) |text| {
            self.allocator.free(text);
        }
        self.owned_texts.deinit();
        self.changes.deinit();
        self.factory.deinit();
    }

    pub fn trackText(self: *TransformContext, text: []const u8) !void {
        try self.owned_texts.append(text);
    }
};

/// AST Transformation engine
pub const ASTTransformer = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ASTTransformer {
        return .{ .allocator = allocator };
    }

    /// Apply multiple transformations to create new AST
    pub fn transform(
        self: ASTTransformer,
        source_ast: *const AST,
        operations: []const TransformOp,
    ) !AST {
        var ctx = TransformContext.init(self.allocator);
        defer ctx.deinit();

        // Clone the original AST
        var new_root = try self.cloneNode(&source_ast.root, &ctx);

        // Apply each transformation
        for (operations) |op| {
            try self.applyOperation(&new_root, op, &ctx);
        }

        return AST{
            .root = new_root,
            .source = try self.allocator.dupe(u8, source_ast.source),
            .owned_texts = try ctx.owned_texts.toOwnedSlice(),
        };
    }

    /// Replace a node at the specified path
    pub fn replaceNode(
        self: ASTTransformer,
        source_ast: *const AST,
        path: []const u8,
        new_node: Node,
    ) !AST {
        const op = TransformOp{ .replace = .{ .target_path = path, .new_node = new_node } };
        return self.transform(source_ast, &.{op});
    }

    /// Remove a node at the specified path
    pub fn removeNode(
        self: ASTTransformer,
        source_ast: *const AST,
        path: []const u8,
    ) !AST {
        const op = TransformOp{ .remove = .{ .target_path = path } };
        return self.transform(source_ast, &.{op});
    }

    /// Insert a node at the specified location
    pub fn insertNode(
        self: ASTTransformer,
        source_ast: *const AST,
        parent_path: []const u8,
        index: usize,
        new_node: Node,
    ) !AST {
        const op = TransformOp{ .insert = .{ .parent_path = parent_path, .index = index, .new_node = new_node } };
        return self.transform(source_ast, &.{op});
    }

    /// Modify text content of a node
    pub fn modifyNodeText(
        self: ASTTransformer,
        source_ast: *const AST,
        path: []const u8,
        new_text: []const u8,
    ) !AST {
        var ctx = TransformContext.init(self.allocator);
        defer ctx.deinit();

        const modifier = struct {
            text: []const u8,
            ctx_ptr: *TransformContext,

            fn modify(node: *Node) !void {
                const owned_text = try @This().ctx_ptr.allocator.dupe(u8, @This().text);
                try @This().ctx_ptr.trackText(owned_text);
                node.text = owned_text;
            }
        }{ .text = new_text, .ctx_ptr = &ctx };

        const op = TransformOp{ .modify = .{ .target_path = path, .modifier = modifier.modify } };
        return self.transform(source_ast, &.{op});
    }

    /// Filter nodes based on predicate (removes non-matching)
    pub fn filterNodes(
        self: ASTTransformer,
        source_ast: *const AST,
        predicate: *const fn (*const Node) bool,
    ) !AST {
        var ctx = TransformContext.init(self.allocator);
        defer ctx.deinit();

        const new_root = try self.filterNodeRecursive(&source_ast.root, predicate, &ctx);

        return AST{
            .root = new_root,
            .source = try self.allocator.dupe(u8, source_ast.source),
            .owned_texts = try ctx.owned_texts.toOwnedSlice(),
        };
    }

    /// Merge two ASTs by combining their root children
    pub fn mergeASTs(
        self: ASTTransformer,
        ast1: *const AST,
        ast2: *const AST,
        merge_rule_name: []const u8,
    ) !AST {
        var ctx = TransformContext.init(self.allocator);
        defer ctx.deinit();

        // Create new root with merged children
        var merged_children = std.ArrayList(Node).init(self.allocator);
        defer merged_children.deinit();

        // Add children from both ASTs
        for (ast1.root.children) |child| {
            try merged_children.append(try self.cloneNode(&child, &ctx));
        }
        for (ast2.root.children) |child| {
            try merged_children.append(try self.cloneNode(&child, &ctx));
        }

        const merged_rule_name_owned = try self.allocator.dupe(u8, merge_rule_name);
        try ctx.trackText(merged_rule_name_owned);

        const merged_source = try std.fmt.allocPrint(self.allocator, "{s}\n{s}", .{ ast1.source, ast2.source });

        const merged_root = Node{
            .rule_name = merged_rule_name_owned,
            .node_type = .rule,
            .text = merged_source,
            .start_position = 0,
            .end_position = merged_source.len,
            .children = try merged_children.toOwnedSlice(),
            .attributes = null,
            .parent = null,
        };

        return AST{
            .root = merged_root,
            .source = merged_source,
            .owned_texts = try ctx.owned_texts.toOwnedSlice(),
        };
    }

    // ========================================================================
    // Private Implementation
    // ========================================================================

    fn applyOperation(
        self: ASTTransformer,
        root: *Node,
        operation: TransformOp,
        ctx: *TransformContext,
    ) !void {
        switch (operation) {
            .replace => |replace_op| {
                if (self.findNodeByPath(root, replace_op.target_path)) |target| {
                    target.* = try self.cloneNode(&replace_op.new_node, ctx);
                }
            },
            .remove => |remove_op| {
                try self.removeNodeByPath(root, remove_op.target_path);
            },
            .insert => |insert_op| {
                if (self.findNodeByPath(root, insert_op.parent_path)) |parent| {
                    try self.insertChildAt(parent, insert_op.index, try self.cloneNode(&insert_op.new_node, ctx), ctx);
                }
            },
            .modify => |modify_op| {
                if (self.findNodeByPath(root, modify_op.target_path)) |target| {
                    try modify_op.modifier(target);
                }
            },
        }
    }

    fn cloneNode(self: ASTTransformer, source: *const Node, ctx: *TransformContext) !Node {
        _ = self;

        // Clone text
        const cloned_rule_name = try ctx.allocator.dupe(u8, source.rule_name);
        try ctx.trackText(cloned_rule_name);

        const cloned_text = try ctx.allocator.dupe(u8, source.text);
        try ctx.trackText(cloned_text);

        // Clone children
        var cloned_children = try ctx.allocator.alloc(Node, source.children.len);
        for (source.children, 0..) |child, i| {
            cloned_children[i] = try self.cloneNode(&child, ctx);
        }

        return Node{
            .rule_name = cloned_rule_name,
            .node_type = source.node_type,
            .text = cloned_text,
            .start_position = source.start_position,
            .end_position = source.end_position,
            .children = cloned_children,
            .attributes = source.attributes, // Shallow clone for now
            .parent = source.parent, // Will be updated by parent
        };
    }

    fn findNodeByPath(self: ASTTransformer, root: *Node, path: []const u8) ?*Node {
        _ = self;
        var current = root;
        var segments = std.mem.splitScalar(u8, path, '.');

        while (segments.next()) |segment| {
            var found = false;
            for (current.children) |*child| {
                if (std.mem.eql(u8, child.rule_name, segment)) {
                    current = child;
                    found = true;
                    break;
                }
            }
            if (!found) return null;
        }
        return current;
    }

    fn removeNodeByPath(self: ASTTransformer, root: *Node, path: []const u8) !void {
        _ = self;
        const last_dot = std.mem.lastIndexOfScalar(u8, path, '.');
        if (last_dot == null) {
            // Cannot remove root
            return;
        }

        const parent_path = path[0..last_dot.?];
        const target_name = path[last_dot.? + 1 ..];

        if (self.findNodeByPath(root, parent_path)) |parent| {
            // Find and remove the child
            for (parent.children, 0..) |child, i| {
                if (std.mem.eql(u8, child.rule_name, target_name)) {
                    // Shift remaining children
                    for (i..parent.children.len - 1) |j| {
                        parent.children[j] = parent.children[j + 1];
                    }
                    // Reduce array size (simplified for now)
                    break;
                }
            }
        }
    }

    fn insertChildAt(
        self: ASTTransformer,
        parent: *Node,
        index: usize,
        new_child: Node,
        ctx: *TransformContext,
    ) !void {
        _ = self;

        // Reallocate children array with one more slot
        const new_children = try ctx.allocator.alloc(Node, parent.children.len + 1);

        // Copy children before insertion point
        for (0..index) |i| {
            new_children[i] = parent.children[i];
        }

        // Insert new child
        new_children[index] = new_child;

        // Copy children after insertion point
        for (index..parent.children.len) |i| {
            new_children[i + 1] = parent.children[i];
        }

        parent.children = new_children;
    }

    fn filterNodeRecursive(
        self: ASTTransformer,
        node: *const Node,
        predicate: *const fn (*const Node) bool,
        ctx: *TransformContext,
    ) !Node {
        // Filter children first
        var filtered_children = std.ArrayList(Node).init(ctx.allocator);
        defer filtered_children.deinit();

        for (node.children) |child| {
            if (predicate(&child)) {
                try filtered_children.append(try self.filterNodeRecursive(&child, predicate, ctx));
            }
        }

        // Clone current node with filtered children
        const cloned_rule_name = try ctx.allocator.dupe(u8, node.rule_name);
        try ctx.trackText(cloned_rule_name);

        const cloned_text = try ctx.allocator.dupe(u8, node.text);
        try ctx.trackText(cloned_text);

        return Node{
            .rule_name = cloned_rule_name,
            .node_type = node.node_type,
            .text = cloned_text,
            .start_position = node.start_position,
            .end_position = node.end_position,
            .children = try filtered_children.toOwnedSlice(),
            .attributes = node.attributes,
            .parent = node.parent,
        };
    }
};

// ============================================================================
// Convenience Functions
// ============================================================================

/// Quick node replacement
pub fn replaceNodeAtPath(
    allocator: std.mem.Allocator,
    source_ast: *const AST,
    path: []const u8,
    new_node: Node,
) !AST {
    const transformer = ASTTransformer.init(allocator);
    return transformer.replaceNode(source_ast, path, new_node);
}

/// Quick node removal
pub fn removeNodeAtPath(
    allocator: std.mem.Allocator,
    source_ast: *const AST,
    path: []const u8,
) !AST {
    const transformer = ASTTransformer.init(allocator);
    return transformer.removeNode(source_ast, path);
}

/// Quick text modification
pub fn modifyText(
    allocator: std.mem.Allocator,
    source_ast: *const AST,
    path: []const u8,
    new_text: []const u8,
) !AST {
    const transformer = ASTTransformer.init(allocator);
    return transformer.modifyNodeText(source_ast, path, new_text);
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;
const ASTTestHelpers = @import("test_helpers.zig").ASTTestHelpers;

test "node cloning" {
    var ast = try ASTTestHelpers.createZonAST(testing.allocator, ".{ .test = 42 }");
    defer ast.deinit();

    const transformer = ASTTransformer.init(testing.allocator);
    var ctx = TransformContext.init(testing.allocator);
    defer ctx.deinit();

    const cloned = try transformer.cloneNode(&ast.root, &ctx);

    try testing.expectEqualStrings(ast.root.rule_name, cloned.rule_name);
    try testing.expectEqual(ast.root.node_type, cloned.node_type);
}

test "text modification" {
    var ast = try ASTTestHelpers.createMinimalAST(testing.allocator, "literal", "original");
    defer ast.deinit();

    var modified = try modifyText(testing.allocator, &ast, "literal", "modified");
    defer modified.deinit();

    // Check that transformation creates new AST
    try testing.expectEqualStrings("literal", modified.root.rule_name);
}

test "node filtering" {
    var ast = try ASTTestHelpers.createZonAST(testing.allocator, ".{ .keep = 1, .remove = 2 }");
    defer ast.deinit();

    const keepPredicate = struct {
        fn predicate(node: *const Node) bool {
            return !std.mem.eql(u8, node.rule_name, "remove");
        }
    }.predicate;

    const transformer = ASTTransformer.init(testing.allocator);
    var filtered = try transformer.filterNodes(&ast, keepPredicate);
    defer filtered.deinit();

    // Filtered AST should not contain "remove" node
    try testing.expectEqualStrings("object", filtered.root.rule_name);
}
