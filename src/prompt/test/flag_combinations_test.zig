const std = @import("std");
const Config = @import("../config.zig").Config;
const prompt_main = @import("../main.zig");

test "multiple prepend flags - last wins" {
    const allocator = std.testing.allocator;

    var args = [_][:0]const u8{ "zz", "prompt", "--prepend=First", "--prepend=Second", "--prepend=Last", "file.zig" };

    var config = try Config.fromArgs(allocator, &args);
    defer config.deinit();

    // Last prepend should win
    try std.testing.expect(config.prepend_text != null);
    try std.testing.expectEqualStrings("Last", config.prepend_text.?);
}

test "multiple append flags - last wins" {
    const allocator = std.testing.allocator;

    var args = [_][:0]const u8{ "zz", "prompt", "--append=First", "--append=Second", "--append=Last", "file.zig" };

    var config = try Config.fromArgs(allocator, &args);
    defer config.deinit();

    // Last append should win
    try std.testing.expect(config.append_text != null);
    try std.testing.expectEqualStrings("Last", config.append_text.?);
}

test "both allow flags together" {
    const allocator = std.testing.allocator;

    var args = [_][:0]const u8{ "zz", "prompt", "--allow-empty-glob", "--allow-missing", "*.nonexistent", "missing.zig" };

    var config = try Config.fromArgs(allocator, &args);
    defer config.deinit();

    try std.testing.expect(config.allow_empty_glob == true);
    try std.testing.expect(config.allow_missing == true);

    var patterns = try config.getFilePatterns(&args);
    defer patterns.deinit();

    try std.testing.expect(patterns.items.len == 2);
}

test "flags with empty values" {
    const allocator = std.testing.allocator;

    var args = [_][:0]const u8{ "zz", "prompt", "--prepend=", "--append=", "file.zig" };

    var config = try Config.fromArgs(allocator, &args);
    defer config.deinit();

    // Empty strings are valid
    try std.testing.expect(config.prepend_text != null);
    try std.testing.expect(config.append_text != null);
    try std.testing.expectEqualStrings("", config.prepend_text.?);
    try std.testing.expectEqualStrings("", config.append_text.?);
}

test "flags interspersed with files" {
    const allocator = std.testing.allocator;

    var args = [_][:0]const u8{ "zz", "prompt", "file1.zig", "--prepend=Text", "file2.zig", "--allow-missing", "file3.zig", "--append=More", "file4.zig" };

    var config = try Config.fromArgs(allocator, &args);
    defer config.deinit();

    // All flags should be parsed
    try std.testing.expect(config.prepend_text != null);
    try std.testing.expect(config.append_text != null);
    try std.testing.expect(config.allow_missing == true);

    // All files should be collected
    var patterns = try config.getFilePatterns(&args);
    defer patterns.deinit();

    try std.testing.expect(patterns.items.len == 4);
    try std.testing.expectEqualStrings("file1.zig", patterns.items[0]);
    try std.testing.expectEqualStrings("file2.zig", patterns.items[1]);
    try std.testing.expectEqualStrings("file3.zig", patterns.items[2]);
    try std.testing.expectEqualStrings("file4.zig", patterns.items[3]);
}

test "only text flags no files" {
    const allocator = std.testing.allocator;

    var args = [_][:0]const u8{ "zz", "prompt", "--prepend=Header", "--append=Footer" };

    var config = try Config.fromArgs(allocator, &args);
    defer config.deinit();

    // Should not error since we have text flags
    var patterns = try config.getFilePatterns(&args);
    defer patterns.deinit();

    try std.testing.expect(patterns.items.len == 0);
    try std.testing.expect(config.prepend_text != null);
    try std.testing.expect(config.append_text != null);
}

test "conflicting patterns same files" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create test files
    try tmp_dir.dir.writeFile(.{ .sub_path = "test.zig", .data = "const a = 1;" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "main.zig", .data = "const b = 2;" });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);

    // Patterns that will match overlapping files
    var args_buf: [10][:0]const u8 = undefined;
    args_buf[0] = "zz";
    args_buf[1] = "prompt";

    const pattern1 = try std.fmt.allocPrintZ(allocator, "{s}/*.zig", .{tmp_path});
    defer allocator.free(pattern1);
    args_buf[2] = pattern1;

    const pattern2 = try std.fmt.allocPrintZ(allocator, "{s}/test.zig", .{tmp_path});
    defer allocator.free(pattern2);
    args_buf[3] = pattern2;

    const pattern3 = try std.fmt.allocPrintZ(allocator, "{s}/main.zig", .{tmp_path});
    defer allocator.free(pattern3);
    args_buf[4] = pattern3;

    const args = args_buf[0..5];

    var config = try Config.fromArgs(allocator, args);
    defer config.deinit();

    var patterns = try config.getFilePatterns(args);
    defer patterns.deinit();

    // Should have all 3 patterns (deduplication happens later)
    try std.testing.expect(patterns.items.len == 3);
}

test "allow-empty-glob with glob and explicit file" {
    const allocator = std.testing.allocator;

    var args = [_][:0]const u8{
        "zz",                 "prompt",
        "--allow-empty-glob",
        "*.nonexistent", // Glob that matches nothing
        "/missing/file.zig", // Explicit missing file
    };

    var config = try Config.fromArgs(allocator, &args);
    defer config.deinit();

    // allow-empty-glob only affects globs, not explicit files
    try std.testing.expect(config.allow_empty_glob == true);
    try std.testing.expect(config.allow_missing == false);
}

test "unicode in flag values" {
    const allocator = std.testing.allocator;

    var args = [_][:0]const u8{ "zz", "prompt", "--prepend=Hello 世界 🌍", "--append=مرحبا мир", "file.zig" };

    var config = try Config.fromArgs(allocator, &args);
    defer config.deinit();

    try std.testing.expect(config.prepend_text != null);
    try std.testing.expect(config.append_text != null);
    try std.testing.expectEqualStrings("Hello 世界 🌍", config.prepend_text.?);
    try std.testing.expectEqualStrings("مرحبا мир", config.append_text.?);
}

test "very long flag values" {
    const allocator = std.testing.allocator;

    // Create a very long string for flag value
    const long_text = try allocator.alloc(u8, 1000);
    defer allocator.free(long_text);
    @memset(long_text, 'x');

    const prepend_arg = try std.fmt.allocPrintZ(allocator, "--prepend={s}", .{long_text});
    defer allocator.free(prepend_arg);

    var args = [_][:0]const u8{ "zz", "prompt", prepend_arg, "file.zig" };

    var config = try Config.fromArgs(allocator, &args);
    defer config.deinit();

    try std.testing.expect(config.prepend_text != null);
    try std.testing.expect(config.prepend_text.?.len == 1000);
}
