const std = @import("std");
const GlobExpander = @import("../glob.zig").GlobExpander;

test "symlink to file" {
    
    const allocator = std.testing.allocator;
    
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    // Create a regular file
    try tmp_dir.dir.writeFile(.{ .sub_path = "original.zig", .data = "const a = 1;" });
    
    // Create symlink to the file
    try tmp_dir.dir.symLink("original.zig", "link.zig", .{});
    
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);
    
    var expander = GlobExpander.init(allocator);
    
    // Test that glob finds both the original and the link
    const pattern = try std.fmt.allocPrint(allocator, "{s}/*.zig", .{tmp_path});
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
    
    // Should find both files
    try std.testing.expect(results.items.len == 1);
    try std.testing.expect(results.items[0].files.items.len == 2);
}

test "symlink to directory" {
    
    const allocator = std.testing.allocator;
    
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    // Create a directory with files
    try tmp_dir.dir.makeDir("realdir");
    try tmp_dir.dir.writeFile(.{ .sub_path = "realdir/file1.zig", .data = "const a = 1;" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "realdir/file2.zig", .data = "const b = 2;" });
    
    // Create symlink to directory
    try tmp_dir.dir.symLink("realdir", "linkdir", .{ .is_directory = true });
    
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);
    
    var expander = GlobExpander.init(allocator);
    
    // Test recursive pattern through symlinked directory
    const pattern = try std.fmt.allocPrint(allocator, "{s}/**/*.zig", .{tmp_path});
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
    
    // Should find files in both real and linked directories
    try std.testing.expect(results.items.len == 1);
    // Files might be found through both paths
    try std.testing.expect(results.items[0].files.items.len >= 2);
}

test "broken symlink" {
    
    const allocator = std.testing.allocator;
    
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    // Create a symlink to non-existent file
    try tmp_dir.dir.symLink("nonexistent.zig", "broken_link.zig", .{});
    
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);
    
    var expander = GlobExpander.init(allocator);
    
    // Test explicit broken symlink
    const broken_path = try std.fmt.allocPrint(allocator, "{s}/broken_link.zig", .{tmp_path});
    defer allocator.free(broken_path);
    
    var patterns = [_][]const u8{broken_path};
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
    
    // Broken symlink should not be included when accessed explicitly
    try std.testing.expect(results.items.len == 1);
    try std.testing.expect(results.items[0].files.items.len == 0);
}

test "circular symlinks" {
    
    const allocator = std.testing.allocator;
    
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    // Create circular symlinks
    try tmp_dir.dir.makeDir("dir1");
    try tmp_dir.dir.makeDir("dir2");
    try tmp_dir.dir.symLink("../dir2", "dir1/link_to_dir2", .{ .is_directory = true });
    try tmp_dir.dir.symLink("../dir1", "dir2/link_to_dir1", .{ .is_directory = true });
    
    // Add a file to find
    try tmp_dir.dir.writeFile(.{ .sub_path = "dir1/file.zig", .data = "const a = 1;" });
    
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);
    
    var expander = GlobExpander.init(allocator);
    
    // This should not cause infinite recursion
    const pattern = try std.fmt.allocPrint(allocator, "{s}/**/*.zig", .{tmp_path});
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
    
    // Should find the file without hanging
    try std.testing.expect(results.items.len == 1);
    try std.testing.expect(results.items[0].files.items.len >= 1);
}


test "hidden files and directories" {
    const allocator = std.testing.allocator;
    
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    // Create hidden files and directories
    try tmp_dir.dir.writeFile(.{ .sub_path = ".hidden.zig", .data = "const a = 1;" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "visible.zig", .data = "const b = 2;" });
    try tmp_dir.dir.makeDir(".hiddendir");
    try tmp_dir.dir.writeFile(.{ .sub_path = ".hiddendir/file.zig", .data = "const c = 3;" });
    
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);
    
    var expander = GlobExpander.init(allocator);
    
    // Test that * doesn't match hidden files by default
    const pattern1 = try std.fmt.allocPrint(allocator, "{s}/*.zig", .{tmp_path});
    defer allocator.free(pattern1);
    
    var patterns1 = [_][]const u8{pattern1};
    var results1 = try expander.expandPatternsWithInfo(&patterns1);
    defer {
        for (results1.items) |*result| {
            for (result.files.items) |file| {
                allocator.free(file);
            }
            result.files.deinit();
        }
        results1.deinit();
    }
    
    // Should only find visible.zig
    try std.testing.expect(results1.items.len == 1);
    try std.testing.expect(results1.items[0].files.items.len == 1);
    try std.testing.expect(std.mem.indexOf(u8, results1.items[0].files.items[0], "visible.zig") != null);
    
    // Test recursive pattern skips hidden directories
    const pattern2 = try std.fmt.allocPrint(allocator, "{s}/**/*.zig", .{tmp_path});
    defer allocator.free(pattern2);
    
    var patterns2 = [_][]const u8{pattern2};
    var results2 = try expander.expandPatternsWithInfo(&patterns2);
    defer {
        for (results2.items) |*result| {
            for (result.files.items) |file| {
                allocator.free(file);
            }
            result.files.deinit();
        }
        results2.deinit();
    }
    
    // Should only find visible.zig (hidden dir is skipped)
    try std.testing.expect(results2.items.len == 1);
    try std.testing.expect(results2.items[0].files.items.len == 1);
}