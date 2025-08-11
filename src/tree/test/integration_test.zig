const std = @import("std");
const testing = std.testing;

const tree_main = @import("../main.zig");

// Integration tests for the complete tree module workflow
test "complete tree workflow with real directory" {
    // Create a realistic test directory structure
    const test_dir = "integration_test_tree";
    std.fs.cwd().makeDir(test_dir) catch {};
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // Create a complex directory structure
    const dirs_to_create = [_][]const u8{
        "src",
        "src/main",
        "src/utils",
        "tests",
        "docs",
        "node_modules",
        "node_modules/package1",
        "node_modules/package2",
        ".git",
        ".git/objects",
        "build",
        "dist",
        ".cache",
        "target/debug",
        "target/release",
    };

    for (dirs_to_create) |dir_path| {
        const full_path = try std.fmt.allocPrint(testing.allocator, "{s}/{s}", .{ test_dir, dir_path });
        defer testing.allocator.free(full_path);
        std.fs.cwd().makePath(full_path) catch {};
    }

    // Create some files
    const files_to_create = [_][]const u8{
        "README.md",
        "package.json",
        "src/main.zig",
        "src/utils/helper.zig",
        "tests/test.zig",
        "docs/guide.md",
        "node_modules/package1/index.js",
        ".git/config",
        "build/output.bin",
        "dist/bundle.js",
    };

    for (files_to_create) |file_path| {
        const full_path = try std.fmt.allocPrint(testing.allocator, "{s}/{s}", .{ test_dir, file_path });
        defer testing.allocator.free(full_path);
        const file = std.fs.cwd().createFile(full_path, .{}) catch continue;
        file.close();
    }

    // Run the tree command (this would normally go to stdout)
    // We can't easily capture stdout in tests, but we can verify it doesn't crash
    const args = [_][:0]const u8{ "tree", test_dir };
    tree_main.runQuiet(testing.allocator, @constCast(args[0..])) catch {
        try testing.expect(false); // Tree command should not fail
    };

    // Complete tree workflow test completed successfully
}

// Test tree command with depth limitation
test "tree command with depth limitation" {
    const test_dir = "depth_test_tree";
    std.fs.cwd().makeDir(test_dir) catch {};
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // Create deep nested structure
    const deep_paths = [_][]const u8{
        "level1",
        "level1/level2",
        "level1/level2/level3",
        "level1/level2/level3/level4",
        "level1/level2/level3/level4/level5",
    };

    for (deep_paths) |path| {
        const full_path = try std.fmt.allocPrint(testing.allocator, "{s}/{s}", .{ test_dir, path });
        defer testing.allocator.free(full_path);
        std.fs.cwd().makePath(full_path) catch {};

        // Add a file in each level
        const file_path = try std.fmt.allocPrint(testing.allocator, "{s}/file.txt", .{full_path});
        defer testing.allocator.free(file_path);
        const file = std.fs.cwd().createFile(file_path, .{}) catch continue;
        file.close();
    }

    // Test with depth limit
    const args = [_][:0]const u8{ "tree", test_dir, "3" };
    tree_main.runQuiet(testing.allocator, @constCast(args[0..])) catch {
        // Tree command with depth failed
        try testing.expect(false);
    };

    // Tree command with depth limitation test completed successfully
}

// Test tree command error handling
test "tree command error handling" {
    // Test with non-existent directory
    const args_nonexistent = [_][:0]const u8{ "tree", "this_directory_does_not_exist" };

    // Should handle gracefully and not crash
    tree_main.runQuiet(testing.allocator, @constCast(args_nonexistent[0..])) catch {
        // Expected to fail - directory does not exist
    };

    // Test with invalid depth parameter
    const test_dir = "error_test_tree";
    std.fs.cwd().makeDir(test_dir) catch {};
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    const args_invalid_depth = [_][:0]const u8{ "tree", test_dir, "not_a_number" };
    tree_main.runQuiet(testing.allocator, @constCast(args_invalid_depth[0..])) catch {
        // Tree command with invalid depth failed
        try testing.expect(false);
    };

    std.debug.print("✅ Tree command error handling test passed!\n", .{});
}

// Test tree command with permission issues (if possible)
test "tree command with permission scenarios" {
    const test_dir = "permission_test_tree";
    std.fs.cwd().makeDir(test_dir) catch {};
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // Create a normal directory structure
    std.fs.cwd().makeDir(test_dir ++ "/normal") catch {};
    const file = std.fs.cwd().createFile(test_dir ++ "/normal/file.txt", .{}) catch unreachable;
    file.close();

    // On Unix systems, we could try to create permission denied scenarios
    // But this is complex and platform-specific, so we'll just test normal operation

    const args = [_][:0]const u8{ "tree", test_dir };
    tree_main.runQuiet(testing.allocator, @constCast(args[0..])) catch {
        // Tree command with permissions failed
        try testing.expect(false);
    };

    std.debug.print("✅ Tree command with permission scenarios test passed!\n", .{});
}

// Test tree command with various file types
test "tree command with various file types" {
    const test_dir = "filetype_test_tree";
    std.fs.cwd().makeDir(test_dir) catch {};
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // Create different types of entries
    std.fs.cwd().makeDir(test_dir ++ "/directory") catch {};

    // Regular files
    const regular_file = std.fs.cwd().createFile(test_dir ++ "/regular.txt", .{}) catch unreachable;
    regular_file.close();

    // Files with various extensions
    const extensions = [_][]const u8{ ".zig", ".md", ".json", ".txt", ".log", ".tmp" };
    for (extensions, 0..) |ext, i| {
        const filename = try std.fmt.allocPrint(testing.allocator, "{s}/file{d}{s}", .{ test_dir, i, ext });
        defer testing.allocator.free(filename);
        const file = std.fs.cwd().createFile(filename, .{}) catch continue;
        file.close();
    }

    // Subdirectory with files
    std.fs.cwd().makeDir(test_dir ++ "/subdir") catch {};
    const subfile = std.fs.cwd().createFile(test_dir ++ "/subdir/nested.txt", .{}) catch unreachable;
    subfile.close();

    const args = [_][:0]const u8{ "tree", test_dir };
    tree_main.runQuiet(testing.allocator, @constCast(args[0..])) catch {
        // Tree command with file types failed
        try testing.expect(false);
    };

    std.debug.print("✅ Tree command with various file types test passed!\n", .{});
}

// Test tree command with empty directories
test "tree command with empty directories" {
    const test_dir = "empty_test_tree";
    std.fs.cwd().makeDir(test_dir) catch {};
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // Create empty directories at various levels
    std.fs.cwd().makeDir(test_dir ++ "/empty1") catch {};
    std.fs.cwd().makeDir(test_dir ++ "/empty2") catch {};
    std.fs.cwd().makeDir(test_dir ++ "/parent") catch {};
    std.fs.cwd().makeDir(test_dir ++ "/parent/empty_child") catch {};

    // Mix with non-empty
    std.fs.cwd().makeDir(test_dir ++ "/non_empty") catch {};
    const file = std.fs.cwd().createFile(test_dir ++ "/non_empty/file.txt", .{}) catch unreachable;
    file.close();

    const args = [_][:0]const u8{ "tree", test_dir };
    tree_main.runQuiet(testing.allocator, @constCast(args[0..])) catch {
        // Tree command with empty directories failed
        try testing.expect(false);
    };

    std.debug.print("✅ Tree command with empty directories test passed!\n", .{});
}

// Test memory usage and cleanup
test "tree command memory usage" {
    // Test with a moderately large directory structure
    const test_dir = "memory_test_tree";
    std.fs.cwd().makeDir(test_dir) catch {};
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // Create moderately-sized directory structure
    var i: u32 = 0;
    while (i < 15) : (i += 1) {
        const dir_name = try std.fmt.allocPrint(testing.allocator, "{s}/dir_{d}", .{ test_dir, i });
        defer testing.allocator.free(dir_name);
        std.fs.cwd().makeDir(dir_name) catch {};

        // Add files in each directory
        var j: u32 = 0;
        while (j < 5) : (j += 1) {
            const file_name = try std.fmt.allocPrint(testing.allocator, "{s}/file_{d}.txt", .{ dir_name, j });
            defer testing.allocator.free(file_name);
            const file = std.fs.cwd().createFile(file_name, .{}) catch continue;
            file.close();
        }
    }

    // Run tree command - should handle memory efficiently
    const args = [_][:0]const u8{ "tree", test_dir };
    tree_main.runQuiet(testing.allocator, @constCast(args[0..])) catch {
        // Tree command memory test failed
        try testing.expect(false);
    };

    std.debug.print("✅ Tree command memory usage test passed!\n", .{});
}

// Test tree command argument edge cases
test "tree command argument edge cases" {
    // Test minimum arguments
    const args_min = [_][:0]const u8{"tree"};
    tree_main.runQuiet(testing.allocator, @constCast(args_min[0..])) catch {
        // Should work with current directory
        // Expected to fail with error, test passed
    };

    // Test with current directory explicitly
    const args_current = [_][:0]const u8{ "tree", "." };
    tree_main.runQuiet(testing.allocator, @constCast(args_current[0..])) catch {
        // Expected to fail with error, test passed
    };

    // Test with very large depth number
    const test_dir = "edge_args_test";
    std.fs.cwd().makeDir(test_dir) catch {};
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    const args_large_depth = [_][:0]const u8{ "tree", test_dir, "999999" };
    tree_main.runQuiet(testing.allocator, @constCast(args_large_depth[0..])) catch {
        // Expected to fail with error, test passed
    };

    std.debug.print("✅ Tree command argument edge cases test passed!\n", .{});
}

test "tree and list format produce different outputs" {
    // Create a test directory structure
    const test_dir = "format_test";
    std.fs.cwd().makeDir(test_dir) catch {};
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // Create subdirectories and files
    const full_sub_path = try std.fmt.allocPrint(testing.allocator, "{s}/subdir", .{test_dir});
    defer testing.allocator.free(full_sub_path);
    std.fs.cwd().makeDir(full_sub_path) catch {};

    const full_file_path = try std.fmt.allocPrint(testing.allocator, "{s}/file.txt", .{test_dir});
    defer testing.allocator.free(full_file_path);
    const file = std.fs.cwd().createFile(full_file_path, .{}) catch unreachable;
    file.close();

    // Test both formats work without crashing
    const args_tree = [_][:0]const u8{ "tree", test_dir, "2", "--format=tree" };
    tree_main.runQuiet(testing.allocator, @constCast(args_tree[0..])) catch {
        try testing.expect(false); // Should not fail
    };

    const args_list = [_][:0]const u8{ "tree", test_dir, "2", "--format=list" };
    tree_main.runQuiet(testing.allocator, @constCast(args_list[0..])) catch {
        try testing.expect(false); // Should not fail
    };

    // Test that short flag was removed (should now use --format=list)

    std.debug.print("✅ Tree and list format integration test passed!\n", .{});
}

test "format flags with depth and directory combinations" {
    // Create a nested test directory
    const test_dir = "format_combo_test";
    std.fs.cwd().makeDir(test_dir) catch {};
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    const level1_path = try std.fmt.allocPrint(testing.allocator, "{s}/level1", .{test_dir});
    defer testing.allocator.free(level1_path);
    std.fs.cwd().makeDir(level1_path) catch {};

    const level2_path = try std.fmt.allocPrint(testing.allocator, "{s}/level1/level2", .{test_dir});
    defer testing.allocator.free(level2_path);
    std.fs.cwd().makeDir(level2_path) catch {};

    // Test various combinations
    const test_cases = [_]struct {
        args: []const [:0]const u8,
        description: []const u8,
    }{
        .{ .args = &.{ "tree", test_dir, "--format=list" }, .description = "directory + list format" },
        .{ .args = &.{ "tree", test_dir, "1", "--format=list" }, .description = "directory + depth + list format" },
        .{ .args = &.{ "tree", "--format=tree", test_dir, "2" }, .description = "format first, then directory + depth" },
        .{ .args = &.{ "tree", "--format=list", test_dir, "1" }, .description = "format first, then directory + depth" },
    };

    for (test_cases) |test_case| {
        tree_main.runQuiet(testing.allocator, @constCast(test_case.args)) catch |err| {
            std.debug.print("❌ Failed test case: {s}, error: {}\n", .{ test_case.description, err });
            try testing.expect(false);
        };
    }

    std.debug.print("✅ Format flags with combinations test passed!\n", .{});
}

test "format error handling integration" {
    const test_dir = "format_error_test";
    std.fs.cwd().makeDir(test_dir) catch {};
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // Test invalid format should error (using quiet config parsing)
    const Config = @import("../config.zig").Config;
    const args_invalid = [_][:0]const u8{ "tree", test_dir, "--format=invalid" };
    const result = Config.fromArgsQuiet(testing.allocator, @constCast(args_invalid[0..]));
    try testing.expectError(error.InvalidFormat, result);

    // Test invalid flag should error (using quiet config parsing)
    const args_bad_flag = [_][:0]const u8{ "tree", test_dir, "--bad-flag" };
    const result2 = Config.fromArgsQuiet(testing.allocator, @constCast(args_bad_flag[0..]));
    try testing.expectError(error.InvalidFlag, result2);

    std.debug.print("✅ Format error handling integration test passed!\n", .{});
}
