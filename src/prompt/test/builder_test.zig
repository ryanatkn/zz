const std = @import("std");
const testing = std.testing;
const test_helpers = @import("../../test_helpers.zig");
const PromptBuilder = @import("../builder.zig").PromptBuilder;
const GlobExpander = @import("../glob.zig").GlobExpander;

test "PromptBuilder basic" {
    var ctx = try test_helpers.TmpDirTestContext.init(testing.allocator);
    defer ctx.deinit();

    var builder = PromptBuilder.init(testing.allocator, ctx.filesystem);
    defer builder.deinit();

    try builder.addText("Test instructions");
    try testing.expect(builder.lines.items.len > 0);
}

test "prompt builder output format" {
    var ctx = try test_helpers.TmpDirTestContext.init(testing.allocator);
    defer ctx.deinit();

    var builder = PromptBuilder.init(testing.allocator, ctx.filesystem);
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
