const std = @import("std");
const testing = std.testing;
const test_helpers = @import("../../test_helpers.zig");
const Config = @import("../config.zig").Config;
const GlobExpander = @import("../glob.zig").GlobExpander;
const SharedConfig = @import("../../config.zig").SharedConfig;
const RealFilesystem = @import("../../filesystem.zig").RealFilesystem;
const prompt_main = @import("../main.zig");

test "directory argument - basic functionality" {
    const allocator = testing.allocator;

    // Create temp directory for test
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create test files in directory
    try tmp_dir.dir.writeFile(.{ .sub_path = "test1.zig", .data = "const a = 1;" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "test2.zig", .data = "const b = 2;" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "README.md", .data = "# Test" });

    // Get the temp directory path
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);

    // Test directory expansion
    const filesystem = RealFilesystem.init();
    
    const expander = test_helpers.createGlobExpander(allocator, filesystem);
    var patterns = [_][]const u8{tmp_path};
    var results = try expander.expandPatternsWithInfo(&patterns);
    defer {
        for (results.items) |*result| {
            for (result.files.items) |path| {
                allocator.free(path);
            }
            result.files.deinit();
        }
        results.deinit();
    }

    // Should find all 3 files
    try testing.expect(results.items.len == 1);
    try testing.expect(results.items[0].files.items.len == 3);
    try testing.expect(results.items[0].is_glob == false); // Directory is not a glob pattern

    // Check that we found the expected files
    var found_test1 = false;
    var found_test2 = false;
    var found_readme = false;

    for (results.items[0].files.items) |file| {
        if (std.mem.endsWith(u8, file, "test1.zig")) found_test1 = true;
        if (std.mem.endsWith(u8, file, "test2.zig")) found_test2 = true;
        if (std.mem.endsWith(u8, file, "README.md")) found_readme = true;
    }

    try testing.expect(found_test1);
    try testing.expect(found_test2);
    try testing.expect(found_readme);
}

test "directory argument - nested structure" {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create nested directory structure
    try tmp_dir.dir.makeDir("src");
    try tmp_dir.dir.makeDir("src/cli");
    try tmp_dir.dir.writeFile(.{ .sub_path = "main.zig", .data = "const main = 1;" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "src/lib.zig", .data = "const lib = 1;" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "src/cli/args.zig", .data = "const args = 1;" });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);

    const filesystem = RealFilesystem.init();
    
    const expander = test_helpers.createGlobExpander(allocator, filesystem);
    var patterns = [_][]const u8{tmp_path};
    var results = try expander.expandPatternsWithInfo(&patterns);
    defer {
        for (results.items) |*result| {
            for (result.files.items) |path| {
                allocator.free(path);
            }
            result.files.deinit();
        }
        results.deinit();
    }

    // Should find all 3 files recursively
    try testing.expect(results.items[0].files.items.len == 3);

    var found_main = false;
    var found_lib = false;
    var found_args = false;

    for (results.items[0].files.items) |file| {
        if (std.mem.endsWith(u8, file, "main.zig")) found_main = true;
        if (std.mem.endsWith(u8, file, "lib.zig")) found_lib = true;
        if (std.mem.endsWith(u8, file, "args.zig")) found_args = true;
    }

    try testing.expect(found_main);
    try testing.expect(found_lib);
    try testing.expect(found_args);
}

test "directory argument - with ignore patterns" {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create files, including ones that should be ignored
    try tmp_dir.dir.makeDir("node_modules");
    try tmp_dir.dir.writeFile(.{ .sub_path = "main.zig", .data = "const main = 1;" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "node_modules/package.json", .data = "{}" });
    try tmp_dir.dir.writeFile(.{ .sub_path = ".hidden", .data = "hidden" });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);

    const filesystem = RealFilesystem.init();
    
    // Custom configuration with ignore patterns for this test
    const expander = GlobExpander{
        .allocator = allocator,
        .filesystem = filesystem,
        .config = SharedConfig{
            .ignored_patterns = &[_][]const u8{ "node_modules", ".git" }, // Include node_modules
            .hidden_files = &[_][]const u8{ ".hidden" }, // Include .hidden files
            .gitignore_patterns = &[_][]const u8{},
            .symlink_behavior = .skip,
            .respect_gitignore = false, // Don't use gitignore in tests
            .patterns_allocated = false,
        },
    };
    var patterns = [_][]const u8{tmp_path};
    var results = try expander.expandPatternsWithInfo(&patterns);
    defer {
        for (results.items) |*result| {
            for (result.files.items) |path| {
                allocator.free(path);
            }
            result.files.deinit();
        }
        results.deinit();
    }

    // Should find only main.zig (node_modules and hidden files should be ignored)
    try testing.expect(results.items[0].files.items.len == 1);
    try testing.expect(std.mem.endsWith(u8, results.items[0].files.items[0], "main.zig"));
}

test "directory argument - empty directory" {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Don't create any files, leave directory empty
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);

    const filesystem = RealFilesystem.init();
    
    const expander = test_helpers.createGlobExpander(allocator, filesystem);
    var patterns = [_][]const u8{tmp_path};
    var results = try expander.expandPatternsWithInfo(&patterns);
    defer {
        for (results.items) |*result| {
            for (result.files.items) |path| {
                allocator.free(path);
            }
            result.files.deinit();
        }
        results.deinit();
    }

    // Empty directory should return no files
    try testing.expect(results.items[0].files.items.len == 0);
}

test "directory argument - mixed with files" {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create directory structure
    try tmp_dir.dir.makeDir("subdir");
    try tmp_dir.dir.writeFile(.{ .sub_path = "root.zig", .data = "const root = 1;" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "subdir/sub.zig", .data = "const sub = 1;" });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);
    
    // Create paths for individual file and subdirectory
    const root_file = try std.fmt.allocPrint(allocator, "{s}/root.zig", .{tmp_path});
    defer allocator.free(root_file);
    const subdir_path = try std.fmt.allocPrint(allocator, "{s}/subdir", .{tmp_path});
    defer allocator.free(subdir_path);

    // Test mixing explicit file and directory
    const filesystem = RealFilesystem.init();
    
    const expander = test_helpers.createGlobExpander(allocator, filesystem);
    var patterns = [_][]const u8{ root_file, subdir_path };
    var results = try expander.expandPatternsWithInfo(&patterns);
    defer {
        for (results.items) |*result| {
            for (result.files.items) |path| {
                allocator.free(path);
            }
            result.files.deinit();
        }
        results.deinit();
    }

    // Should have 2 pattern results
    try testing.expect(results.items.len == 2);
    
    // First pattern (explicit file) should have 1 file
    try testing.expect(results.items[0].files.items.len == 1);
    try testing.expect(std.mem.endsWith(u8, results.items[0].files.items[0], "root.zig"));
    
    // Second pattern (directory) should have 1 file
    try testing.expect(results.items[1].files.items.len == 1);
    try testing.expect(std.mem.endsWith(u8, results.items[1].files.items[0], "sub.zig"));
}

test "directory argument - hidden files handling" {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create regular and hidden files
    try tmp_dir.dir.writeFile(.{ .sub_path = "visible.zig", .data = "const visible = 1;" });
    try tmp_dir.dir.writeFile(.{ .sub_path = ".hidden.zig", .data = "const hidden = 1;" });
    try tmp_dir.dir.writeFile(.{ .sub_path = ".env", .data = "SECRET=value" });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);

    const filesystem = RealFilesystem.init();
    
    // Custom configuration with hidden files for this test
    const expander = GlobExpander{
        .allocator = allocator,
        .filesystem = filesystem,
        .config = SharedConfig{
            .ignored_patterns = &[_][]const u8{}, // Empty ignore patterns
            .hidden_files = &[_][]const u8{ ".hidden.zig", ".env" }, // Hide specific files
            .gitignore_patterns = &[_][]const u8{},
            .symlink_behavior = .skip,
            .respect_gitignore = false, // Don't use gitignore in tests
            .patterns_allocated = false,
        },
    };
    var patterns = [_][]const u8{tmp_path};
    var results = try expander.expandPatternsWithInfo(&patterns);
    defer {
        for (results.items) |*result| {
            for (result.files.items) |path| {
                allocator.free(path);
            }
            result.files.deinit();
        }
        results.deinit();
    }

    // Should only find visible.zig (hidden files are skipped by default)
    try testing.expect(results.items[0].files.items.len == 1);
    try testing.expect(std.mem.endsWith(u8, results.items[0].files.items[0], "visible.zig"));

    // Verify hidden files are not included
    for (results.items[0].files.items) |file| {
        try testing.expect(!std.mem.endsWith(u8, file, ".hidden.zig"));
        try testing.expect(!std.mem.endsWith(u8, file, ".env"));
    }
}

test "directory vs glob pattern behavior" {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create test files
    try tmp_dir.dir.writeFile(.{ .sub_path = "test1.zig", .data = "const a = 1;" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "test2.zig", .data = "const b = 2;" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "README.md", .data = "# Test" });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);

    const filesystem = RealFilesystem.init();
    
    const expander = test_helpers.createGlobExpander(allocator, filesystem);
    
    // Test directory (should get all files)
    var dir_patterns = [_][]const u8{tmp_path};
    var dir_results = try expander.expandPatternsWithInfo(&dir_patterns);
    defer {
        for (dir_results.items) |*result| {
            for (result.files.items) |path| {
                allocator.free(path);
            }
            result.files.deinit();
        }
        dir_results.deinit();
    }

    // Test glob pattern (should get only .zig files)
    const glob_pattern = try std.fmt.allocPrint(allocator, "{s}/*.zig", .{tmp_path});
    defer allocator.free(glob_pattern);
    var glob_patterns = [_][]const u8{glob_pattern};
    var glob_results = try expander.expandPatternsWithInfo(&glob_patterns);
    defer {
        for (glob_results.items) |*result| {
            for (result.files.items) |path| {
                allocator.free(path);
            }
            result.files.deinit();
        }
        glob_results.deinit();
    }

    // Directory should find all 3 files
    try testing.expect(dir_results.items[0].files.items.len == 3);
    try testing.expect(dir_results.items[0].is_glob == false);

    // Glob should find only 2 .zig files
    try testing.expect(glob_results.items[0].files.items.len == 2);
    try testing.expect(glob_results.items[0].is_glob == true);

    // Verify glob only got .zig files
    for (glob_results.items[0].files.items) |file| {
        try testing.expect(std.mem.endsWith(u8, file, ".zig"));
    }
}