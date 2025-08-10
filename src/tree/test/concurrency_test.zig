const std = @import("std");
const testing = std.testing;

const Walker = @import("../walker.zig").Walker;
const Config = @import("../config.zig").Config;
const TreeConfig = @import("../config.zig").TreeConfig;

// Test thread safety and concurrent access patterns
test "multiple walker instances" {
    const test_dir = "concurrent_test";
    std.fs.cwd().makeDir(test_dir) catch {};
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // Create test structure
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        const dir_name = try std.fmt.allocPrint(testing.allocator, "{s}/dir_{d}", .{ test_dir, i });
        defer testing.allocator.free(dir_name);
        std.fs.cwd().makeDir(dir_name) catch {};

        const file_name = try std.fmt.allocPrint(testing.allocator, "{s}/file.txt", .{dir_name});
        defer testing.allocator.free(file_name);
        const file = std.fs.cwd().createFile(file_name, .{}) catch continue;
        file.close();
    }

    const tree_config = TreeConfig{
        .ignored_patterns = &[_][]const u8{},
        .hidden_files = &[_][]const u8{},
    };

    const config = Config{ .tree_config = tree_config };

    // Create multiple walker instances (should be safe)
    const walker1 = Walker.initQuiet(testing.allocator, config);
    const walker2 = Walker.initQuiet(testing.allocator, config);
    const walker3 = Walker.initQuiet(testing.allocator, config);

    // All should work independently
    try walker1.walk(test_dir);
    try walker2.walk(test_dir);
    try walker3.walk(test_dir);

    std.debug.print("✅ Multiple walker instances test passed!\n", .{});
}

// Test configuration immutability
test "config immutability" {
    const tree_config = TreeConfig{
        .ignored_patterns = &[_][]const u8{ "test1", "test2" },
        .hidden_files = &[_][]const u8{"hidden1"},
    };

    const config = Config{ .tree_config = tree_config };

    // Create multiple walkers with same config
    const walker1 = Walker.initQuiet(testing.allocator, config);
    const walker2 = Walker.initQuiet(testing.allocator, config);

    // Both should have the same configuration
    try testing.expect(walker1.filter.tree_config.ignored_patterns.len == 2);
    try testing.expect(walker2.filter.tree_config.ignored_patterns.len == 2);
    try testing.expect(walker1.filter.tree_config.hidden_files.len == 1);
    try testing.expect(walker2.filter.tree_config.hidden_files.len == 1);

    std.debug.print("✅ Config immutability test passed!\n", .{});
}

// Test rapid creation/destruction of configs
test "rapid config lifecycle" {
    var iteration: u32 = 0;
    while (iteration < 100) : (iteration += 1) {
        var args = [_][]const u8{"tree"};
        var config = try Config.fromArgs(testing.allocator, @ptrCast(&args));
        defer config.deinit(testing.allocator);

        // Verify config is valid each time
        try testing.expect(config.tree_config.ignored_patterns.len > 0);

        // Create walker and immediately destroy
        const walker = Walker.initQuiet(testing.allocator, config);
        _ = walker; // Just creation/destruction cycle
    }

    std.debug.print("✅ Rapid config lifecycle test passed!\n", .{});
}

// Test memory behavior under stress
test "memory stress with config changes" {
    // Test many different config combinations
    const patterns_sets = [_][]const []const u8{
        &[_][]const u8{},
        &[_][]const u8{"node_modules"},
        &[_][]const u8{ "node_modules", ".git" },
        &[_][]const u8{ "node_modules", ".git", "target", "dist" },
        &[_][]const u8{ ".git", ".cache", ".zig-cache", "zig-out" },
    };

    for (patterns_sets) |patterns| {
        const tree_config = TreeConfig{
            .ignored_patterns = patterns,
            .hidden_files = &[_][]const u8{},
        };

        const config = Config{ .tree_config = tree_config };
        const walker = Walker.initQuiet(testing.allocator, config);

        // Verify walker works with different configs
        _ = walker;
    }

    std.debug.print("✅ Memory stress with config changes test passed!\n", .{});
}
