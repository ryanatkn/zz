const std = @import("std");
const testing = std.testing;

const PathBuilder = @import("../path_builder.zig").PathBuilder;
const test_helpers = @import("../../test_helpers.zig");

test "path builder initialization" {
    var ctx = test_helpers.MockTestContext.init(testing.allocator);
    defer ctx.deinit();

    const path_builder = PathBuilder.init(testing.allocator, ctx.filesystem);
    _ = path_builder; // Just verify it initializes

    std.debug.print("✓ Path builder initialization test passed!\n", .{});
}

test "path builder buildPath functionality" {
    var ctx = test_helpers.MockTestContext.init(testing.allocator);
    defer ctx.deinit();

    const path_builder = PathBuilder.init(testing.allocator, ctx.filesystem);

    // Test building path with "." base
    const result1 = try path_builder.buildPath(".", "file.txt");
    defer testing.allocator.free(result1);
    try testing.expectEqualStrings("file.txt", result1);

    // Test building path with directory base
    const result2 = try path_builder.buildPath("src", "main.zig");
    defer testing.allocator.free(result2);
    try testing.expectEqualStrings("src/main.zig", result2);

    // Test building nested path
    const result3 = try path_builder.buildPath("src/tree", "config.zig");
    defer testing.allocator.free(result3);
    try testing.expectEqualStrings("src/tree/config.zig", result3);

    std.debug.print("✓ Path builder buildPath test passed!\n", .{});
}

test "path builder tree prefix functionality" {
    var ctx = test_helpers.MockTestContext.init(testing.allocator);
    defer ctx.deinit();

    const path_builder = PathBuilder.init(testing.allocator, ctx.filesystem);

    // Test building prefix for last entry
    const result1 = try path_builder.buildTreePrefix("", true);
    defer testing.allocator.free(result1);
    try testing.expectEqualStrings("    ", result1);

    // Test building prefix for non-last entry
    const result2 = try path_builder.buildTreePrefix("", false);
    defer testing.allocator.free(result2);
    try testing.expectEqualStrings("│   ", result2);

    // Test building nested prefix
    const result3 = try path_builder.buildTreePrefix("│   ", true);
    defer testing.allocator.free(result3);
    try testing.expectEqualStrings("│       ", result3);

    std.debug.print("✓ Path builder tree prefix test passed!\n", .{});
}

test "path builder basename functionality" {
    const allocator = testing.allocator;
    var ctx = test_helpers.MockTestContext.init(allocator);
    defer ctx.deinit();

    const builder = PathBuilder.init(allocator, ctx.filesystem);

    // Test basename extraction
    try testing.expectEqualStrings("file.txt", builder.basename("path/to/file.txt"));
    try testing.expectEqualStrings("file.txt", builder.basename("file.txt"));
    try testing.expectEqualStrings("dir", builder.basename("path/to/dir"));
    try testing.expectEqualStrings(".", builder.basename("."));

    std.debug.print("✓ Path builder basename test passed!\n", .{});
}
