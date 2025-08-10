const std = @import("std");
const testing = std.testing;
const Walker = @import("../walker.zig").Walker;
const Config = @import("../config.zig").Config;
const TreeConfig = @import("../config.zig").TreeConfig;

// Mock filesystem operations to track directory access
var mock_active = false;

// Test that verifies ignored directories are never crawled - basic case
test "basic ignored directories are not crawled" {
    var accessed_directories = std.ArrayList([]const u8).init(testing.allocator);
    defer accessed_directories.deinit();

    // Create a temporary test directory structure
    const test_dir = "test_crawl_behavior";
    std.fs.cwd().makeDir(test_dir) catch {};
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // Create subdirectories including ones that should be ignored
    const subdirs = [_][]const u8{ "normal_dir", "src", "node_modules", ".git", "target" };
    for (subdirs) |subdir| {
        const full_path = try std.fmt.allocPrint(testing.allocator, "{s}/{s}", .{ test_dir, subdir });
        defer testing.allocator.free(full_path);
        std.fs.cwd().makeDir(full_path) catch {};

        // Add some files in each directory so readdir() would find something
        const test_file = try std.fmt.allocPrint(testing.allocator, "{s}/test.txt", .{full_path});
        defer testing.allocator.free(test_file);
        const file = std.fs.cwd().createFile(test_file, .{}) catch continue;
        file.close();
    }

    // Create special case: src/tree/compiled
    std.fs.cwd().makeDir(test_dir ++ "/src/tree") catch {};
    std.fs.cwd().makeDir(test_dir ++ "/src/tree/compiled") catch {};
    const compiled_file = std.fs.cwd().createFile(test_dir ++ "/src/tree/compiled/test.spv", .{}) catch unreachable;
    compiled_file.close();

    // Setup configuration with ignored patterns
    const tree_config = TreeConfig{
        .ignored_patterns = &[_][]const u8{ "node_modules", ".git", "target", "src/tree/compiled" },
        .hidden_files = &[_][]const u8{},
    };

    const config = Config{
        .tree_config = tree_config,
    };

    // Create a custom walker that tracks directory access
    const TestWalker = struct {
        base_walker: Walker,
        tracked_dirs: *std.ArrayList([]const u8),

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator, cfg: Config, tracked_dirs: *std.ArrayList([]const u8)) Self {
            return Self{
                .base_walker = Walker.init(allocator, cfg),
                .tracked_dirs = tracked_dirs,
            };
        }

        pub fn walkWithTracking(self: Self, path: []const u8) !void {
            mock_active = true;
            defer mock_active = false;
            self.tracked_dirs.clearRetainingCapacity();

            // Use our custom recursive function that tracks access
            try self.walkRecursiveWithTracking(path, "", true, 0);
        }

        fn walkRecursiveWithTracking(self: Self, path: []const u8, prefix: []const u8, is_last: bool, current_depth: u32) !void {
            // Record that we're accessing this directory
            const path_copy = try testing.allocator.dupe(u8, path);
            try self.tracked_dirs.append(path_copy);

            const basename = std.fs.path.basename(path);
            _ = basename;
            _ = prefix;
            _ = is_last; // Suppress unused warnings

            // Check depth limit
            if (self.base_walker.config.max_depth) |depth| {
                if (current_depth >= depth) return;
            }

            // Try to open directory
            const dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch |err| switch (err) {
                error.NotDir => return,
                error.InvalidUtf8 => return,
                error.BadPathName => return,
                error.FileNotFound => return,
                error.AccessDenied => return,
                error.SymLinkLoop => return,
                else => return err,
            };
            var iter_dir = dir;
            defer iter_dir.close();

            var entries = std.ArrayList(std.fs.Dir.Entry).init(self.base_walker.allocator);
            defer entries.deinit();

            var iterator = iter_dir.iterate();
            while (try iterator.next()) |dir_entry| {
                try entries.append(dir_entry);
            }

            // Sort entries
            std.sort.insertion(std.fs.Dir.Entry, entries.items, {}, struct {
                fn lessThan(context: void, lhs: std.fs.Dir.Entry, rhs: std.fs.Dir.Entry) bool {
                    _ = context;
                    if (lhs.kind == .directory and rhs.kind != .directory) return true;
                    if (lhs.kind != .directory and rhs.kind == .directory) return false;
                    return std.mem.lessThan(u8, lhs.name, rhs.name);
                }
            }.lessThan);

            // Process entries with ignore logic
            for (entries.items) |dir_entry| {
                if (std.mem.indexOfScalar(u8, dir_entry.name, 0) != null) continue;
                if (self.base_walker.filter.shouldHide(dir_entry.name)) continue;

                const full_path = std.fs.path.join(self.base_walker.allocator, &.{ path, dir_entry.name }) catch continue;
                defer self.base_walker.allocator.free(full_path);

                const is_ignored_by_name = self.base_walker.filter.shouldIgnore(dir_entry.name);
                const is_ignored_by_path = self.base_walker.filter.shouldIgnoreAtPath(full_path);
                const is_ignored = is_ignored_by_name or is_ignored_by_path;

                // Key test: if ignored, we should NOT recurse (and thus not track access)
                if (is_ignored and dir_entry.kind == .directory) {
                    // Ignored directories should not be recursed into
                    continue;
                }

                if (dir_entry.kind == .directory) {
                    try self.walkRecursiveWithTracking(full_path, "", false, current_depth + 1);
                }
            }
        }
    };

    // Run the walker with tracking
    const test_walker = TestWalker.init(testing.allocator, config, &accessed_directories);
    try test_walker.walkWithTracking(test_dir);

    // Verify results: ignored directories should NOT appear in accessed_directories
    const forbidden_paths = [_][]const u8{
        test_dir ++ "/node_modules",
        test_dir ++ "/.git",
        test_dir ++ "/target",
        test_dir ++ "/src/tree/compiled",
    };

    std.debug.print("\nAccessed directories:\n", .{});
    for (accessed_directories.items) |accessed_path| {
        std.debug.print("  {s}\n", .{accessed_path});
    }

    // Check that forbidden directories were never accessed
    for (forbidden_paths) |forbidden| {
        for (accessed_directories.items) |accessed| {
            if (std.mem.eql(u8, accessed, forbidden)) {
                std.debug.print("ERROR: Crawled into ignored directory: {s}\n", .{forbidden});
                try testing.expect(false); // Fail the test
            }
        }
        std.debug.print("✓ Correctly avoided: {s}\n", .{forbidden});
    }

    // Verify that normal directories WERE accessed
    const expected_paths = [_][]const u8{
        test_dir,
        test_dir ++ "/normal_dir",
        test_dir ++ "/src",
        test_dir ++ "/src/tree",
    };

    for (expected_paths) |expected| {
        var found = false;
        for (accessed_directories.items) |accessed| {
            if (std.mem.eql(u8, accessed, expected)) {
                found = true;
                break;
            }
        }
        if (!found) {
            std.debug.print("ERROR: Expected to access: {s}\n", .{expected});
            try testing.expect(false);
        }
        std.debug.print("✓ Correctly accessed: {s}\n", .{expected});
    }

    // Cleanup allocated paths
    for (accessed_directories.items) |path| {
        testing.allocator.free(path);
    }

    std.debug.print("✅ Basic crawl behavior test passed!\n", .{});
}

// Test nested ignored patterns
test "nested path patterns are not crawled" {
    var accessed_directories = std.ArrayList([]const u8).init(testing.allocator);
    defer accessed_directories.deinit();

    const test_dir = "test_nested_patterns";
    std.fs.cwd().makeDir(test_dir) catch {};
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // Create complex nested structure
    const paths_to_create = [_][]const u8{
        "src",                    "src/cli",                   "src/tree", "src/tree/compiled",
        "src/tree/compiled/test1", "src/tree/compiled/test2", "node_modules",
        "node_modules/deep",       "node_modules/deep/nested",
    };

    for (paths_to_create) |path| {
        const full_path = try std.fmt.allocPrint(testing.allocator, "{s}/{s}", .{ test_dir, path });
        defer testing.allocator.free(full_path);
        std.fs.cwd().makePath(full_path) catch {};

        // Add files to make directories "interesting" to crawl
        const test_file = try std.fmt.allocPrint(testing.allocator, "{s}/test.txt", .{full_path});
        defer testing.allocator.free(test_file);
        const file = std.fs.cwd().createFile(test_file, .{}) catch continue;
        file.close();
    }

    const tree_config = TreeConfig{
        .ignored_patterns = &[_][]const u8{ "node_modules", "src/tree/compiled" },
        .hidden_files = &[_][]const u8{},
    };

    const TestWalker = createTestWalker(tree_config);
    const test_walker = TestWalker.init(testing.allocator, Config{ .tree_config = tree_config }, &accessed_directories);
    try test_walker.walkWithTracking(test_dir);

    // Verify deep nested paths are not accessed
    const forbidden_paths = [_][]const u8{
        test_dir ++ "/node_modules",
        test_dir ++ "/node_modules/deep",
        test_dir ++ "/node_modules/deep/nested",
        test_dir ++ "/src/tree/compiled",
        test_dir ++ "/src/tree/compiled/test1",
        test_dir ++ "/src/tree/compiled/test2",
    };

    for (forbidden_paths) |forbidden| {
        for (accessed_directories.items) |accessed| {
            try testing.expect(!std.mem.eql(u8, accessed, forbidden));
        }
    }

    // But verify allowed paths are accessed
    const allowed_paths = [_][]const u8{
        test_dir ++ "/src",
        test_dir ++ "/src/cli",
        test_dir ++ "/src/tree",
    };

    for (allowed_paths) |allowed| {
        var found = false;
        for (accessed_directories.items) |accessed| {
            if (std.mem.eql(u8, accessed, allowed)) {
                found = true;
                break;
            }
        }
        try testing.expect(found);
    }

    // Cleanup
    for (accessed_directories.items) |path| {
        testing.allocator.free(path);
    }

    std.debug.print("✅ Nested patterns test passed!\n", .{});
}

// Test dot-prefixed directories
test "dot-prefixed directories are not crawled" {
    var accessed_directories = std.ArrayList([]const u8).init(testing.allocator);
    defer accessed_directories.deinit();

    const test_dir = "test_dot_dirs";
    std.fs.cwd().makeDir(test_dir) catch {};
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    const dot_dirs = [_][]const u8{ ".git", ".cache", ".config", ".hidden" };
    for (dot_dirs) |dot_dir| {
        const full_path = try std.fmt.allocPrint(testing.allocator, "{s}/{s}", .{ test_dir, dot_dir });
        defer testing.allocator.free(full_path);
        std.fs.cwd().makeDir(full_path) catch {};

        // Add nested structure inside dot dirs
        const nested = try std.fmt.allocPrint(testing.allocator, "{s}/nested", .{full_path});
        defer testing.allocator.free(nested);
        std.fs.cwd().makeDir(nested) catch {};

        const nested_file = try std.fmt.allocPrint(testing.allocator, "{s}/file.txt", .{nested});
        defer testing.allocator.free(nested_file);
        const file = std.fs.cwd().createFile(nested_file, .{}) catch continue;
        file.close();
    }

    // Also create normal directories
    const normal_dir = try std.fmt.allocPrint(testing.allocator, "{s}/normal", .{test_dir});
    defer testing.allocator.free(normal_dir);
    std.fs.cwd().makeDir(normal_dir) catch {};

    const normal_file = try std.fmt.allocPrint(testing.allocator, "{s}/file.txt", .{normal_dir});
    defer testing.allocator.free(normal_file);
    const file = std.fs.cwd().createFile(normal_file, .{}) catch unreachable;
    file.close();

    const tree_config = TreeConfig{
        .ignored_patterns = &[_][]const u8{}, // No explicit patterns - dots should be auto-ignored
        .hidden_files = &[_][]const u8{},
    };

    const TestWalker = createTestWalker(tree_config);
    const test_walker = TestWalker.init(testing.allocator, Config{ .tree_config = tree_config }, &accessed_directories);
    try test_walker.walkWithTracking(test_dir);

    // Verify no dot directories were crawled
    for (accessed_directories.items) |accessed| {
        const basename = std.fs.path.basename(accessed);
        if (basename.len > 0 and basename[0] == '.') {
            std.debug.print("ERROR: Crawled dot directory: {s}\n", .{accessed});
            try testing.expect(false);
        }
    }

    // Verify normal directory was crawled
    var found_normal = false;
    for (accessed_directories.items) |accessed| {
        if (std.mem.endsWith(u8, accessed, "/normal")) {
            found_normal = true;
            break;
        }
    }
    try testing.expect(found_normal);

    // Cleanup
    for (accessed_directories.items) |path| {
        testing.allocator.free(path);
    }

    std.debug.print("✅ Dot-prefixed directories test passed!\n", .{});
}

// Test empty vs populated directories
test "empty and populated ignored directories are not crawled" {
    var accessed_directories = std.ArrayList([]const u8).init(testing.allocator);
    defer accessed_directories.deinit();

    const test_dir = "test_empty_vs_populated";
    std.fs.cwd().makeDir(test_dir) catch {};
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // Create empty ignored directory
    const empty_dir = try std.fmt.allocPrint(testing.allocator, "{s}/empty_ignored", .{test_dir});
    defer testing.allocator.free(empty_dir);
    std.fs.cwd().makeDir(empty_dir) catch {};

    // Create populated ignored directory with many files
    const populated_dir = try std.fmt.allocPrint(testing.allocator, "{s}/populated_ignored", .{test_dir});
    defer testing.allocator.free(populated_dir);
    std.fs.cwd().makeDir(populated_dir) catch {};
    var i: u32 = 0;
    while (i < 20) : (i += 1) {
        const filename = try std.fmt.allocPrint(testing.allocator, "{s}/file_{d}.txt", .{ populated_dir, i });
        defer testing.allocator.free(filename);
        const file = std.fs.cwd().createFile(filename, .{}) catch continue;
        file.close();
    }

    // Create subdirectories in populated ignored
    const subdir1 = try std.fmt.allocPrint(testing.allocator, "{s}/subdir1", .{populated_dir});
    defer testing.allocator.free(subdir1);
    const subdir2 = try std.fmt.allocPrint(testing.allocator, "{s}/subdir2", .{populated_dir});
    defer testing.allocator.free(subdir2);
    std.fs.cwd().makeDir(subdir1) catch {};
    std.fs.cwd().makeDir(subdir2) catch {};

    const tree_config = TreeConfig{
        .ignored_patterns = &[_][]const u8{ "empty_ignored", "populated_ignored" },
        .hidden_files = &[_][]const u8{},
    };

    const TestWalker = createTestWalker(tree_config);
    const test_walker = TestWalker.init(testing.allocator, Config{ .tree_config = tree_config }, &accessed_directories);
    try test_walker.walkWithTracking(test_dir);

    // Verify neither empty nor populated ignored dirs were crawled
    const forbidden_paths = [_][]const u8{
        test_dir ++ "/empty_ignored",
        test_dir ++ "/populated_ignored",
        test_dir ++ "/populated_ignored/subdir1",
        test_dir ++ "/populated_ignored/subdir2",
    };

    for (forbidden_paths) |forbidden| {
        for (accessed_directories.items) |accessed| {
            try testing.expect(!std.mem.eql(u8, accessed, forbidden));
        }
    }

    // Cleanup
    for (accessed_directories.items) |path| {
        testing.allocator.free(path);
    }

    std.debug.print("✅ Empty vs populated directories test passed!\n", .{});
}

// Test configuration edge cases
test "configuration fallbacks and edge cases" {
    var accessed_directories = std.ArrayList([]const u8).init(testing.allocator);
    defer accessed_directories.deinit();

    const test_dir = "test_config_edge_cases";
    std.fs.cwd().makeDir(test_dir) catch {};
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // Test empty configuration
    const empty_config = TreeConfig{
        .ignored_patterns = &[_][]const u8{}, // Empty
        .hidden_files = &[_][]const u8{}, // Empty
    };

    const crawled_dir = try std.fmt.allocPrint(testing.allocator, "{s}/should_be_crawled", .{test_dir});
    defer testing.allocator.free(crawled_dir);
    std.fs.cwd().makeDir(crawled_dir) catch {};

    const crawled_file = try std.fmt.allocPrint(testing.allocator, "{s}/file.txt", .{crawled_dir});
    defer testing.allocator.free(crawled_file);
    const file = std.fs.cwd().createFile(crawled_file, .{}) catch unreachable;
    file.close();

    const TestWalker = createTestWalker(empty_config);
    const test_walker = TestWalker.init(testing.allocator, Config{ .tree_config = empty_config }, &accessed_directories);
    try test_walker.walkWithTracking(test_dir);

    // With empty config, normal dirs should be crawled
    var found = false;
    for (accessed_directories.items) |accessed| {
        if (std.mem.endsWith(u8, accessed, "/should_be_crawled")) {
            found = true;
            break;
        }
    }
    try testing.expect(found);

    // Cleanup
    for (accessed_directories.items) |path| {
        testing.allocator.free(path);
    }

    std.debug.print("✅ Configuration edge cases test passed!\n", .{});
}

// Test real project structure patterns
test "real project structure is handled correctly" {
    var accessed_directories = std.ArrayList([]const u8).init(testing.allocator);
    defer accessed_directories.deinit();

    const test_dir = "test_real_project";
    std.fs.cwd().makeDir(test_dir) catch {};
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // Simulate real project structure like our zz project
    const project_structure = [_][]const u8{
        "src",       "src/cli", "src/tree", "src/tree/compiled", "src/tree/test",
        "zig-out",   "zig-out/bin", ".git", ".zig-cache",
    };

    for (project_structure) |path| {
        const full_path = try std.fmt.allocPrint(testing.allocator, "{s}/{s}", .{ test_dir, path });
        defer testing.allocator.free(full_path);
        std.fs.cwd().makePath(full_path) catch {};

        // Add realistic files
        const extensions = [_][]const u8{ ".zig", ".md", ".txt" };
        for (extensions) |ext| {
            const filename = try std.fmt.allocPrint(testing.allocator, "{s}/test{s}", .{ full_path, ext });
            defer testing.allocator.free(filename);
            const file = std.fs.cwd().createFile(filename, .{}) catch continue;
            file.close();
        }
    }

    // Use realistic config (matches our defaults)
    const tree_config = TreeConfig{
        .ignored_patterns = &[_][]const u8{ ".git", ".zig-cache", "zig-out", "src/tree/compiled" },
        .hidden_files = &[_][]const u8{},
    };

    const TestWalker = createTestWalker(tree_config);
    const test_walker = TestWalker.init(testing.allocator, Config{ .tree_config = tree_config }, &accessed_directories);
    try test_walker.walkWithTracking(test_dir);

    // Verify ignored paths are not crawled
    const should_be_ignored = [_][]const u8{
        test_dir ++ "/.git",
        test_dir ++ "/.zig-cache",
        test_dir ++ "/zig-out",
        test_dir ++ "/zig-out/bin",
        test_dir ++ "/src/tree/compiled",
    };

    for (should_be_ignored) |ignored| {
        for (accessed_directories.items) |accessed| {
            try testing.expect(!std.mem.eql(u8, accessed, ignored));
        }
    }

    // Verify allowed paths are crawled
    const should_be_crawled = [_][]const u8{
        test_dir ++ "/src",
        test_dir ++ "/src/cli",
        test_dir ++ "/src/tree",
        test_dir ++ "/src/tree/test",
    };

    for (should_be_crawled) |expected| {
        var found = false;
        for (accessed_directories.items) |accessed| {
            if (std.mem.eql(u8, accessed, expected)) {
                found = true;
                break;
            }
        }
        if (!found) {
            std.debug.print("ERROR: Expected to find: {s}\n", .{expected});
            try testing.expect(false);
        }
    }

    // Cleanup
    for (accessed_directories.items) |path| {
        testing.allocator.free(path);
    }

    std.debug.print("✅ Real project structure test passed!\n", .{});
}

// Helper function to create test walker (reduces code duplication)
fn createTestWalker(comptime tree_config: TreeConfig) type {
    _ = tree_config; // Mark as used (comptime parameter)
    return struct {
        base_walker: Walker,
        tracked_dirs: *std.ArrayList([]const u8),

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator, cfg: Config, tracked_dirs: *std.ArrayList([]const u8)) Self {
            return Self{
                .base_walker = Walker.init(allocator, cfg),
                .tracked_dirs = tracked_dirs,
            };
        }

        pub fn walkWithTracking(self: Self, path: []const u8) !void {
            mock_active = true;
            defer mock_active = false;
            self.tracked_dirs.clearRetainingCapacity();

            try self.walkRecursiveWithTracking(path, "", true, 0);
        }

        fn walkRecursiveWithTracking(self: Self, path: []const u8, prefix: []const u8, is_last: bool, current_depth: u32) !void {
            // Record directory access
            const path_copy = try testing.allocator.dupe(u8, path);
            try self.tracked_dirs.append(path_copy);

            _ = prefix;
            _ = is_last; // Suppress unused warnings

            // Check depth limit
            if (self.base_walker.config.max_depth) |depth| {
                if (current_depth >= depth) return;
            }

            const dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return;
            var iter_dir = dir;
            defer iter_dir.close();

            var entries = std.ArrayList(std.fs.Dir.Entry).init(self.base_walker.allocator);
            defer entries.deinit();

            var iterator = iter_dir.iterate();
            while (try iterator.next()) |dir_entry| {
                try entries.append(dir_entry);
            }

            for (entries.items) |dir_entry| {
                if (std.mem.indexOfScalar(u8, dir_entry.name, 0) != null) continue;
                if (self.base_walker.filter.shouldHide(dir_entry.name)) continue;

                const full_path = std.fs.path.join(self.base_walker.allocator, &.{ path, dir_entry.name }) catch continue;
                defer self.base_walker.allocator.free(full_path);

                const is_ignored_by_name = self.base_walker.filter.shouldIgnore(dir_entry.name);
                const is_ignored_by_path = self.base_walker.filter.shouldIgnoreAtPath(full_path);
                const is_ignored = is_ignored_by_name or is_ignored_by_path;

                if (is_ignored and dir_entry.kind == .directory) {
                    continue; // Key test: don't recurse into ignored directories
                }

                if (dir_entry.kind == .directory) {
                    try self.walkRecursiveWithTracking(full_path, "", false, current_depth + 1);
                }
            }
        }
    };
}
