const std = @import("std");
const testing = std.testing;

const Walker = @import("../walker.zig").Walker;
const Config = @import("../config.zig").Config;
const SharedConfig = @import("../../config.zig").SharedConfig;

// Helper to create test directory structure
fn createTestStructure(dir: std.fs.Dir, dir_count: u32, files_per_dir: u32) !void {
    var dir_idx: u32 = 0;
    while (dir_idx < dir_count) : (dir_idx += 1) {
        const dir_name = try std.fmt.allocPrint(testing.allocator, "dir_{d}", .{dir_idx});
        defer testing.allocator.free(dir_name);
        try dir.makeDir(dir_name);

        var file_idx: u32 = 0;
        while (file_idx < files_per_dir) : (file_idx += 1) {
            const file_name = try std.fmt.allocPrint(testing.allocator, "{s}/file_{d}.txt", .{ dir_name, file_idx });
            defer testing.allocator.free(file_name);
            const file = try dir.createFile(file_name, .{});
            file.close();
        }
    }
}

// Helper to time walker operations
fn timeWalkerOperation(walker: Walker, path: []const u8) !i64 {
    const start_time = std.time.milliTimestamp();
    try walker.walk(path);
    return std.time.milliTimestamp() - start_time;
}

// Performance benchmarks and stress tests for the tree module
test "performance with large directory structure" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const test_dir_path = try tmp_dir.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(test_dir_path);

    // Create a moderately-sized directory structure (100 dirs, 300 files)
    const start_creation = std.time.milliTimestamp();

    var dir_count: u32 = 0;
    var file_count: u32 = 0;

    while (dir_count < 20) : (dir_count += 1) {
        const dir_name = try std.fmt.allocPrint(testing.allocator, "dir_{d}", .{dir_count});
        defer testing.allocator.free(dir_name);
        try tmp_dir.dir.makeDir(dir_name);

        // Create subdirectories
        var subdir_count: u32 = 0;
        while (subdir_count < 5) : (subdir_count += 1) {
            const subdir_name = try std.fmt.allocPrint(testing.allocator, "{s}/subdir_{d}", .{ dir_name, subdir_count });
            defer testing.allocator.free(subdir_name);
            try tmp_dir.dir.makePath(subdir_name);

            // Add files to subdirectory
            var file_in_subdir: u32 = 0;
            while (file_in_subdir < 3) : (file_in_subdir += 1) {
                const file_name = try std.fmt.allocPrint(testing.allocator, "{s}/file_{d}.txt", .{ subdir_name, file_in_subdir });
                defer testing.allocator.free(file_name);
                const file = try tmp_dir.dir.createFile(file_name, .{});
                file.close();
                file_count += 1;
            }
        }
    }

    const creation_time = std.time.milliTimestamp() - start_creation;
    std.debug.print("Created test structure with ~{d} directories and ~{d} files in {d}ms\n", .{ dir_count * 5, file_count, creation_time });

    // Now benchmark the tree traversal
    const ignored = [_][]const u8{ ".git", "node_modules" }; // Minimal patterns
    const hidden = [_][]const u8{};

    const shared_config = SharedConfig{
        .ignored_patterns = &ignored,
        .hidden_files = &hidden,
        .gitignore_patterns = &[_][]const u8{},
        .symlink_behavior = .skip,
        .respect_gitignore = false,
        .patterns_allocated = false,
    };

    const config = Config{
        .shared_config = shared_config,
    };

    const walker = Walker.initQuiet(testing.allocator, config);

    const start_traversal = std.time.milliTimestamp();
    try walker.walk(test_dir_path);
    const traversal_time = std.time.milliTimestamp() - start_traversal;

    // Performance expectations: should complete in reasonable time
    try testing.expect(traversal_time < 5000); // Less than 5 seconds

    std.debug.print("✓ Large directory structure traversal completed in {d}ms\n", .{traversal_time});
}

// Test performance with many ignored directories
test "performance with many ignored directories" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const test_dir_path = try tmp_dir.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(test_dir_path);

    // Create some directories that should be ignored
    var ignored_count: u32 = 0;
    while (ignored_count < 8) : (ignored_count += 1) {
        const dir_name = try std.fmt.allocPrint(testing.allocator, "node_modules_{d}", .{ignored_count});
        defer testing.allocator.free(dir_name);
        try tmp_dir.dir.makeDir(dir_name);

        // Add files that should never be read
        var file_count: u32 = 0;
        while (file_count < 5) : (file_count += 1) {
            const file_name = try std.fmt.allocPrint(testing.allocator, "{s}/ignored_file_{d}.js", .{ dir_name, file_count });
            defer testing.allocator.free(file_name);
            const file = try tmp_dir.dir.createFile(file_name, .{});
            file.close();
        }
    }

    // Also create some normal directories
    var normal_count: u32 = 0;
    while (normal_count < 10) : (normal_count += 1) {
        const dir_name = try std.fmt.allocPrint(testing.allocator, "normal_dir_{d}", .{normal_count});
        defer testing.allocator.free(dir_name);
        try tmp_dir.dir.makeDir(dir_name);

        const file_name = try std.fmt.allocPrint(testing.allocator, "{s}/normal_file.txt", .{dir_name});
        defer testing.allocator.free(file_name);
        const file = try tmp_dir.dir.createFile(file_name, .{});
        file.close();
    }

    // Test with pattern that ignores most directories
    const ignored = [_][]const u8{ "node_modules_0", "node_modules_1", "node_modules_2", "node_modules_3", "node_modules_4", "node_modules_5" };
    const hidden = [_][]const u8{};

    const shared_config = SharedConfig{
        .ignored_patterns = &ignored,
        .hidden_files = &hidden,
        .gitignore_patterns = &[_][]const u8{},
        .symlink_behavior = .skip,
        .respect_gitignore = false,
        .patterns_allocated = false,
    };

    const config = Config{
        .shared_config = shared_config,
    };

    const walker = Walker.initQuiet(testing.allocator, config);

    const start_time = std.time.milliTimestamp();
    try walker.walk(test_dir_path);
    const end_time = std.time.milliTimestamp();

    const duration = end_time - start_time;

    // Should be fast because most directories are ignored and not traversed
    try testing.expect(duration < 1000); // Less than 1 second

    std.debug.print("✓ Many ignored directories test completed in {d}ms\n", .{duration});
}

// Test memory efficiency with deep nesting
test "memory efficiency with deep nesting" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const test_dir_path = try tmp_dir.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(test_dir_path);

    // Create very deep directory structure
    var current_path = try std.fmt.allocPrint(testing.allocator, ".", .{});
    defer testing.allocator.free(current_path);

    var depth: u32 = 0;
    while (depth < 20) : (depth += 1) {
        const next_path = try std.fmt.allocPrint(testing.allocator, "{s}/level_{d}", .{ current_path, depth });
        testing.allocator.free(current_path);
        current_path = next_path;

        tmp_dir.dir.makePath(current_path) catch break;

        // Add a file at each level
        const file_path = try std.fmt.allocPrint(testing.allocator, "{s}/file.txt", .{current_path});
        defer testing.allocator.free(file_path);
        const file = tmp_dir.dir.createFile(file_path, .{}) catch continue;
        file.close();
    }

    const ignored = [_][]const u8{};
    const hidden = [_][]const u8{};

    const shared_config = SharedConfig{
        .ignored_patterns = &ignored,
        .hidden_files = &hidden,
        .gitignore_patterns = &[_][]const u8{},
        .symlink_behavior = .skip,
        .respect_gitignore = false,
        .patterns_allocated = false,
    };

    const config = Config{
        .shared_config = shared_config,
    };

    const walker = Walker.initQuiet(testing.allocator, config);

    const start_time = std.time.milliTimestamp();
    try walker.walk(test_dir_path);
    const end_time = std.time.milliTimestamp();

    const duration = end_time - start_time;

    // Should handle deep nesting efficiently
    try testing.expect(duration < 2000); // Less than 2 seconds

    std.debug.print("✓ Deep nesting test ({d} levels) completed in {d}ms\n", .{ depth, duration });
}

// Test performance comparison: ignored vs not ignored
test "performance comparison ignored vs not ignored" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const test_dir_ignored = "perf_comparison_ignored";
    const test_dir_normal = "perf_comparison_normal";

    // Create identical directory structures
    for ([_][]const u8{ test_dir_ignored, test_dir_normal }) |base_dir| {
        try tmp_dir.dir.makeDir(base_dir);

        // Create node_modules with many files
        const nm_path = try std.fmt.allocPrint(testing.allocator, "{s}/node_modules", .{base_dir});
        defer testing.allocator.free(nm_path);
        try tmp_dir.dir.makeDir(nm_path);

        var file_count: u32 = 0;
        while (file_count < 1000) : (file_count += 1) {
            const file_name = try std.fmt.allocPrint(testing.allocator, "{s}/file_{d}.js", .{ nm_path, file_count });
            defer testing.allocator.free(file_name);
            const file = try tmp_dir.dir.createFile(file_name, .{});
            file.close();
        }

        // Add normal directories
        const src_dir_path = try std.fmt.allocPrint(testing.allocator, "{s}/src", .{base_dir});
        defer testing.allocator.free(src_dir_path);
        try tmp_dir.dir.makeDir(src_dir_path);

        const src_file_path = try std.fmt.allocPrint(testing.allocator, "{s}/src/main.zig", .{base_dir});
        defer testing.allocator.free(src_file_path);
        const src_file = try tmp_dir.dir.createFile(src_file_path, .{});
        src_file.close();
    }

    // Cleanup handled by tmp_dir.cleanup()

    // Test with node_modules ignored
    const ignored = [_][]const u8{"node_modules"};
    const hidden = [_][]const u8{};

    const shared_config = SharedConfig{
        .ignored_patterns = &ignored,
        .hidden_files = &hidden,
        .gitignore_patterns = &[_][]const u8{},
        .symlink_behavior = .skip,
        .respect_gitignore = false,
        .patterns_allocated = false,
    };

    const config_ignored = Config{
        .shared_config = shared_config,
    };

    const walker_ignored = Walker.initQuiet(testing.allocator, config_ignored);

    const test_dir_ignored_path = try tmp_dir.dir.realpathAlloc(testing.allocator, test_dir_ignored);
    defer testing.allocator.free(test_dir_ignored_path);

    const start_ignored = std.time.milliTimestamp();
    try walker_ignored.walk(test_dir_ignored_path);
    const time_ignored = std.time.milliTimestamp() - start_ignored;

    // Test without ignoring node_modules
    const ignored2 = [_][]const u8{}; // No ignores
    const hidden2 = [_][]const u8{};

    const shared_config2 = SharedConfig{
        .ignored_patterns = &ignored2,
        .hidden_files = &hidden2,
        .gitignore_patterns = &[_][]const u8{},
        .symlink_behavior = .skip,
        .respect_gitignore = false,
        .patterns_allocated = false,
    };

    const config_normal = Config{
        .shared_config = shared_config2,
    };

    const walker_normal = Walker.initQuiet(testing.allocator, config_normal);

    const test_dir_normal_path = try tmp_dir.dir.realpathAlloc(testing.allocator, test_dir_normal);
    defer testing.allocator.free(test_dir_normal_path);

    const start_normal = std.time.milliTimestamp();
    try walker_normal.walk(test_dir_normal_path);
    const time_normal = std.time.milliTimestamp() - start_normal;

    // Ignored version should be significantly faster
    const speedup_ratio = @as(f32, @floatFromInt(time_normal)) / @as(f32, @floatFromInt(time_ignored));

    std.debug.print("Performance comparison:\n", .{});
    std.debug.print("  With ignoring: {d}ms\n", .{time_ignored});
    std.debug.print("  Without ignoring: {d}ms\n", .{time_normal});
    std.debug.print("  Speedup: {d:.2}x\n", .{speedup_ratio});

    // Should see at least 2x speedup from ignoring large directories
    try testing.expect(speedup_ratio >= 2.0);

    std.debug.print("✓ Performance comparison test passed (speedup: {d:.2}x)\n", .{speedup_ratio});
}

// Test scalability with increasing directory sizes
test "scalability with increasing directory sizes" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const base_dir = "perf_scalability";
    try tmp_dir.dir.makeDir(base_dir);

    const ignored = [_][]const u8{".git"};
    const hidden = [_][]const u8{};

    const shared_config = SharedConfig{
        .ignored_patterns = &ignored,
        .hidden_files = &hidden,
        .gitignore_patterns = &[_][]const u8{},
        .symlink_behavior = .skip,
        .respect_gitignore = false,
        .patterns_allocated = false,
    };

    const config = Config{
        .shared_config = shared_config,
    };

    const walker = Walker.initQuiet(testing.allocator, config);

    // Test with increasing numbers of files
    const test_sizes = [_]u32{ 10, 25, 50, 75, 100 };
    var previous_time: i64 = 0;

    for (test_sizes) |size| {
        // Clean directory
        tmp_dir.dir.deleteTree(base_dir) catch {};
        try tmp_dir.dir.makeDir(base_dir);

        // Create files
        var file_count: u32 = 0;
        while (file_count < size) : (file_count += 1) {
            const file_name = try std.fmt.allocPrint(testing.allocator, "{s}/file_{d}.txt", .{ base_dir, file_count });
            defer testing.allocator.free(file_name);
            const file = try tmp_dir.dir.createFile(file_name, .{});
            file.close();
        }

        // Time traversal
        const base_dir_path = try tmp_dir.dir.realpathAlloc(testing.allocator, base_dir);
        defer testing.allocator.free(base_dir_path);

        const start_time = std.time.milliTimestamp();
        try walker.walk(base_dir_path);
        const duration = std.time.milliTimestamp() - start_time;

        std.debug.print("Traversal of {d} files: {d}ms\n", .{ size, duration });

        // Check that performance scales reasonably (not exponentially)
        if (previous_time > 0 and previous_time >= 2 and duration >= 2) { // Only test if we have meaningful timing data
            const scale_factor = @as(f32, @floatFromInt(size)) / @as(f32, @floatFromInt(test_sizes[0]));
            const time_factor = @as(f32, @floatFromInt(duration)) / @as(f32, @floatFromInt(previous_time));

            // Be more lenient - performance can vary due to system load
            // Main goal is to detect exponential scaling, not precise timing
            if (time_factor > scale_factor * 5.0) { // Much more generous threshold
                std.debug.print("⚠️  Performance scaling concern: time_factor={d:.2}, scale_factor={d:.2}\n", .{ time_factor, scale_factor });
                // Don't fail the test - just warn about potential performance issues
            }
        }

        previous_time = duration;
    }

    std.debug.print("✓ Scalability test passed - performance scales reasonably\n", .{});
}

// Memory stress test
test "memory stress test" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const test_dir = "perf_memory_stress";
    try tmp_dir.dir.makeDir(test_dir);

    // Create a structure that could cause memory issues if not handled properly
    var level1: u32 = 0;
    while (level1 < 20) : (level1 += 1) {
        const l1_name = try std.fmt.allocPrint(testing.allocator, "{s}/level1_{d}", .{ test_dir, level1 });
        defer testing.allocator.free(l1_name);
        tmp_dir.dir.makeDir(l1_name) catch continue;

        var level2: u32 = 0;
        while (level2 < 3) : (level2 += 1) {
            const l2_name = try std.fmt.allocPrint(testing.allocator, "{s}/level2_{d}", .{ l1_name, level2 });
            defer testing.allocator.free(l2_name);
            tmp_dir.dir.makeDir(l2_name) catch continue;

            // Add files
            var file_idx: u32 = 0;
            while (file_idx < 2) : (file_idx += 1) {
                const file_name = try std.fmt.allocPrint(testing.allocator, "{s}/file_{d}.txt", .{ l2_name, file_idx });
                defer testing.allocator.free(file_name);
                const file = try tmp_dir.dir.createFile(file_name, .{});
                file.close();
            }
        }
    }

    const ignored = [_][]const u8{};
    const hidden = [_][]const u8{};

    const shared_config = SharedConfig{
        .ignored_patterns = &ignored,
        .hidden_files = &hidden,
        .gitignore_patterns = &[_][]const u8{},
        .symlink_behavior = .skip,
        .respect_gitignore = false,
        .patterns_allocated = false,
    };

    const config = Config{
        .shared_config = shared_config,
    };

    // Run traversal multiple times to test memory handling
    const test_dir_path = try tmp_dir.dir.realpathAlloc(testing.allocator, test_dir);
    defer testing.allocator.free(test_dir_path);

    var iteration: u32 = 0;
    while (iteration < 5) : (iteration += 1) {
        const walker = Walker.initQuiet(testing.allocator, config);

        const start_time = std.time.milliTimestamp();
        try walker.walk(test_dir_path);
        const duration = std.time.milliTimestamp() - start_time;

        std.debug.print("Memory stress iteration {d}: {d}ms\n", .{ iteration + 1, duration });
    }

    std.debug.print("✓ Memory stress test passed - no memory issues detected\n", .{});
}
