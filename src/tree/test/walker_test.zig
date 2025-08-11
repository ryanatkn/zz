const std = @import("std");
const testing = std.testing;

const Walker = @import("../walker.zig").Walker;
const Config = @import("../config.zig").Config;
const SharedConfig = @import("../../config.zig").SharedConfig;

// Mock filesystem operations to track directory access
var mock_active = false;

// Test that verifies ignored directories are never crawled - basic case
test "basic ignored directories are not crawled" {
    var accessed_directories = std.ArrayList([]const u8).init(testing.allocator);
    defer accessed_directories.deinit();

    // Create a temporary test directory structure
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const test_dir_path = try tmp_dir.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(test_dir_path);

    // Create subdirectories including ones that should be ignored
    const subdirs = [_][]const u8{ "normal_dir", "src", "node_modules", ".git", "target" };
    for (subdirs) |subdir| {
        try tmp_dir.dir.makeDir(subdir);

        // Add some files in each directory so readdir() would find something
        const test_file = try std.fmt.allocPrint(testing.allocator, "{s}/test.txt", .{subdir});
        defer testing.allocator.free(test_file);
        const file = try tmp_dir.dir.createFile(test_file, .{});
        file.close();
    }

    // Create special case: src/tree/compiled
    try tmp_dir.dir.makePath("src/tree");
    try tmp_dir.dir.makePath("src/tree/compiled");
    const compiled_file = try tmp_dir.dir.createFile("src/tree/compiled/test.spv", .{});
    compiled_file.close();

    // Setup configuration with ignored patterns
    const ignored = [_][]const u8{ "node_modules", ".git", "target", "src/tree/compiled" };
    const hidden = [_][]const u8{};
    
    const shared_config = SharedConfig{
        .ignored_patterns = &ignored,
        .hidden_files = &hidden,
        .symlink_behavior = .skip,
        .patterns_allocated = false,
    };

    const config = Config{
        .shared_config = shared_config,
    };

    // Create a custom walker that tracks directory access
    const TestWalker = struct {
        base_walker: Walker,
        tracked_dirs: *std.ArrayList([]const u8),
        root_dir: std.fs.Dir,
        root_path: []const u8,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator, cfg: Config, tracked_dirs: *std.ArrayList([]const u8), root_dir: std.fs.Dir, root_path: []const u8) Self {
            return Self{
                .base_walker = Walker.init(allocator, cfg),
                .tracked_dirs = tracked_dirs,
                .root_dir = root_dir,
                .root_path = root_path,
            };
        }

        pub fn walkWithTracking(self: Self, relative_path: []const u8) !void {
            mock_active = true;
            defer mock_active = false;
            
            // Free previously allocated strings
            for (self.tracked_dirs.items) |path| {
                testing.allocator.free(path);
            }
            self.tracked_dirs.clearRetainingCapacity();

            try self.walkRecursiveWithTracking(relative_path, "", true, 0);
        }

        fn walkRecursiveWithTracking(self: Self, relative_path: []const u8, prefix: []const u8, is_last: bool, current_depth: u32) !void {
            // Record that we're accessing this directory (store as absolute path for verification)
            const abs_path = if (std.mem.eql(u8, relative_path, "."))
                try testing.allocator.dupe(u8, self.root_path)
            else
                try std.fs.path.join(testing.allocator, &.{ self.root_path, relative_path });
            try self.tracked_dirs.append(abs_path);

            const basename = std.fs.path.basename(relative_path);
            _ = basename;
            _ = prefix;
            _ = is_last; // Suppress unused warnings

            // Check depth limit
            if (self.base_walker.config.max_depth) |depth| {
                if (current_depth >= depth) return;
            }

            // Try to open directory using the test directory handle
            const dir = self.root_dir.openDir(relative_path, .{ .iterate = true }) catch |err| switch (err) {
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

                const full_path = std.fs.path.join(self.base_walker.allocator, &.{ relative_path, dir_entry.name }) catch continue;
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
    const test_walker = TestWalker.init(testing.allocator, config, &accessed_directories, tmp_dir.dir, test_dir_path);
    try test_walker.walkWithTracking(".");

    // Verify results: ignored directories should NOT appear in accessed_directories
    const forbidden_suffixes = [_][]const u8{
        "/node_modules",
        "/.git",
        "/target",
        "/src/tree/compiled",
    };

    // Debug output removed - uncomment for troubleshooting
    // std.debug.print("\nAccessed directories:\n", .{});
    // for (accessed_directories.items) |accessed_path| {
    //     std.debug.print("  {s}\n", .{accessed_path});
    // }

    // Check that forbidden directories were never accessed
    for (forbidden_suffixes) |suffix| {
        for (accessed_directories.items) |accessed| {
            if (std.mem.endsWith(u8, accessed, suffix)) {
                // Found an ignored directory that was crawled
                try testing.expect(false); // Fail the test
            }
        }
        // Correctly avoided this suffix
    }

    // Verify that normal directories WERE accessed
    const expected_suffixes = [_][]const u8{
        "", // root
        "/normal_dir",
        "/src",
        "/src/tree",
    };

    for (expected_suffixes) |suffix| {
        var found = false;
        for (accessed_directories.items) |accessed| {
            if (suffix.len == 0) {
                if (std.mem.eql(u8, accessed, test_dir_path)) {
                    found = true;
                    break;
                }
            } else if (std.mem.endsWith(u8, accessed, suffix)) {
                found = true;
                break;
            }
        }
        if (!found) {
            // Expected to access this path but didn't
            try testing.expect(false);
        }
        // Correctly accessed this suffix
    }

    // Cleanup allocated paths
    for (accessed_directories.items) |path| {
        testing.allocator.free(path);
    }

    // Test passed
}

// Test nested ignored patterns
test "nested path patterns are not crawled" {
    var accessed_directories = std.ArrayList([]const u8).init(testing.allocator);
    defer accessed_directories.deinit();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const test_dir_path = try tmp_dir.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(test_dir_path);

    // Create complex nested structure
    const paths_to_create = [_][]const u8{
        "src",                      "src/cli",                 "src/tree",     "src/tree/compiled",
        "src/tree/compiled/test1",  "src/tree/compiled/test2", "node_modules", "node_modules/deep",
        "node_modules/deep/nested",
    };

    for (paths_to_create) |path| {
        try tmp_dir.dir.makePath(path);

        // Add files to make directories "interesting" to crawl
        const test_file = try std.fmt.allocPrint(testing.allocator, "{s}/test.txt", .{path});
        defer testing.allocator.free(test_file);
        const file = try tmp_dir.dir.createFile(test_file, .{});
        file.close();
    }

    const ignored = [_][]const u8{ "node_modules", "src/tree/compiled" };
    const hidden = [_][]const u8{};
    
    const shared_config = SharedConfig{
        .ignored_patterns = &ignored,
        .hidden_files = &hidden,
        .symlink_behavior = .skip,
        .patterns_allocated = false,
    };

    const TestWalker = createTestWalker(shared_config);
    const test_walker = TestWalker.init(testing.allocator, Config{ .shared_config = shared_config }, &accessed_directories, tmp_dir.dir, test_dir_path);
    try test_walker.walkWithTracking(".");

    // Verify deep nested paths are not accessed
    const forbidden_suffixes = [_][]const u8{
        "/node_modules",
        "/node_modules/deep",
        "/node_modules/deep/nested",
        "/src/tree/compiled",
        "/src/tree/compiled/test1",
        "/src/tree/compiled/test2",
    };

    for (forbidden_suffixes) |suffix| {
        for (accessed_directories.items) |accessed| {
            try testing.expect(!std.mem.endsWith(u8, accessed, suffix));
        }
    }

    // But verify allowed paths are accessed
    const allowed_suffixes = [_][]const u8{
        "/src",
        "/src/cli",
        "/src/tree",
    };

    for (allowed_suffixes) |suffix| {
        var found = false;
        for (accessed_directories.items) |accessed| {
            if (std.mem.endsWith(u8, accessed, suffix)) {
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

    // Test passed
}

// Test dot-prefixed directories
test "dot-prefixed directories are not crawled" {
    var accessed_directories = std.ArrayList([]const u8).init(testing.allocator);
    defer accessed_directories.deinit();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const test_dir_path = try tmp_dir.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(test_dir_path);

    const dot_dirs = [_][]const u8{ ".git", ".cache", ".config", ".hidden" };
    for (dot_dirs) |dot_dir| {
        try tmp_dir.dir.makeDir(dot_dir);

        // Add nested structure inside dot dirs
        const nested = try std.fmt.allocPrint(testing.allocator, "{s}/nested", .{dot_dir});
        defer testing.allocator.free(nested);
        try tmp_dir.dir.makePath(nested);

        const nested_file = try std.fmt.allocPrint(testing.allocator, "{s}/file.txt", .{nested});
        defer testing.allocator.free(nested_file);
        const file = try tmp_dir.dir.createFile(nested_file, .{});
        file.close();
    }

    // Also create normal directories
    try tmp_dir.dir.makeDir("normal");
    const file = try tmp_dir.dir.createFile("normal/file.txt", .{});
    file.close();

    const ignored = [_][]const u8{}; // No explicit patterns - dots should be auto-ignored
    const hidden = [_][]const u8{};
    
    const shared_config = SharedConfig{
        .ignored_patterns = &ignored,
        .hidden_files = &hidden,
        .symlink_behavior = .skip,
        .patterns_allocated = false,
    };

    const TestWalker = createTestWalker(shared_config);
    const test_walker = TestWalker.init(testing.allocator, Config{ .shared_config = shared_config }, &accessed_directories, tmp_dir.dir, test_dir_path);
    try test_walker.walkWithTracking(".");

    // Verify no dot directories were crawled
    for (accessed_directories.items) |accessed| {
        const basename = std.fs.path.basename(accessed);
        if (basename.len > 0 and basename[0] == '.') {
            // Found a dot directory that was crawled
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

    // Test passed
}

// Test empty vs populated directories
test "empty and populated ignored directories are not crawled" {
    var accessed_directories = std.ArrayList([]const u8).init(testing.allocator);
    defer accessed_directories.deinit();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const test_dir_path = try tmp_dir.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(test_dir_path);

    // Create empty ignored directory
    try tmp_dir.dir.makeDir("empty_ignored");

    // Create populated ignored directory with many files
    try tmp_dir.dir.makeDir("populated_ignored");
    var i: u32 = 0;
    while (i < 20) : (i += 1) {
        const filename = try std.fmt.allocPrint(testing.allocator, "populated_ignored/file_{d}.txt", .{i});
        defer testing.allocator.free(filename);
        const file = try tmp_dir.dir.createFile(filename, .{});
        file.close();
    }

    // Create subdirectories in populated ignored
    try tmp_dir.dir.makePath("populated_ignored/subdir1");
    try tmp_dir.dir.makePath("populated_ignored/subdir2");

    const ignored = [_][]const u8{ "empty_ignored", "populated_ignored" };
    const hidden = [_][]const u8{};
    
    const shared_config = SharedConfig{
        .ignored_patterns = &ignored,
        .hidden_files = &hidden,
        .symlink_behavior = .skip,
        .patterns_allocated = false,
    };

    const TestWalker = createTestWalker(shared_config);
    const test_walker = TestWalker.init(testing.allocator, Config{ .shared_config = shared_config }, &accessed_directories, tmp_dir.dir, test_dir_path);
    try test_walker.walkWithTracking(".");

    // Verify neither empty nor populated ignored dirs were crawled
    const forbidden_suffixes = [_][]const u8{
        "/empty_ignored",
        "/populated_ignored",
        "/populated_ignored/subdir1",
        "/populated_ignored/subdir2",
    };

    for (forbidden_suffixes) |suffix| {
        for (accessed_directories.items) |accessed| {
            try testing.expect(!std.mem.endsWith(u8, accessed, suffix));
        }
    }

    // Cleanup
    for (accessed_directories.items) |path| {
        testing.allocator.free(path);
    }

    // Test passed
}

// Test configuration edge cases
test "configuration fallbacks and edge cases" {
    var accessed_directories = std.ArrayList([]const u8).init(testing.allocator);
    defer accessed_directories.deinit();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const test_dir_path = try tmp_dir.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(test_dir_path);

    // Test empty configuration
    const ignored = [_][]const u8{}; // Empty
    const hidden = [_][]const u8{}; // Empty
    
    const shared_config = SharedConfig{
        .ignored_patterns = &ignored,
        .hidden_files = &hidden,
        .symlink_behavior = .skip,
        .patterns_allocated = false,
    };

    try tmp_dir.dir.makeDir("should_be_crawled");
    const file = try tmp_dir.dir.createFile("should_be_crawled/file.txt", .{});
    file.close();

    const TestWalker = createTestWalker(shared_config);
    const test_walker = TestWalker.init(testing.allocator, Config{ .shared_config = shared_config }, &accessed_directories, tmp_dir.dir, test_dir_path);
    try test_walker.walkWithTracking(".");

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

    // Test passed
}

// Test real project structure patterns
test "real project structure is handled correctly" {
    var accessed_directories = std.ArrayList([]const u8).init(testing.allocator);
    defer accessed_directories.deinit();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const test_dir_path = try tmp_dir.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(test_dir_path);

    // Simulate real project structure like our zz project
    const project_structure = [_][]const u8{
        "src",     "src/cli",     "src/tree", "src/tree/compiled", "src/tree/test",
        "zig-out", "zig-out/bin", ".git",     ".zig-cache",
    };

    for (project_structure) |path| {
        try tmp_dir.dir.makePath(path);

        // Add realistic files
        const extensions = [_][]const u8{ ".zig", ".md", ".txt" };
        for (extensions) |ext| {
            const filename = try std.fmt.allocPrint(testing.allocator, "{s}/test{s}", .{ path, ext });
            defer testing.allocator.free(filename);
            const file = try tmp_dir.dir.createFile(filename, .{});
            file.close();
        }
    }

    // Use realistic config (matches our defaults)
    const ignored = [_][]const u8{ ".git", ".zig-cache", "zig-out", "src/tree/compiled" };
    const hidden = [_][]const u8{};
    
    const shared_config = SharedConfig{
        .ignored_patterns = &ignored,
        .hidden_files = &hidden,
        .symlink_behavior = .skip,
        .patterns_allocated = false,
    };

    const TestWalker = createTestWalker(shared_config);
    const test_walker = TestWalker.init(testing.allocator, Config{ .shared_config = shared_config }, &accessed_directories, tmp_dir.dir, test_dir_path);
    try test_walker.walkWithTracking(".");

    // Verify ignored paths are not crawled
    const should_be_ignored_suffixes = [_][]const u8{
        "/.git",
        "/.zig-cache",
        "/zig-out",
        "/zig-out/bin",
        "/src/tree/compiled",
    };

    for (should_be_ignored_suffixes) |suffix| {
        for (accessed_directories.items) |accessed| {
            try testing.expect(!std.mem.endsWith(u8, accessed, suffix));
        }
    }

    // Verify allowed paths are crawled
    const should_be_crawled_suffixes = [_][]const u8{
        "/src",
        "/src/cli",
        "/src/tree",
        "/src/tree/test",
    };

    for (should_be_crawled_suffixes) |suffix| {
        var found = false;
        for (accessed_directories.items) |accessed| {
            if (std.mem.endsWith(u8, accessed, suffix)) {
                found = true;
                break;
            }
        }
        if (!found) {
            // Expected to find this path but didn't
            try testing.expect(false);
        }
    }

    // Cleanup
    for (accessed_directories.items) |path| {
        testing.allocator.free(path);
    }

    // Test passed
}

// Helper function to create test walker (reduces code duplication)
fn createTestWalker(comptime shared_config: SharedConfig) type {
    _ = shared_config; // Mark as used (comptime parameter)
    return struct {
        base_walker: Walker,
        tracked_dirs: *std.ArrayList([]const u8),
        root_dir: std.fs.Dir,
        root_path: []const u8,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator, cfg: Config, tracked_dirs: *std.ArrayList([]const u8), root_dir: std.fs.Dir, root_path: []const u8) Self {
            return Self{
                .base_walker = Walker.init(allocator, cfg),
                .tracked_dirs = tracked_dirs,
                .root_dir = root_dir,
                .root_path = root_path,
            };
        }

        pub fn walkWithTracking(self: Self, relative_path: []const u8) !void {
            mock_active = true;
            defer mock_active = false;
            
            // Free previously allocated strings
            for (self.tracked_dirs.items) |path| {
                testing.allocator.free(path);
            }
            self.tracked_dirs.clearRetainingCapacity();

            try self.walkRecursiveWithTracking(relative_path, "", true, 0);
        }

        fn walkRecursiveWithTracking(self: Self, relative_path: []const u8, prefix: []const u8, is_last: bool, current_depth: u32) !void {
            // Record directory access (store as absolute path for verification)
            const abs_path = if (std.mem.eql(u8, relative_path, "."))
                try testing.allocator.dupe(u8, self.root_path)
            else
                try std.fs.path.join(testing.allocator, &.{ self.root_path, relative_path });
            try self.tracked_dirs.append(abs_path);

            _ = prefix;
            _ = is_last; // Suppress unused warnings

            // Check depth limit
            if (self.base_walker.config.max_depth) |depth| {
                if (current_depth >= depth) return;
            }

            const dir = self.root_dir.openDir(relative_path, .{ .iterate = true }) catch return;
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

                const full_path = std.fs.path.join(self.base_walker.allocator, &.{ relative_path, dir_entry.name }) catch continue;
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
