const std = @import("std");
const testing = std.testing;

// Import ZON modules
const zon_mod = @import("../mod.zig");

// =============================================================================
// Edge Cases Tests
// =============================================================================

test "ZON edge cases - empty structures" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const test_cases = [_][]const u8{
        ".{}",
        ".{ }",
        ".{ .items = .{} }",
        ".{ .nested = .{ .empty = .{} } }",
    };

    for (test_cases) |input| {
        var ast = try zon_mod.parse(allocator, input);
        defer ast.deinit();

        try testing.expect(ast.root != null);
    }
}

test "ZON edge cases - special identifiers" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const test_cases = [_][]const u8{
        ".{ .@\"special name\" = 123 }",
        ".{ .@\"with spaces\" = \"value\" }",
        ".{ .@\"123numeric\" = true }",
    };

    for (test_cases) |input| {
        var ast = try zon_mod.parse(allocator, input);
        defer ast.deinit();

        try testing.expect(ast.root != null);
    }
}

test "ZON edge cases - trailing commas" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const test_cases = [_][]const u8{
        ".{ .a = 1, }",
        ".{ .a = 1, .b = 2, }",
        ".{ .nested = .{ .x = 3, }, }",
    };

    for (test_cases) |input| {
        var ast = try zon_mod.parse(allocator, input);
        defer ast.deinit();

        try testing.expect(ast.root != null);
    }
}

test "ZON edge cases - nested anonymous structs" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const deep_nested = ".{ .level1 = .{ .level2 = .{ .level3 = .{ .value = 42 } } } }";

    var ast = try zon_mod.parse(allocator, deep_nested);
    defer ast.deinit();

    try testing.expect(ast.root != null);
}

test "ZON edge cases - all number formats" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const number_formats =
        \\.{
        \\    .decimal = 123,
        \\    .hex = 0xFF,
        \\    .octal = 0o777,
        \\    .binary = 0b1010,
        \\    .float = 3.14,
        \\}
    ;

    var ast = try zon_mod.parse(allocator, number_formats);
    defer ast.deinit();

    try testing.expect(ast.root != null);
}
