const std = @import("std");
const testing = std.testing;
const test_helpers = @import("../../test_helpers.zig");
const GlobExpander = @import("../glob.zig").GlobExpander;

test "nested braces with real files" {
    const allocator = testing.allocator;

    var ctx = test_helpers.MockTestContext.init(allocator);
    defer ctx.deinit();

    // Create test files
    try ctx.addFile("test.zig", "// Zig file\n");
    try ctx.addFile("test.md", "# Markdown file\n");
    try ctx.addFile("test.txt", "Text file\n");
    try ctx.addFile("test.rs", "// Rust file\n");

    const expander = test_helpers.createGlobExpander(allocator, ctx.filesystem);

    // Test nested braces pattern: *.{zig,{md,txt}}
    // Should match: test.zig, test.md, test.txt
    // Should NOT match: test.rs
    const pattern = "*.{zig,{md,txt}}";
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

    // Should find exactly 3 files
    try testing.expect(results.items.len == 1);
    try testing.expectEqual(@as(usize, 3), results.items[0].files.items.len);

    // Check that we got the right files
    var found_zig = false;
    var found_md = false;
    var found_txt = false;

    for (results.items[0].files.items) |file| {
        if (std.mem.endsWith(u8, file, "test.zig")) found_zig = true;
        if (std.mem.endsWith(u8, file, "test.md")) found_md = true;
        if (std.mem.endsWith(u8, file, "test.txt")) found_txt = true;

        // Should NOT find test.rs
        try testing.expect(!std.mem.endsWith(u8, file, "test.rs"));
    }

    try testing.expect(found_zig);
    try testing.expect(found_md);
    try testing.expect(found_txt);

}

test "character classes with real files" {
    const allocator = testing.allocator;

    var ctx = test_helpers.MockTestContext.init(allocator);
    defer ctx.deinit();

    // Create numbered log files
    try ctx.addFile("log0.txt", "Log 0\n");
    try ctx.addFile("log5.txt", "Log 5\n");
    try ctx.addFile("log9.txt", "Log 9\n");
    try ctx.addFile("loga.txt", "Log A\n");
    try ctx.addFile("logZ.txt", "Log Z\n");

    const expander = test_helpers.createGlobExpander(allocator, ctx.filesystem);

    // Test character class pattern: log[0-9].txt
    // Should match: log0.txt, log5.txt, log9.txt
    // Should NOT match: loga.txt, logZ.txt
    const pattern = "log[0-9].txt";
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

    // Should find exactly 3 files
    try testing.expect(results.items.len == 1);
    try testing.expectEqual(@as(usize, 3), results.items[0].files.items.len);

    // Verify we only got numeric logs
    for (results.items[0].files.items) |file| {
        try testing.expect(std.mem.endsWith(u8, file, "log0.txt") or
            std.mem.endsWith(u8, file, "log5.txt") or
            std.mem.endsWith(u8, file, "log9.txt"));
    }

}

test "escape sequences with real files" {
    const allocator = testing.allocator;

    var ctx = test_helpers.MockTestContext.init(allocator);
    defer ctx.deinit();

    // Create files with special characters in names
    try ctx.addFile("file*.txt", "File with asterisk\n");
    try ctx.addFile("file?.txt", "File with question\n");
    try ctx.addFile("file[1].txt", "File with brackets\n");
    try ctx.addFile("file123.txt", "Normal file\n");

    const expander = test_helpers.createGlobExpander(allocator, ctx.filesystem);

    // Test escaped asterisk: file\*.txt
    // Should match only: file*.txt
    const pattern1 = "file\\*.txt";
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

    try testing.expectEqual(@as(usize, 1), results1.items[0].files.items.len);
    try testing.expect(std.mem.endsWith(u8, results1.items[0].files.items[0], "file*.txt"));

    // Test escaped brackets: file\[1\].txt
    // Should match only: file[1].txt
    const pattern2 = "file\\[1\\].txt";
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

    try testing.expectEqual(@as(usize, 1), results2.items[0].files.items.len);
    try testing.expect(std.mem.endsWith(u8, results2.items[0].files.items[0], "file[1].txt"));

}
