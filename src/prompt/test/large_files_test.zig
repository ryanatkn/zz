const std = @import("std");
const GlobExpander = @import("../glob.zig").GlobExpander;
const PromptBuilder = @import("../builder.zig").PromptBuilder;

test "single large file warning" {
    const allocator = std.testing.allocator;
    
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    // Create a large file (over 10MB limit)
    const large_size = 11 * 1024 * 1024; // 11MB
    const large_content = try allocator.alloc(u8, large_size);
    defer allocator.free(large_content);
    @memset(large_content, 'a');
    
    try tmp_dir.dir.writeFile(.{ .sub_path = "large.zig", .data = large_content });
    
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);
    
    // Try to add the large file to prompt
    var builder = PromptBuilder.init(allocator);
    defer builder.deinit();
    
    const large_path = try std.fmt.allocPrint(allocator, "{s}/large.zig", .{tmp_path});
    defer allocator.free(large_path);
    
    var files = [_][]u8{large_path};
    
    // This should handle the large file gracefully (skip with warning)
    try builder.addFiles(&files);
}

test "many small files" {
    const allocator = std.testing.allocator;
    
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    // Create many small files
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        var name_buf: [32]u8 = undefined;
        const name = try std.fmt.bufPrint(&name_buf, "file_{d}.zig", .{i});
        
        var content_buf: [64]u8 = undefined;
        const content = try std.fmt.bufPrint(&content_buf, "const val_{d} = {d};", .{i, i});
        
        try tmp_dir.dir.writeFile(.{ .sub_path = name, .data = content });
    }
    
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);
    
    var expander = GlobExpander.init(allocator);
    
    // Match all files
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
    
    // Should find all 100 files
    try std.testing.expect(results.items.len == 1);
    try std.testing.expect(results.items[0].files.items.len == 100);
}

test "deep directory recursion" {
    const allocator = std.testing.allocator;
    
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    // Create a deep directory structure
    var current_path = std.ArrayList(u8).init(allocator);
    defer current_path.deinit();
    
    try current_path.appendSlice("level0");
    try tmp_dir.dir.makeDir("level0");
    
    var i: usize = 1;
    while (i < 10) : (i += 1) {
        try current_path.append('/');
        try current_path.writer().print("level{d}", .{i});
        
        try tmp_dir.dir.makePath(current_path.items);
        
        // Add a file at this level
        var file_path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const file_path = try std.fmt.bufPrint(&file_path_buf, "{s}/file.zig", .{current_path.items});
        
        try tmp_dir.dir.writeFile(.{ .sub_path = file_path, .data = "const a = 1;" });
    }
    
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);
    
    var expander = GlobExpander.init(allocator);
    
    // Recursive pattern to find all files
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
    
    // Should find files at all levels (we created 9 files)
    try std.testing.expect(results.items.len == 1);
    try std.testing.expect(results.items[0].files.items.len == 9);
}

test "extreme recursion pattern" {
    const allocator = std.testing.allocator;
    
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    // Create a simple structure
    try tmp_dir.dir.makeDir("a");
    try tmp_dir.dir.makeDir("a/b");
    try tmp_dir.dir.makeDir("a/b/c");
    try tmp_dir.dir.writeFile(.{ .sub_path = "a/b/c/file.zig", .data = "const a = 1;" });
    
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);
    
    var expander = GlobExpander.init(allocator);
    
    // Pattern with multiple ** (should still work)
    const pattern = try std.fmt.allocPrint(allocator, "{s}/**/**/**/*.zig", .{tmp_path});
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
    
    // Should still find the file (multiple ** should be handled)
    try std.testing.expect(results.items.len == 1);
}

test "memory usage with large file count" {
    const allocator = std.testing.allocator;
    
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    // Create a moderate number of files to test memory handling
    var i: usize = 0;
    while (i < 500) : (i += 1) {
        var name_buf: [32]u8 = undefined;
        const name = try std.fmt.bufPrint(&name_buf, "f{d}.zig", .{i});
        try tmp_dir.dir.writeFile(.{ .sub_path = name, .data = "x" });
    }
    
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);
    
    // Test that we can handle many files without issues
    var expander = GlobExpander.init(allocator);
    
    const pattern = try std.fmt.allocPrint(allocator, "{s}/*.zig", .{tmp_path});
    defer allocator.free(pattern);
    
    var patterns = [_][]const u8{pattern};
    var results = try expander.expandPatternsWithInfo(&patterns);
    
    // Proper cleanup
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
    try std.testing.expect(results.items[0].files.items.len == 500);
}

test "file with extremely long lines" {
    const allocator = std.testing.allocator;
    
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    // Create file with very long lines
    const long_line = try allocator.alloc(u8, 5000);
    defer allocator.free(long_line);
    @memset(long_line[0..4995], 'x');
    long_line[4995] = ';';
    long_line[4996] = '\n';
    
    var content = std.ArrayList(u8).init(allocator);
    defer content.deinit();
    
    try content.appendSlice("const long_string = \"");
    try content.appendSlice(long_line);
    try content.appendSlice("const another = \"");
    try content.appendSlice(long_line);
    
    try tmp_dir.dir.writeFile(.{ .sub_path = "longlines.zig", .data = content.items });
    
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);
    
    // This should handle long lines gracefully
    var builder = PromptBuilder.init(allocator);
    defer builder.deinit();
    
    const file_path = try std.fmt.allocPrint(allocator, "{s}/longlines.zig", .{tmp_path});
    defer allocator.free(file_path);
    
    var files = [_][]u8{file_path};
    try builder.addFiles(&files);
    
    // Write to buffer to check it works
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    
    try builder.write(buf.writer());
    
    // Should have written something
    try std.testing.expect(buf.items.len > 0);
}