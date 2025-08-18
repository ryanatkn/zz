const std = @import("std");
const testing = std.testing;
const Node = @import("node.zig").Node;
const NodeType = @import("node.zig").NodeType;
const createNode = @import("node.zig").createNode;
const createLeafNode = @import("node.zig").createLeafNode;
const Visitor = @import("visitor.zig").Visitor;
const Walker = @import("walker.zig").Walker;

test "create leaf node" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const leaf = try createLeafNode(allocator, "number", "42", 0, 2);
    defer leaf.deinit(allocator);

    try testing.expectEqualStrings("number", leaf.rule_name);
    try testing.expectEqualStrings("42", leaf.text);
    try testing.expectEqual(@as(usize, 0), leaf.start_position);
    try testing.expectEqual(@as(usize, 2), leaf.end_position);
    try testing.expectEqual(@as(usize, 0), leaf.children.len);
    try testing.expect(leaf.isLeaf());
    try testing.expectEqual(@as(usize, 2), leaf.length());
}

test "create node with children" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const child1 = try createLeafNode(allocator, "number", "1", 0, 1);
    const child2 = try createLeafNode(allocator, "plus", "+", 1, 2);
    const child3 = try createLeafNode(allocator, "number", "2", 2, 3);

    const children = [_]Node{ child1, child2, child3 };
    const parent = try createNode(
        allocator,
        "expression",
        .rule,
        "1+2",
        0,
        3,
        @constCast(&children),
    );
    defer parent.deinit(allocator);

    try testing.expectEqualStrings("expression", parent.rule_name);
    try testing.expectEqualStrings("1+2", parent.text);
    try testing.expectEqual(@as(usize, 3), parent.children.len);
    try testing.expect(!parent.isLeaf());

    // Test child access
    const first = parent.firstChild().?;
    try testing.expectEqualStrings("number", first.rule_name);
    try testing.expectEqualStrings("1", first.text);

    const last = parent.lastChild().?;
    try testing.expectEqualStrings("number", last.rule_name);
    try testing.expectEqualStrings("2", last.text);
}

test "find child by rule name" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const child1 = try createLeafNode(allocator, "number", "42", 0, 2);
    const child2 = try createLeafNode(allocator, "operator", "+", 2, 3);
    const child3 = try createLeafNode(allocator, "number", "7", 3, 4);

    const children = [_]Node{ child1, child2, child3 };
    const parent = try createNode(
        allocator,
        "expression",
        .rule,
        "42+7",
        0,
        4,
        @constCast(&children),
    );
    defer parent.deinit(allocator);

    const found_operator = parent.findChild("operator");
    try testing.expect(found_operator != null);
    try testing.expectEqualStrings("+", found_operator.?.text);

    const not_found = parent.findChild("unknown");
    try testing.expect(not_found == null);
}

test "visitor pattern" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const leaf1 = try createLeafNode(allocator, "number", "1", 0, 1);
    const leaf2 = try createLeafNode(allocator, "number", "2", 2, 3);
    const children = [_]Node{ leaf1, leaf2 };
    const root = try createNode(
        allocator,
        "expression",
        .rule,
        "1+2",
        0,
        3,
        @constCast(&children),
    );
    defer root.deinit(allocator);

    var visit_count: usize = 0;

    const Context = struct {
        count: *usize,

        fn visit(n: *const Node, ctx: *anyopaque) bool {
            _ = n;
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.count.* += 1;
            return true;
        }
    };

    var context = Context{ .count = &visit_count };
    const visitor = Visitor.init(Context.visit, null, &context);
    visitor.visit(&root);

    try testing.expectEqual(@as(usize, 3), visit_count); // root + 2 children
}

test "walker utilities" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const leaf1 = try createLeafNode(allocator, "number", "1", 0, 1);
    const leaf2 = try createLeafNode(allocator, "number", "2", 2, 3);
    const children = [_]Node{ leaf1, leaf2 };
    const root = try createNode(
        allocator,
        "expression",
        .rule,
        "1+2",
        0,
        3,
        @constCast(&children),
    );
    defer root.deinit(allocator);

    // Test node counting
    try testing.expectEqual(@as(usize, 3), Walker.countNodes(&root));

    // Test max depth
    try testing.expectEqual(@as(usize, 1), Walker.getMaxDepth(&root));

    // Test leaf walking
    var leaf_count: usize = 0;
    Walker.walkLeaves(&root, &leaf_count, struct {
        fn visit(node: *const Node, count: *usize) void {
            _ = node;
            count.* += 1;
        }
    }.visit);
    try testing.expectEqual(@as(usize, 2), leaf_count);
}

test "parent references" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const leaf1 = try createLeafNode(allocator, "number", "1", 0, 1);
    const leaf2 = try createLeafNode(allocator, "number", "2", 2, 3);

    const children = [_]Node{ leaf1, leaf2 };
    var root = try createNode(
        allocator,
        "expression",
        .rule,
        "1+2",
        0,
        3,
        @constCast(&children),
    );
    defer root.deinit(allocator);

    // Set parent references
    root.setParentReferences();

    // Check that children have parent reference
    try testing.expect(root.children[0].parent != null);
    try testing.expect(root.children[1].parent != null);

    // Test depth calculation
    try testing.expectEqual(@as(usize, 0), Walker.getDepth(&root));
    try testing.expectEqual(@as(usize, 1), Walker.getDepth(&root.children[0]));
}
