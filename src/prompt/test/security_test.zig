const std = @import("std");
const GlobExpander = @import("../glob.zig").GlobExpander;
const Config = @import("../config.zig").Config;

test "path traversal with .." {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create nested structure
    try tmp_dir.dir.makeDir("subdir");
    try tmp_dir.dir.writeFile(.{ .sub_path = "parent.zig", .data = "const a = 1;" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "subdir/child.zig", .data = "const b = 2;" });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);

    var expander = GlobExpander.init(allocator);

    // Try path traversal pattern
    const pattern = try std.fmt.allocPrint(allocator, "{s}/subdir/../*.zig", .{tmp_path});
    defer allocator.free(pattern);

    var patterns = [_][]const u8{pattern};
    var results = try expander.expandPatternsWithInfo(&patterns);
    defer {
        for (results.items) |*result| {
            for (result.files.items) |file| {
                allocator.free(file);
            }
            result.files.deinit();
        }
        results.deinit();
    }

    // Should work and find parent.zig
    try std.testing.expect(results.items.len == 1);
    try std.testing.expect(results.items[0].files.items.len == 1);
}

test "absolute paths" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.writeFile(.{ .sub_path = "test.zig", .data = "const a = 1;" });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);

    var expander = GlobExpander.init(allocator);

    // Use absolute path
    const abs_path = try std.fmt.allocPrint(allocator, "{s}/test.zig", .{tmp_path});
    defer allocator.free(abs_path);

    var patterns = [_][]const u8{abs_path};
    var results = try expander.expandPatternsWithInfo(&patterns);
    defer {
        for (results.items) |*result| {
            for (result.files.items) |file| {
                allocator.free(file);
            }
            result.files.deinit();
        }
        results.deinit();
    }

    // Should work with absolute paths
    try std.testing.expect(results.items.len == 1);
    try std.testing.expect(results.items[0].files.items.len == 1);
}

test "home directory expansion not supported" {
    const allocator = std.testing.allocator;

    var expander = GlobExpander.init(allocator);

    // Try to use ~ for home directory
    var patterns = [_][]const u8{"~/file.zig"};
    var results = try expander.expandPatternsWithInfo(&patterns);
    defer {
        for (results.items) |*result| {
            for (result.files.items) |file| {
                allocator.free(file);
            }
            result.files.deinit();
        }
        results.deinit();
    }

    // ~ is not expanded, treated as literal
    try std.testing.expect(results.items.len == 1);
    try std.testing.expect(results.items[0].files.items.len == 0);
    try std.testing.expect(results.items[0].is_glob == false);
}

test "non-existent directory handling" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);

    var expander = GlobExpander.init(allocator);

    // Try to access files in non-existent directory
    const pattern = try std.fmt.allocPrint(allocator, "{s}/nonexistent/*.zig", .{tmp_path});
    defer allocator.free(pattern);

    var patterns = [_][]const u8{pattern};
    var results = try expander.expandPatternsWithInfo(&patterns);
    defer {
        for (results.items) |*result| {
            for (result.files.items) |file| {
                allocator.free(file);
            }
            result.files.deinit();
        }
        results.deinit();
    }

    // Should handle non-existent directory gracefully
    try std.testing.expect(results.items.len == 1);
    try std.testing.expect(results.items[0].files.items.len == 0);
}

test "attempt to read system files" {
    const allocator = std.testing.allocator;

    var expander = GlobExpander.init(allocator);

    // Try to access system files (these patterns should be handled safely)
    const patterns = [_][]const u8{
        "/etc/passwd",
        "/etc/shadow",
        "/dev/null",
        "/proc/self/mem",
    };

    for (patterns) |pattern| {
        var single_pattern = [_][]const u8{pattern};
        var results = try expander.expandPatternsWithInfo(&single_pattern);
        defer {
            for (results.items) |*result| {
                for (result.files.items) |file| {
                    allocator.free(file);
                }
                result.files.deinit();
            }
            results.deinit();
        }

        // Should handle system files (either find them or not, but not crash)
        try std.testing.expect(results.items.len == 1);
        // Results depend on system and permissions
    }
}

test "relative path outside project" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.makeDir("project");
    try tmp_dir.dir.writeFile(.{ .sub_path = "outside.zig", .data = "const a = 1;" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "project/inside.zig", .data = "const b = 2;" });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const project_path = try tmp_dir.dir.realpath("project", &path_buf);

    // Change to project directory context
    var project_dir = try std.fs.openDirAbsolute(project_path, .{});
    defer project_dir.close();

    var expander = GlobExpander.init(allocator);

    // Try to access file outside project with ..
    var patterns = [_][]const u8{"../outside.zig"};
    var results = try expander.expandPatternsWithInfo(&patterns);
    defer {
        for (results.items) |*result| {
            for (result.files.items) |file| {
                allocator.free(file);
            }
            result.files.deinit();
        }
        results.deinit();
    }

    // Should work (no artificial restrictions)
    try std.testing.expect(results.items.len == 1);
}

test "extremely deep path traversal" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create a file
    try tmp_dir.dir.writeFile(.{ .sub_path = "target.zig", .data = "const a = 1;" });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);

    var expander = GlobExpander.init(allocator);

    // Try extremely deep path traversal that goes nowhere
    const pattern = try std.fmt.allocPrint(allocator, "{s}/a/b/c/../../../../../../../../../../*.zig", .{tmp_path});
    defer allocator.free(pattern);

    var patterns = [_][]const u8{pattern};
    var results = try expander.expandPatternsWithInfo(&patterns);
    defer {
        for (results.items) |*result| {
            for (result.files.items) |file| {
                allocator.free(file);
            }
            result.files.deinit();
        }
        results.deinit();
    }

    // Should handle this gracefully
    try std.testing.expect(results.items.len == 1);
}

test "empty path components" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.writeFile(.{ .sub_path = "test.zig", .data = "const a = 1;" });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);

    var expander = GlobExpander.init(allocator);

    // Path with empty components (double slashes)
    const pattern = try std.fmt.allocPrint(allocator, "{s}//test.zig", .{tmp_path});
    defer allocator.free(pattern);

    var patterns = [_][]const u8{pattern};
    var results = try expander.expandPatternsWithInfo(&patterns);
    defer {
        for (results.items) |*result| {
            for (result.files.items) |file| {
                allocator.free(file);
            }
            result.files.deinit();
        }
        results.deinit();
    }

    // Should normalize and work
    try std.testing.expect(results.items.len == 1);
}
