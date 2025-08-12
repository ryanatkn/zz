const std = @import("std");
const Config = @import("../config.zig").Config;
const GlobExpander = @import("../glob.zig").GlobExpander;
const prompt_main = @import("../main.zig");

test "empty input scenarios - no files specified" {
    const allocator = std.testing.allocator;

    // Test with no arguments at all (should error)
    var args_empty = [_][:0]const u8{ "zz", "prompt" };
    var config_empty = try Config.fromArgs(allocator, &args_empty);
    defer config_empty.deinit();

    // Should return error when no files and no text flags
    const result = config_empty.getFilePatterns(&args_empty);
    try std.testing.expectError(error.NoInputFiles, result);
}

test "empty input scenarios - only prepend text" {
    const allocator = std.testing.allocator;

    // Test with only prepend text (should be valid)
    var args = [_][:0]const u8{ "zz", "prompt", "--prepend=Some text" };
    var config = try Config.fromArgs(allocator, &args);
    defer config.deinit();

    var patterns = try config.getFilePatterns(&args);
    defer patterns.deinit();

    // Should have no patterns but not error
    try std.testing.expect(patterns.items.len == 0);
    try std.testing.expect(config.prepend_text != null);
}

test "empty input scenarios - only append text" {
    const allocator = std.testing.allocator;

    // Test with only append text (should be valid)
    var args = [_][:0]const u8{ "zz", "prompt", "--append=Some text" };
    var config = try Config.fromArgs(allocator, &args);
    defer config.deinit();

    var patterns = try config.getFilePatterns(&args);
    defer patterns.deinit();

    // Should have no patterns but not error
    try std.testing.expect(patterns.items.len == 0);
    try std.testing.expect(config.append_text != null);
}

test "empty input scenarios - empty string pattern" {
    const allocator = std.testing.allocator;

    // Test with empty string as pattern
    var args = [_][:0]const u8{ "zz", "prompt", "" };
    var config = try Config.fromArgs(allocator, &args);
    defer config.deinit();

    var patterns = try config.getFilePatterns(&args);
    defer patterns.deinit();

    // Empty string should be treated as a pattern (though it won't match anything)
    try std.testing.expect(patterns.items.len == 1);
    try std.testing.expectEqualStrings("", patterns.items[0]);
}

test "empty text flags" {
    const allocator = std.testing.allocator;

    // Test with empty prepend and append
    var args = [_][:0]const u8{ "zz", "prompt", "--prepend=", "--append=", "test.zig" };
    var config = try Config.fromArgs(allocator, &args);
    defer config.deinit();

    // Empty strings should still be captured
    try std.testing.expect(config.prepend_text != null);
    try std.testing.expect(config.append_text != null);
    try std.testing.expectEqualStrings("", config.prepend_text.?);
    try std.testing.expectEqualStrings("", config.append_text.?);
}

test "glob with no matches in empty directory" {
    const allocator = std.testing.allocator;

    // Create a temporary empty directory
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);

    var expander = GlobExpander.init(allocator);

    // Try to match files in empty directory
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

    // Should have one result with no files
    try std.testing.expect(results.items.len == 1);
    try std.testing.expect(results.items[0].files.items.len == 0);
    try std.testing.expect(results.items[0].is_glob == true);
}

test "directory as input argument - empty directory" {
    const allocator = std.testing.allocator;

    // Create temp directory
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.makeDir("subdir");

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);

    var expander = GlobExpander.init(allocator);

    // Test directory support with empty directory
    const dir_path = try std.fmt.allocPrint(allocator, "{s}/subdir", .{tmp_path});
    defer allocator.free(dir_path);

    var patterns = [_][]const u8{dir_path};
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

    // Directory should now be supported - empty directory returns no files
    try std.testing.expect(results.items.len == 1);
    try std.testing.expect(results.items[0].files.items.len == 0);  // Empty directory
    try std.testing.expect(results.items[0].is_glob == false);
}

test "multiple empty glob patterns" {
    const allocator = std.testing.allocator;

    var expander = GlobExpander.init(allocator);

    // Multiple patterns that match nothing
    var patterns = [_][]const u8{
        "*.nonexistent1",
        "*.nonexistent2",
        "*.nonexistent3",
    };

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

    // All should return empty
    try std.testing.expect(results.items.len == 3);
    for (results.items) |result| {
        try std.testing.expect(result.files.items.len == 0);
        try std.testing.expect(result.is_glob == true);
    }
}
