const std = @import("std");
const testing = std.testing;

const PathBuilder = @import("../path_builder.zig").PathBuilder;

test "path builder initialization" {
    const path_builder = PathBuilder.init(testing.allocator);
    _ = path_builder; // Just verify it initializes
    
    std.debug.print("✅ Path builder initialization test passed!\n", .{});
}

test "path builder buildPath functionality" {
    const path_builder = PathBuilder.init(testing.allocator);
    
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
    
    std.debug.print("✅ Path builder buildPath test passed!\n", .{});
}

test "path builder tree prefix functionality" {
    const path_builder = PathBuilder.init(testing.allocator);
    
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
    
    std.debug.print("✅ Path builder tree prefix test passed!\n", .{});
}

test "path builder basename functionality" {
    // Test basename extraction
    try testing.expectEqualStrings("file.txt", PathBuilder.basename("path/to/file.txt"));
    try testing.expectEqualStrings("file.txt", PathBuilder.basename("file.txt"));
    try testing.expectEqualStrings("dir", PathBuilder.basename("path/to/dir"));
    try testing.expectEqualStrings(".", PathBuilder.basename("."));
    
    std.debug.print("✅ Path builder basename test passed!\n", .{});
}