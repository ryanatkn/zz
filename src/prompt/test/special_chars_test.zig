const std = @import("std");
const GlobExpander = @import("../glob.zig").GlobExpander;
const Config = @import("../config.zig").Config;

test "files with spaces in names" {
    const allocator = std.testing.allocator;

    // Create temp directory with files containing spaces
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.writeFile(.{ .sub_path = "file with spaces.zig", .data = "const a = 1;" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "another file.zig", .data = "const b = 2;" });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);

    var expander = GlobExpander.init(allocator);

    // Test explicit file with spaces
    const spaced_file = try std.fmt.allocPrint(allocator, "{s}/file with spaces.zig", .{tmp_path});
    defer allocator.free(spaced_file);

    var patterns = [_][]const u8{spaced_file};
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

    try std.testing.expect(results.items.len == 1);
    try std.testing.expect(results.items[0].files.items.len == 1);
    try std.testing.expect(std.mem.indexOf(u8, results.items[0].files.items[0], "file with spaces.zig") != null);
}

test "files with special characters" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create files with various special characters
    try tmp_dir.dir.writeFile(.{ .sub_path = "file[1].zig", .data = "const a = 1;" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "file(2).zig", .data = "const b = 2;" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "file-3.zig", .data = "const c = 3;" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "file_4.zig", .data = "const d = 4;" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "file.test.zig", .data = "const e = 5;" });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);

    var expander = GlobExpander.init(allocator);

    // Test glob matching with special char files
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

    // Should match all 5 files
    try std.testing.expect(results.items.len == 1);
    try std.testing.expect(results.items[0].files.items.len == 5);
}

test "unicode filenames" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create files with unicode characters
    try tmp_dir.dir.writeFile(.{ .sub_path = "файл.zig", .data = "const a = 1;" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "文件.zig", .data = "const b = 2;" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "ملف.zig", .data = "const c = 3;" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "😀.zig", .data = "const d = 4;" });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);

    var expander = GlobExpander.init(allocator);

    // Test glob with unicode files
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

    // Should match all unicode files
    try std.testing.expect(results.items.len == 1);
    try std.testing.expect(results.items[0].files.items.len == 4);
}

test "escaped characters in glob patterns" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create files that look like they have glob chars
    try tmp_dir.dir.writeFile(.{ .sub_path = "file*.zig", .data = "const a = 1;" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "file?.zig", .data = "const b = 2;" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "normal.zig", .data = "const c = 3;" });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);

    var expander = GlobExpander.init(allocator);

    // Try to match literal file with * in name
    // Note: Currently our glob doesn't support escaping, so this will be treated as glob
    const pattern = try std.fmt.allocPrint(allocator, "{s}/file*.zig", .{tmp_path});
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

    // This will be treated as a glob and match both file*.zig and file?.zig
    try std.testing.expect(results.items.len == 1);
    try std.testing.expect(results.items[0].is_glob == true);
}

test "very long filenames" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create a file with a very long name (but within filesystem limits)
    // Use a conservative length that should work on most systems
    const long_name = try allocator.alloc(u8, 100);
    defer allocator.free(long_name);

    // Fill with 'a' and add .zig extension
    @memset(long_name[0..96], 'a');
    @memcpy(long_name[96..100], ".zig");

    try tmp_dir.dir.writeFile(.{ .sub_path = long_name, .data = "const a = 1;" });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);

    var expander = GlobExpander.init(allocator);

    // Match with glob
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

    try std.testing.expect(results.items.len == 1);
    try std.testing.expect(results.items[0].files.items.len == 1);
}

test "files with newlines and tabs in names" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Most filesystems don't allow newlines in filenames, but tabs might work
    // Try creating a file with tab character
    tmp_dir.dir.writeFile(.{ .sub_path = "file\ttab.zig", .data = "const a = 1;" }) catch |err| {
        // Some filesystems might not support this
        if (err == error.InvalidFileName or err == error.BadPathName) {
            return;
        }
        return err;
    };

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);

    var expander = GlobExpander.init(allocator);

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

    // Should still match the file
    try std.testing.expect(results.items.len == 1);
    try std.testing.expect(results.items[0].files.items.len == 1);
}
