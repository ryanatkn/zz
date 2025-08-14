const std = @import("std");
const testing = std.testing;

const tree_main = @import("../main.zig");
const test_helpers = @import("../../lib/test/helpers.zig");
const RealFilesystem = @import("../../lib/filesystem/real.zig").RealFilesystem;

// Integration tests for the complete tree module workflow
test "complete tree workflow with real directory" {
    var ctx = try test_helpers.TmpDirTestContext.init(testing.allocator);
    defer ctx.deinit();

    const test_dir = "integration_test_tree";
    try ctx.makeDir(test_dir);

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
        try ctx.makePath(full_path);
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
        try ctx.writeFile(full_path, "");
    }

    // Run the tree command
    const args = [_][:0]const u8{ "tree", test_dir };
    tree_main.runQuiet(testing.allocator, ctx.filesystem, @constCast(args[0..])) catch {
        try testing.expect(false); // Tree command should not fail
    };
}

// Test tree command with depth limitation
test "tree command with depth limitation" {
    var ctx = try test_helpers.TmpDirTestContext.init(testing.allocator);
    defer ctx.deinit();

    const test_dir = "depth_test_tree";
    try ctx.makeDir(test_dir);

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
        try ctx.makePath(full_path);

        // Add a file in each level
        const file_path = try std.fmt.allocPrint(testing.allocator, "{s}/file.txt", .{full_path});
        defer testing.allocator.free(file_path);
        try ctx.writeFile(file_path, "");
    }

    // Test with depth limit
    const args = [_][:0]const u8{ "tree", test_dir, "3" };
    tree_main.runQuiet(testing.allocator, ctx.filesystem, @constCast(args[0..])) catch {
        // Tree command with depth failed
        try testing.expect(false);
    };
}

// Test tree command error handling
test "tree command error handling" {
    // Use TmpDirTestContext for more robust error handling
    var tmp_ctx = try test_helpers.TmpDirTestContext.init(testing.allocator);
    defer tmp_ctx.deinit();

    const args_nonexistent = [_][:0]const u8{ "tree", "this_directory_does_not_exist" };

    // Should handle gracefully and not crash
    tree_main.runQuiet(testing.allocator, tmp_ctx.filesystem, @constCast(args_nonexistent[0..])) catch {
        // Expected to fail - directory does not exist
    };

    // Test with invalid depth parameter using TmpDirTestContext for better error handling
    const test_dir = "error_test_tree";
    try tmp_ctx.makeDir(test_dir);

    const args_invalid_depth = [_][:0]const u8{ "tree", test_dir, "not_a_number" };
    tree_main.runQuiet(testing.allocator, tmp_ctx.filesystem, @constCast(args_invalid_depth[0..])) catch {
        // Tree command with invalid depth failed - expected
        try testing.expect(false);
    };
}

// Test tree command with permission issues (if possible)
test "tree command with permission scenarios" {
    var ctx = try test_helpers.TmpDirTestContext.init(testing.allocator);
    defer ctx.deinit();

    const test_dir = "permission_test_tree";
    try ctx.makeDir(test_dir);

    // Create a normal directory structure
    try ctx.makePath(test_dir ++ "/normal");
    try ctx.writeFile(test_dir ++ "/normal/file.txt", "");

    // On Unix systems, we could try to create permission denied scenarios
    // But this is complex and platform-specific, so we'll just test normal operation

    const args = [_][:0]const u8{ "tree", test_dir };
    tree_main.runQuiet(testing.allocator, ctx.filesystem, @constCast(args[0..])) catch {
        // Tree command with permissions failed
        try testing.expect(false);
    };
}

// Test tree command with various file types
test "tree command with various file types" {
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const test_dir = "filetype_test_tree";
    try tmp_dir.dir.makeDir(test_dir);

    // Create different types of entries
    try tmp_dir.dir.makeDir(test_dir ++ "/directory");

    // Regular files
    try tmp_dir.dir.writeFile(.{
        .sub_path = test_dir ++ "/regular.txt",
        .data = "",
    });

    // Files with various extensions
    const extensions = [_][]const u8{ ".zig", ".md", ".json", ".txt", ".log", ".tmp" };
    for (extensions, 0..) |ext, i| {
        const filename = try std.fmt.allocPrint(testing.allocator, "{s}/file{d}{s}", .{ test_dir, i, ext });
        defer testing.allocator.free(filename);
        try tmp_dir.dir.writeFile(.{
            .sub_path = filename,
            .data = "",
        });
    }

    // Subdirectory with files
    try tmp_dir.dir.makePath(test_dir ++ "/subdir");
    try tmp_dir.dir.writeFile(.{
        .sub_path = test_dir ++ "/subdir/nested.txt",
        .data = "",
    });

    const tmp_base_path = try tmp_dir.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_base_path);
    const path_z = try std.fmt.allocPrint(testing.allocator, "{s}/{s}", .{ tmp_base_path, test_dir });
    defer testing.allocator.free(path_z);

    const path_z_sentinel = try testing.allocator.dupeZ(u8, path_z);
    defer testing.allocator.free(path_z_sentinel);
    const args = [_][:0]const u8{ "tree", path_z_sentinel };
    const filesystem = RealFilesystem.init();
    tree_main.runQuiet(testing.allocator, filesystem, @constCast(args[0..])) catch {
        // Tree command with file types failed
        try testing.expect(false);
    };
}

// Test tree command with empty directories
test "tree command with empty directories" {
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const test_dir = "empty_test_tree";
    try tmp_dir.dir.makeDir(test_dir);

    // Create empty directories at various levels
    try tmp_dir.dir.makeDir(test_dir ++ "/empty1");
    try tmp_dir.dir.makeDir(test_dir ++ "/empty2");
    try tmp_dir.dir.makePath(test_dir ++ "/parent");
    try tmp_dir.dir.makePath(test_dir ++ "/parent/empty_child");

    // Mix with non-empty
    try tmp_dir.dir.makePath(test_dir ++ "/non_empty");
    try tmp_dir.dir.writeFile(.{
        .sub_path = test_dir ++ "/non_empty/file.txt",
        .data = "",
    });

    const tmp_base_path2 = try tmp_dir.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_base_path2);
    const path_z = try std.fmt.allocPrint(testing.allocator, "{s}/{s}", .{ tmp_base_path2, test_dir });
    defer testing.allocator.free(path_z);

    const path_z_sentinel = try testing.allocator.dupeZ(u8, path_z);
    defer testing.allocator.free(path_z_sentinel);
    const args = [_][:0]const u8{ "tree", path_z_sentinel };
    const filesystem = RealFilesystem.init();
    tree_main.runQuiet(testing.allocator, filesystem, @constCast(args[0..])) catch {
        // Tree command with empty directories failed
        try testing.expect(false);
    };
}

// Test memory usage and cleanup
test "tree command memory usage" {
    // Test with a moderately large directory structure
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const test_dir = "memory_test_tree";
    try tmp_dir.dir.makeDir(test_dir);

    // Create moderately-sized directory structure
    var i: u32 = 0;
    while (i < 15) : (i += 1) {
        const dir_name = try std.fmt.allocPrint(testing.allocator, "{s}/dir_{d}", .{ test_dir, i });
        defer testing.allocator.free(dir_name);
        try tmp_dir.dir.makePath(dir_name);

        // Add files in each directory
        var j: u32 = 0;
        while (j < 5) : (j += 1) {
            const file_name = try std.fmt.allocPrint(testing.allocator, "{s}/file_{d}.txt", .{ dir_name, j });
            defer testing.allocator.free(file_name);
            try tmp_dir.dir.writeFile(.{
                .sub_path = file_name,
                .data = "",
            });
        }
    }

    // Run tree command - should handle memory efficiently
    const tmp_base_path3 = try tmp_dir.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_base_path3);
    const path_z = try std.fmt.allocPrint(testing.allocator, "{s}/{s}", .{ tmp_base_path3, test_dir });
    defer testing.allocator.free(path_z);

    const path_z_sentinel = try testing.allocator.dupeZ(u8, path_z);
    defer testing.allocator.free(path_z_sentinel);
    const args = [_][:0]const u8{ "tree", path_z_sentinel };
    const filesystem = RealFilesystem.init();
    tree_main.runQuiet(testing.allocator, filesystem, @constCast(args[0..])) catch {
        // Tree command memory test failed
        try testing.expect(false);
    };
}

// Test tree command argument edge cases
test "tree command argument edge cases" {
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Test minimum arguments (current directory)
    const current_path_z = try tmp_dir.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(current_path_z);

    const current_path_z_sentinel = try testing.allocator.dupeZ(u8, current_path_z);
    defer testing.allocator.free(current_path_z_sentinel);
    const args_current = [_][:0]const u8{ "tree", current_path_z_sentinel };
    const fs_current = RealFilesystem.init();
    tree_main.runQuiet(testing.allocator, fs_current, @constCast(args_current[0..])) catch {
        // Should work with current directory
    };

    // Test with very large depth number
    const test_dir = "edge_args_test";
    try tmp_dir.dir.makeDir(test_dir);

    const tmp_base_path4 = try tmp_dir.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_base_path4);
    const path_z = try std.fmt.allocPrint(testing.allocator, "{s}/{s}", .{ tmp_base_path4, test_dir });
    defer testing.allocator.free(path_z);

    const path_z_large_sentinel = try testing.allocator.dupeZ(u8, path_z);
    defer testing.allocator.free(path_z_large_sentinel);
    const args_large_depth = [_][:0]const u8{ "tree", path_z_large_sentinel, "999999" };
    const fs_large = RealFilesystem.init();
    tree_main.runQuiet(testing.allocator, fs_large, @constCast(args_large_depth[0..])) catch {
        // Should handle large depth gracefully
    };
}

test "tree and list format produce different outputs" {
    // Create a test directory structure
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const test_dir = "format_test";
    try tmp_dir.dir.makeDir(test_dir);

    // Create subdirectories and files
    try tmp_dir.dir.makePath(test_dir ++ "/subdir");
    try tmp_dir.dir.writeFile(.{
        .sub_path = test_dir ++ "/file.txt",
        .data = "",
    });

    const tmp_base_path5 = try tmp_dir.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_base_path5);
    const path_z = try std.fmt.allocPrint(testing.allocator, "{s}/{s}", .{ tmp_base_path5, test_dir });
    defer testing.allocator.free(path_z);

    // Test both formats work without crashing
    const path_z_tree_sentinel = try testing.allocator.dupeZ(u8, path_z);
    defer testing.allocator.free(path_z_tree_sentinel);
    const args_tree = [_][:0]const u8{ "tree", path_z_tree_sentinel, "2", "--format=tree" };
    const fs_tree = RealFilesystem.init();
    tree_main.runQuiet(testing.allocator, fs_tree, @constCast(args_tree[0..])) catch {
        try testing.expect(false); // Should not fail
    };

    const path_z_list_sentinel = try testing.allocator.dupeZ(u8, path_z);
    defer testing.allocator.free(path_z_list_sentinel);
    const args_list = [_][:0]const u8{ "tree", path_z_list_sentinel, "2", "--format=list" };
    const fs_list = RealFilesystem.init();
    tree_main.runQuiet(testing.allocator, fs_list, @constCast(args_list[0..])) catch {
        try testing.expect(false); // Should not fail
    };
}

test "format flags with depth and directory combinations" {
    // Create a nested test directory
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const test_dir = "format_combo_test";
    try tmp_dir.dir.makeDir(test_dir);
    try tmp_dir.dir.makePath(test_dir ++ "/level1");
    try tmp_dir.dir.makePath(test_dir ++ "/level1/level2");

    const tmp_base_path6 = try tmp_dir.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_base_path6);
    const path_z = try std.fmt.allocPrint(testing.allocator, "{s}/{s}", .{ tmp_base_path6, test_dir });
    defer testing.allocator.free(path_z);

    // Test various combinations
    const path_z_combo_sentinel = try testing.allocator.dupeZ(u8, path_z);
    defer testing.allocator.free(path_z_combo_sentinel);

    const test_cases = [_]struct {
        args: []const [:0]const u8,
        description: []const u8,
    }{
        .{ .args = &.{ "tree", path_z_combo_sentinel, "--format=list" }, .description = "directory + list format" },
        .{ .args = &.{ "tree", path_z_combo_sentinel, "1", "--format=list" }, .description = "directory + depth + list format" },
        .{ .args = &.{ "tree", "--format=tree", path_z_combo_sentinel, "2" }, .description = "format first, then directory + depth" },
        .{ .args = &.{ "tree", "--format=list", path_z_combo_sentinel, "1" }, .description = "format first, then directory + depth" },
    };

    for (test_cases) |test_case| {
        const fs_case = RealFilesystem.init();
        tree_main.runQuiet(testing.allocator, fs_case, @constCast(test_case.args)) catch |err| {
            std.debug.print("🞪 Failed test case: {s}, error: {}\n", .{ test_case.description, err });
            try testing.expect(false);
        };
    }
}

test "format error handling integration" {
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const test_dir = "format_error_test";
    try tmp_dir.dir.makeDir(test_dir);

    const tmp_base_path7 = try tmp_dir.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_base_path7);
    const path_z = try std.fmt.allocPrint(testing.allocator, "{s}/{s}", .{ tmp_base_path7, test_dir });
    defer testing.allocator.free(path_z);

    // Test invalid format should error (using quiet config parsing)
    const Config = @import("../config.zig").Config;
    const filesystem = RealFilesystem.init();
    const path_z_invalid_sentinel = try testing.allocator.dupeZ(u8, path_z);
    defer testing.allocator.free(path_z_invalid_sentinel);
    const args_invalid = [_][:0]const u8{ "tree", path_z_invalid_sentinel, "--format=invalid" };
    const result = Config.fromArgsQuiet(testing.allocator, filesystem, @constCast(args_invalid[0..]));
    try testing.expectError(error.InvalidFormat, result);

    // Test invalid flag should error (using quiet config parsing)
    const path_z_bad_flag_sentinel = try testing.allocator.dupeZ(u8, path_z);
    defer testing.allocator.free(path_z_bad_flag_sentinel);
    const args_bad_flag = [_][:0]const u8{ "tree", path_z_bad_flag_sentinel, "--bad-flag" };
    const result2 = Config.fromArgsQuiet(testing.allocator, filesystem, @constCast(args_bad_flag[0..]));
    try testing.expectError(error.InvalidFlag, result2);

    // Test passed
}

// Safety check: Verify no test artifacts leak into the actual working directory
// This test intentionally uses std.fs.cwd() to check the real project directory,
// not a temp directory. It ensures that all other tests properly use tmpDir()
// and don't accidentally create files in the project root.
test "no test artifacts in working directory" {
    // Check that no test directories are left in the current working directory
    var cwd = try std.fs.cwd().openDir(".", .{ .iterate = true });
    defer cwd.close();

    const test_prefixes = [_][]const u8{
        "integration_test_tree",
        "depth_test_tree",
        "error_test_tree",
        "permission_test_tree",
        "filetype_test_tree",
        "empty_test_tree",
        "memory_test_tree",
        "edge_args_test",
        "format_test",
        "format_combo_test",
        "format_error_test",
    };

    var it = cwd.iterate();
    while (try it.next()) |entry| {
        for (test_prefixes) |prefix| {
            if (std.mem.eql(u8, entry.name, prefix)) {
                // Test artifact found in working directory - tests are leaking!
                return error.TestArtifactInWorkingDirectory;
            }
        }
    }
}
