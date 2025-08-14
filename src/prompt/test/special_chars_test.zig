const std = @import("std");
const test_helpers = @import("../../lib/test/helpers.zig");
const GlobExpander = @import("../glob.zig").GlobExpander;
const Config = @import("../config.zig").Config;

test "files with spaces in names" {
    const allocator = std.testing.allocator;

    var ctx = test_helpers.MockTestContext.init(allocator);
    defer ctx.deinit();

    // Create files containing spaces
    try ctx.addFile("file with spaces.zig", "const a = 1;");
    try ctx.addFile("another file.zig", "const b = 2;");

    const expander = test_helpers.createGlobExpander(allocator, ctx.filesystem);

    // Test explicit file with spaces
    const spaced_file = "file with spaces.zig";
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
    try std.testing.expectEqualStrings("file with spaces.zig", results.items[0].files.items[0]);
}

test "files with special characters" {
    const allocator = std.testing.allocator;

    var ctx = test_helpers.MockTestContext.init(allocator);
    defer ctx.deinit();

    // Create files with various special characters
    try ctx.addFile("file[1].zig", "const a = 1;");
    try ctx.addFile("file(2).zig", "const b = 2;");
    try ctx.addFile("file-3.zig", "const c = 3;");
    try ctx.addFile("file_4.zig", "const d = 4;");
    try ctx.addFile("file.test.zig", "const e = 5;");

    const expander = test_helpers.createGlobExpander(allocator, ctx.filesystem);

    // Test glob matching with special char files
    const pattern = "*.zig";
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

    var ctx = test_helpers.MockTestContext.init(allocator);
    defer ctx.deinit();

    // Create files with unicode characters
    try ctx.addFile("файл.zig", "const a = 1;");
    try ctx.addFile("文件.zig", "const b = 2;");
    try ctx.addFile("ملف.zig", "const c = 3;");
    try ctx.addFile("😀.zig", "const d = 4;");

    const expander = test_helpers.createGlobExpander(allocator, ctx.filesystem);

    // Test glob with unicode files
    const pattern = "*.zig";
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

    var ctx = test_helpers.MockTestContext.init(allocator);
    defer ctx.deinit();

    // Create files that look like they have glob chars
    try ctx.addFile("file*.zig", "const a = 1;");
    try ctx.addFile("file?.zig", "const b = 2;");
    try ctx.addFile("normal.zig", "const c = 3;");

    const expander = test_helpers.createGlobExpander(allocator, ctx.filesystem);

    // Try to match literal file with * in name
    // Note: Currently our glob doesn't support escaping, so this will be treated as glob
    const pattern = "file*.zig";
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

    var ctx = test_helpers.MockTestContext.init(allocator);
    defer ctx.deinit();

    // Create a file with a very long name (but within filesystem limits)
    // Use a conservative length that should work on most systems
    const long_name = try allocator.alloc(u8, 100);
    defer allocator.free(long_name);

    // Fill with 'a' and add .zig extension
    @memset(long_name[0..96], 'a');
    @memcpy(long_name[96..100], ".zig");

    try ctx.addFile(long_name, "const a = 1;");

    const expander = test_helpers.createGlobExpander(allocator, ctx.filesystem);

    // Match with glob
    const pattern = "*.zig";
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

    var ctx = test_helpers.MockTestContext.init(allocator);
    defer ctx.deinit();

    // Mock filesystem can handle tab characters in names
    try ctx.addFile("file\ttab.zig", "const a = 1;");

    const expander = test_helpers.createGlobExpander(allocator, ctx.filesystem);

    const pattern = "*.zig";
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
