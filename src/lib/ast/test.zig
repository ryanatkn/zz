const std = @import("std");
const testing = std.testing;
const Node = @import("node.zig").Node;
const NodeType = @import("node.zig").NodeType;
const createNode = @import("node.zig").createNode;
const createLeafNode = @import("node.zig").createLeafNode;
const Visitor = @import("visitor.zig").Visitor;
const Walker = @import("walker.zig").Walker;
const CommonRules = @import("rules.zig").CommonRules;

test "create leaf node" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const leaf = try createLeafNode(allocator, @intFromEnum(CommonRules.number_literal), "42", 0, 2);
    defer leaf.deinit(allocator);

    // TODO: Replace with rule_id check when TestRules are available
    try testing.expect(leaf.rule_id != 0); // Basic sanity check
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

    const child1 = try createLeafNode(allocator, @intFromEnum(CommonRules.number_literal), "1", 0, 1);
    const child2 = try createLeafNode(allocator, 100, "+", 1, 2); // Use an arbitrary ID for plus
    const child3 = try createLeafNode(allocator, @intFromEnum(CommonRules.number_literal), "2", 2, 3);

    const children = [_]Node{ child1, child2, child3 };
    const parent = try createNode(
        allocator,
        102, // Use arbitrary ID for expression
        .rule,
        "1+2",
        0,
        3,
        @constCast(&children),
    );
    defer parent.deinit(allocator);

    // TODO: Replace with rule_id check when TestRules are available
    try testing.expect(parent.rule_id != 0); // Basic sanity check
    try testing.expectEqualStrings("1+2", parent.text);
    try testing.expectEqual(@as(usize, 3), parent.children.len);
    try testing.expect(!parent.isLeaf());

    // Test child access
    const first = parent.firstChild().?;
    // TODO: Replace with rule_id check when TestRules are available
    try testing.expect(first.rule_id != 0); // Basic sanity check
    try testing.expectEqualStrings("1", first.text);

    const last = parent.lastChild().?;
    // TODO: Replace with rule_id check when TestRules are available
    try testing.expect(last.rule_id != 0); // Basic sanity check
    try testing.expectEqualStrings("2", last.text);
}

test "find child by rule name" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const child1 = try createLeafNode(allocator, @intFromEnum(CommonRules.number_literal), "42", 0, 2);
    const child2 = try createLeafNode(allocator, 101, "+", 2, 3); // Use arbitrary ID for operator
    const child3 = try createLeafNode(allocator, @intFromEnum(CommonRules.number_literal), "7", 3, 4);

    const children = [_]Node{ child1, child2, child3 };
    const parent = try createNode(
        allocator,
        103, // Use arbitrary ID for expression
        .rule,
        "42+7",
        0,
        4,
        @constCast(&children),
    );
    defer parent.deinit(allocator);

    const found_operator = parent.findChild(101); // Use the same ID we used for operator
    try testing.expect(found_operator != null);
    try testing.expectEqualStrings("+", found_operator.?.text);

    const not_found = parent.findChild(999); // Use non-existent ID
    try testing.expect(not_found == null);
}

test "visitor pattern" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const leaf1 = try createLeafNode(allocator, @intFromEnum(CommonRules.number_literal), "1", 0, 1);
    const leaf2 = try createLeafNode(allocator, @intFromEnum(CommonRules.number_literal), "2", 2, 3);
    const children = [_]Node{ leaf1, leaf2 };
    const root = try createNode(
        allocator,
        104, // Use arbitrary ID for expression
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

    const leaf1 = try createLeafNode(allocator, @intFromEnum(CommonRules.number_literal), "1", 0, 1);
    const leaf2 = try createLeafNode(allocator, @intFromEnum(CommonRules.number_literal), "2", 2, 3);
    const children = [_]Node{ leaf1, leaf2 };
    const root = try createNode(
        allocator,
        104, // Use arbitrary ID for expression
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

    const leaf1 = try createLeafNode(allocator, @intFromEnum(CommonRules.number_literal), "1", 0, 1);
    const leaf2 = try createLeafNode(allocator, @intFromEnum(CommonRules.number_literal), "2", 2, 3);

    const children = [_]Node{ leaf1, leaf2 };
    var root = try createNode(
        allocator,
        105, // Use arbitrary ID for expression
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

test {
    _ = @import("test_helpers.zig");
    _ = @import("traversal.zig");
    _ = @import("builder.zig");
    _ = @import("serialization.zig");
    _ = @import("rules.zig");
    _ = @import("query.zig");
    _ = @import("transformation.zig");
}
