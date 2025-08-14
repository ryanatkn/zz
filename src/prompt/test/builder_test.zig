const std = @import("std");
const testing = std.testing;
const test_helpers = @import("../../test_helpers.zig");
const PromptBuilder = @import("../builder.zig").PromptBuilder;
const GlobExpander = @import("../glob.zig").GlobExpander;
const ExtractionFlags = @import("../../lib/extraction_flags.zig").ExtractionFlags;

test "PromptBuilder basic" {
    var ctx = try test_helpers.TmpDirTestContext.init(testing.allocator);
    defer ctx.deinit();

    const extraction_flags = ExtractionFlags{};
    var builder = PromptBuilder.init(testing.allocator, ctx.filesystem, extraction_flags);
    defer builder.deinit();

    try builder.addText("Test instructions");
    try testing.expect(builder.lines.items.len > 0);
}

test "prompt builder output format" {
    var ctx = try test_helpers.TmpDirTestContext.init(testing.allocator);
    defer ctx.deinit();

    const extraction_flags = ExtractionFlags{};
    var builder = PromptBuilder.init(testing.allocator, ctx.filesystem, extraction_flags);
    defer builder.deinit();

    // Add text
    try builder.addText("Test instructions");

    // Write to buffer
    var buf = std.ArrayList(u8).init(testing.allocator);
    defer buf.deinit();

    try builder.write(buf.writer());

    const output = buf.items;
    try testing.expect(std.mem.indexOf(u8, output, "Test instructions") != null);
}

test "deduplication of file paths" {
    var ctx = try test_helpers.TmpDirTestContext.init(testing.allocator);
    defer ctx.deinit();

    // Create test files
    try ctx.writeFile("test1.zig", "const a = 1;");
    try ctx.writeFile("test2.zig", "const b = 2;");
    try ctx.makeDir("sub");
    try ctx.writeFile("sub/test3.zig", "const c = 3;");

    // Test deduplication with multiple patterns that match same files
    const expander = test_helpers.createGlobExpander(testing.allocator, ctx.filesystem);

    // Create patterns that will match some of the same files
    var patterns = [_][]const u8{
        try std.fmt.allocPrint(testing.allocator, "{s}/test1.zig", .{ctx.path}),
        try std.fmt.allocPrint(testing.allocator, "{s}/*.zig", .{ctx.path}),
        try std.fmt.allocPrint(testing.allocator, "{s}/test1.zig", .{ctx.path}), // Duplicate
    };
    defer for (patterns) |pattern| testing.allocator.free(pattern);

    var file_paths = try expander.expandGlobs(&patterns);
    defer {
        for (file_paths.items) |path| {
            testing.allocator.free(path);
        }
        file_paths.deinit();
    }

    // Deduplicate
    var seen = std.StringHashMap(void).init(testing.allocator);
    defer seen.deinit();

    var unique_paths = std.ArrayList([]u8).init(testing.allocator);
    defer unique_paths.deinit();

    for (file_paths.items) |path| {
        if (!seen.contains(path)) {
            try seen.put(path, {});
            try unique_paths.append(path);
        }
    }

    // Should have only 2 unique files (test1.zig and test2.zig)
    try testing.expect(unique_paths.items.len == 2);
}

test "prompt builder outputs relative paths with ./ prefix" {
    var ctx = test_helpers.MockTestContext.init(testing.allocator);
    defer ctx.deinit();
    
    try ctx.addFile("test.zig", "const a = 1;");
    
    const extraction_flags = ExtractionFlags{};
    var builder = PromptBuilder.init(testing.allocator, ctx.filesystem, extraction_flags);
    defer builder.deinit();
    
    try builder.addFile("test.zig");
    
    var buf = std.ArrayList(u8).init(testing.allocator);
    defer buf.deinit();
    
    try builder.write(buf.writer());
    
    const output = buf.items;
    
    // Should contain ./test.zig in the XML tag
    try testing.expect(std.mem.indexOf(u8, output, "<File path=\"./test.zig\">") != null);
}

test "prompt builder preserves absolute paths" {
    var ctx = try test_helpers.TmpDirTestContext.init(testing.allocator);
    defer ctx.deinit();
    
    try ctx.writeFile("test.zig", "const a = 1;");
    
    const extraction_flags = ExtractionFlags{};
    var builder = PromptBuilder.init(testing.allocator, ctx.filesystem, extraction_flags);
    defer builder.deinit();
    
    // Add file with absolute path (using the temporary directory path)
    const abs_path = try std.fmt.allocPrint(testing.allocator, "{s}/test.zig", .{ctx.path});
    defer testing.allocator.free(abs_path);
    
    try builder.addFile(abs_path);
    
    var buf = std.ArrayList(u8).init(testing.allocator);
    defer buf.deinit();
    
    try builder.write(buf.writer());
    
    const output = buf.items;
    
    // Absolute paths should remain unchanged
    const expected_tag = try std.fmt.allocPrint(testing.allocator, "<File path=\"{s}\">", .{abs_path});
    defer testing.allocator.free(expected_tag);
    
    try testing.expect(std.mem.indexOf(u8, output, expected_tag) != null);
}
