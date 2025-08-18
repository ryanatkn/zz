const std = @import("std");
const test_helpers = @import("../../lib/test/helpers.zig");
const GlobExpander = @import("../glob.zig").GlobExpander;
const PromptBuilder = @import("../builder.zig").PromptBuilder;
const ExtractionFlags = @import("../../lib/core/extraction.zig").ExtractionFlags;

test "single large file warning" {
    const allocator = std.testing.allocator;

    var ctx = try test_helpers.TmpDirTestContext.init(allocator);
    defer ctx.deinit();

    // Create a file that appears large without actually writing 11MB
    // We'll create a sparse file or just a smaller file that still tests the logic
    const file = try ctx.tmp_dir.dir.createFile("large.zig", .{});
    defer file.close();

    // Use seekTo to make the file appear large without writing all the data
    // This reduces SSD wear significantly
    const large_size = 11 * 1024 * 1024; // 11MB
    try file.seekTo(large_size - 1);
    try file.writeAll("\n");

    // Try to add the large file to prompt (using quiet mode to suppress warning)
    const extraction_flags = ExtractionFlags{};
    var builder = try PromptBuilder.initForTest(allocator, ctx.filesystem, extraction_flags);
    builder.quiet = true; // Set quiet mode for this test
    defer builder.deinit();

    const large_path = try std.fmt.allocPrint(allocator, "{s}/large.zig", .{ctx.path});
    defer allocator.free(large_path);

    var files = [_][]u8{large_path};

    // This should handle the large file gracefully (skip without warning in quiet mode)
    try builder.addFiles(&files);

    // Verify the file was skipped (output should be empty)
    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();
    try builder.write(output.writer());
    try std.testing.expect(output.items.len == 0);
}

test "many small files" {
    const allocator = std.testing.allocator;

    var ctx = try test_helpers.TmpDirTestContext.init(allocator);
    defer ctx.deinit();

    // Create many small files
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        var name_buf: [32]u8 = undefined;
        const name = try std.fmt.bufPrint(&name_buf, "file_{d}.zig", .{i});

        var content_buf: [64]u8 = undefined;
        const content = try std.fmt.bufPrint(&content_buf, "const val_{d} = {d};", .{ i, i });

        try ctx.writeFile(name, content);
    }

    const expander = test_helpers.createGlobExpander(allocator, ctx.filesystem);

    // Match all files
    const pattern = try std.fmt.allocPrint(allocator, "{s}/*.zig", .{ctx.path});
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

    // Should find 100 files
    try std.testing.expect(results.items.len == 1);
    try std.testing.expect(results.items[0].files.items.len == 100);
}

test "glob with large files" {
    const allocator = std.testing.allocator;

    var ctx = try test_helpers.TmpDirTestContext.init(allocator);
    defer ctx.deinit();

    // Create a mix of small and large files
    try ctx.writeFile("small1.zig", "const a = 1;");
    try ctx.writeFile("small2.zig", "const b = 2;");

    // Create large file
    const large_file = try ctx.tmp_dir.dir.createFile("large.zig", .{});
    defer large_file.close();
    const large_size = 11 * 1024 * 1024; // 11MB
    try large_file.seekTo(large_size - 1);
    try large_file.writeAll("\n");

    const expander = test_helpers.createGlobExpander(allocator, ctx.filesystem);

    // Match all .zig files
    const pattern = try std.fmt.allocPrint(allocator, "{s}/*.zig", .{ctx.path});
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

    // Should find all 3 files (glob doesn't filter by size)
    try std.testing.expect(results.items.len == 1);
    try std.testing.expect(results.items[0].files.items.len == 3);
}

test "recursive glob with large files" {
    const allocator = std.testing.allocator;

    var ctx = try test_helpers.TmpDirTestContext.init(allocator);
    defer ctx.deinit();

    // Create nested structure with files
    try ctx.makePath("src/deep/nested");
    try ctx.writeFile("src/file1.zig", "const a = 1;");
    try ctx.writeFile("src/deep/file2.zig", "const b = 2;");
    try ctx.writeFile("src/deep/nested/file3.zig", "const c = 3;");

    // Create a large file in nested directory
    const large_file = try ctx.tmp_dir.dir.createFile("src/deep/large.zig", .{});
    defer large_file.close();
    const large_size = 11 * 1024 * 1024;
    try large_file.seekTo(large_size - 1);
    try large_file.writeAll("\n");

    const expander = test_helpers.createGlobExpander(allocator, ctx.filesystem);

    // Recursive match
    const pattern = try std.fmt.allocPrint(allocator, "{s}/**/*.zig", .{ctx.path});
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

    // Should find all 4 files
    try std.testing.expect(results.items.len == 1);
    try std.testing.expect(results.items[0].files.items.len == 4);
}

test "stress test with many patterns" {
    const allocator = std.testing.allocator;

    var ctx = try test_helpers.TmpDirTestContext.init(allocator);
    defer ctx.deinit();

    // Create test files
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        var name_buf: [32]u8 = undefined;
        const name = try std.fmt.bufPrint(&name_buf, "file_{d}.zig", .{i});
        try ctx.writeFile(name, "const x = 1;");
    }

    const expander = test_helpers.createGlobExpander(allocator, ctx.filesystem);

    // Create many patterns
    var pattern_list = std.ArrayList([]const u8).init(allocator);
    defer {
        for (pattern_list.items) |pattern| {
            allocator.free(pattern);
        }
        pattern_list.deinit();
    }

    i = 0;
    while (i < 20) : (i += 1) {
        const pattern = try std.fmt.allocPrint(allocator, "{s}/file_{d}.zig", .{ ctx.path, i });
        try pattern_list.append(pattern);
    }

    var results = try expander.expandPatternsWithInfo(pattern_list.items);
    defer {
        for (results.items) |*result| {
            for (result.files.items) |file| {
                allocator.free(file);
            }
            result.files.deinit();
        }
        results.deinit();
    }

    // Should find all patterns
    try std.testing.expect(results.items.len == 20);
    for (results.items) |result| {
        try std.testing.expect(result.files.items.len == 1);
    }
}

test "prompt builder with large content" {
    const allocator = std.testing.allocator;

    var ctx = try test_helpers.TmpDirTestContext.init(allocator);
    defer ctx.deinit();

    // Create file with moderately large content (not 10MB, just enough to test)
    const content_size = 1024 * 100; // 100KB
    const content = try allocator.alloc(u8, content_size);
    defer allocator.free(content);

    // Fill with valid Zig code
    for (content, 0..) |*byte, idx| {
        byte.* = if (idx % 80 == 79) '\n' else 'a';
    }

    try ctx.writeFile("moderate.zig", content);

    const extraction_flags2 = ExtractionFlags{};
    var builder = try PromptBuilder.initForTest(allocator, ctx.filesystem, extraction_flags2);
    defer builder.deinit();

    const file_path = try std.fmt.allocPrint(allocator, "{s}/moderate.zig", .{ctx.path});
    defer allocator.free(file_path);

    var files = [_][]u8{file_path};
    try builder.addFiles(&files);

    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();
    try builder.write(output.writer());

    // Should include the file content
    try std.testing.expect(output.items.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "moderate.zig") != null);
}
