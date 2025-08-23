const std = @import("std");
const testing = std.testing;

// Import memory modules
const memory = @import("mod.zig");
const MemoryStrategy = memory.MemoryStrategy;
const MemoryContext = memory.MemoryContext;

// Test node type
const TestNode = struct {
    value: i32,
};

test "basic memory context creation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Just test creation and destruction
    var ctx = MemoryContext(TestNode).init(allocator, .arena_only);
    defer ctx.deinit();
    
    try testing.expect(ctx.strategy == .arena_only);
}

test "basic node allocation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var ctx = MemoryContext(TestNode).init(allocator, .arena_only);
    defer ctx.deinit();
    
    // Try to allocate a single node
    const node = try ctx.allocateNode();
    node.value = 42;
    
    try testing.expect(node.value == 42);
}

test "basic array allocation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var ctx = MemoryContext(TestNode).init(allocator, .arena_only);
    defer ctx.deinit();
    
    // Try to allocate an array
    const array = try ctx.allocateNodes(5);
    try testing.expect(array.len == 5);
    
    for (array, 0..) |*node, i| {
        node.value = @intCast(i);
    }
    
    try testing.expect(array[0].value == 0);
    try testing.expect(array[4].value == 4);
}

test "basic string allocation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var ctx = MemoryContext(TestNode).init(allocator, .arena_only);
    defer ctx.deinit();
    
    const text = try ctx.allocateAstText("hello");
    try testing.expectEqualStrings("hello", text);
}