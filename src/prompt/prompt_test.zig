const std = @import("std");
const PromptBuilder = @import("builder.zig").PromptBuilder;
const GlobExpander = @import("glob.zig").GlobExpander;
const Config = @import("config.zig").Config;
const fence = @import("fence.zig");

test "deduplication of file paths" {
    const allocator = std.testing.allocator;
    
    // Create temp directory structure for testing
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    // Create test files
    try tmp_dir.dir.writeFile(.{ .sub_path = "test1.zig", .data = "const a = 1;" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "test2.zig", .data = "const b = 2;" });
    try tmp_dir.dir.makeDir("sub");
    try tmp_dir.dir.writeFile(.{ .sub_path = "sub/test3.zig", .data = "const c = 3;" });
    
    // Get temp path
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);
    
    // Test deduplication with multiple patterns that match same files
    var expander = GlobExpander.init(allocator);
    
    // Create patterns that will match some of the same files
    var patterns = [_][]const u8{
        try std.fmt.allocPrint(allocator, "{s}/test1.zig", .{tmp_path}),
        try std.fmt.allocPrint(allocator, "{s}/*.zig", .{tmp_path}),
        try std.fmt.allocPrint(allocator, "{s}/test1.zig", .{tmp_path}), // Duplicate
    };
    defer for (patterns) |pattern| allocator.free(pattern);
    
    var file_paths = try expander.expandGlobs(&patterns);
    defer {
        for (file_paths.items) |path| {
            allocator.free(path);
        }
        file_paths.deinit();
    }
    
    // Deduplicate
    var seen = std.StringHashMap(void).init(allocator);
    defer seen.deinit();
    
    var unique_paths = std.ArrayList([]u8).init(allocator);
    defer unique_paths.deinit();
    
    for (file_paths.items) |path| {
        if (!seen.contains(path)) {
            try seen.put(path, {});
            try unique_paths.append(path);
        }
    }
    
    // Should have only 2 unique files (test1.zig and test2.zig)
    try std.testing.expect(unique_paths.items.len == 2);
}

test "glob pattern expansion" {
    const allocator = std.testing.allocator;
    var expander = GlobExpander.init(allocator);
    
    // Test simple wildcard matching
    try std.testing.expect(expander.matchPattern("test.zig", "*.zig"));
    try std.testing.expect(expander.matchPattern("main.zig", "*.zig"));
    try std.testing.expect(!expander.matchPattern("test.txt", "*.zig"));
    
    // Test alternatives
    try std.testing.expect(expander.matchPattern("test.zig", "*.{zig,txt}"));
    try std.testing.expect(expander.matchPattern("test.txt", "*.{zig,txt}"));
    try std.testing.expect(!expander.matchPattern("test.md", "*.{zig,txt}"));
    
    // Test question mark
    try std.testing.expect(expander.matchPattern("a.txt", "?.txt"));
    try std.testing.expect(!expander.matchPattern("ab.txt", "?.txt"));
}

test "fence detection with various content" {
    const allocator = std.testing.allocator;
    
    // Test empty content
    const fence1 = try fence.detectFence("", allocator);
    defer allocator.free(fence1);
    try std.testing.expectEqualStrings("```", fence1);
    
    // Test content with nested fences
    const content2 = 
        \\```zig
        \\const a = 1;
        \\```
    ;
    const fence2 = try fence.detectFence(content2, allocator);
    defer allocator.free(fence2);
    try std.testing.expectEqualStrings("````", fence2);
    
    // Test content with multiple fence levels
    const content3 = 
        \\````markdown
        \\```zig
        \\const a = 1;
        \\```
        \\````
    ;
    const fence3 = try fence.detectFence(content3, allocator);
    defer allocator.free(fence3);
    try std.testing.expectEqualStrings("`````", fence3);
}

test "config parsing" {
    const allocator = std.testing.allocator;
    
    // Test with --prepend flag
    var args1 = [_][:0]const u8{ "zz", "prompt", "--prepend=Instructions here", "file.zig" };
    var config1 = try Config.fromArgs(allocator, &args1);
    defer config1.deinit();
    
    try std.testing.expect(config1.prepend_text != null);
    try std.testing.expectEqualStrings("Instructions here", config1.prepend_text.?);
    
    var patterns1 = try config1.getFilePatterns(&args1);
    defer patterns1.deinit();
    try std.testing.expect(patterns1.items.len == 1);
    try std.testing.expectEqualStrings("file.zig", patterns1.items[0]);
    
    // Test with --append flag
    var args2 = [_][:0]const u8{ "zz", "prompt", "--append=Follow-up text", "file.zig" };
    var config2 = try Config.fromArgs(allocator, &args2);
    defer config2.deinit();
    
    try std.testing.expect(config2.append_text != null);
    try std.testing.expectEqualStrings("Follow-up text", config2.append_text.?);
    
    // Test without text flags
    var args3 = [_][:0]const u8{ "zz", "prompt", "file1.zig", "file2.zig" };
    var config3 = try Config.fromArgs(allocator, &args3);
    defer config3.deinit();
    
    try std.testing.expect(config3.prepend_text == null);
    try std.testing.expect(config3.append_text == null);
    
    var patterns3 = try config3.getFilePatterns(&args3);
    defer patterns3.deinit();
    try std.testing.expect(patterns3.items.len == 2);
    try std.testing.expectEqualStrings("file1.zig", patterns3.items[0]);
    try std.testing.expectEqualStrings("file2.zig", patterns3.items[1]);
    
    // Test error when no files provided and no text flags
    var args4 = [_][:0]const u8{ "zz", "prompt" };
    var config4 = try Config.fromArgs(allocator, &args4);
    defer config4.deinit();
    
    const result = config4.getFilePatterns(&args4);
    try std.testing.expectError(error.NoInputFiles, result);
}

test "prompt builder output format" {
    const allocator = std.testing.allocator;
    
    var builder = PromptBuilder.init(allocator);
    defer builder.deinit();
    
    // Add text
    try builder.addText("Test instructions");
    
    // Write to buffer
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    
    try builder.write(buf.writer());
    
    const output = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "Test instructions") != null);
}

test "ignore patterns" {
    const allocator = std.testing.allocator;
    
    var args = [_][:0]const u8{ "zz", "prompt" };
    var config = try Config.fromArgs(allocator, &args);
    defer config.deinit();
    
    // Test default ignore patterns
    try std.testing.expect(config.shouldIgnore(".git/config"));
    try std.testing.expect(config.shouldIgnore("path/to/.zig-cache/file"));
    try std.testing.expect(config.shouldIgnore("zig-out/bin/test"));
    try std.testing.expect(config.shouldIgnore("node_modules/package/index.js"));
    
    // Test non-ignored paths
    try std.testing.expect(!config.shouldIgnore("src/main.zig"));
    try std.testing.expect(!config.shouldIgnore("README.md"));
    try std.testing.expect(!config.shouldIgnore("src/module.test.zig"));
}