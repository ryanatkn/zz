const std = @import("std");
const testing = std.testing;
const GlobExpander = @import("../glob.zig").GlobExpander;

test "nested braces with real files" {
    const allocator = testing.allocator;
    
    // Create temp directory for test
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    // Create test files
    try tmp_dir.dir.writeFile(.{ .sub_path = "test.zig", .data = "// Zig file\n" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "test.md", .data = "# Markdown file\n" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "test.txt", .data = "Text file\n" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "test.rs", .data = "// Rust file\n" });
    
    // Get the temp directory path
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);
    
    var expander = GlobExpander.init(allocator);
    
    // Test nested braces pattern: *.{zig,{md,txt}}
    // Should match: test.zig, test.md, test.txt
    // Should NOT match: test.rs
    const pattern = try std.fmt.allocPrint(allocator, "{s}/*.{{zig,{{md,txt}}}}", .{tmp_path});
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
    
    std.debug.print("✅ Nested braces integration test passed!\n", .{});
}

test "character classes with real files" {
    const allocator = testing.allocator;
    
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    // Create numbered log files
    try tmp_dir.dir.writeFile(.{ .sub_path = "log0.txt", .data = "Log 0\n" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "log5.txt", .data = "Log 5\n" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "log9.txt", .data = "Log 9\n" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "loga.txt", .data = "Log A\n" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "logZ.txt", .data = "Log Z\n" });
    
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);
    
    var expander = GlobExpander.init(allocator);
    
    // Test character class pattern: log[0-9].txt
    // Should match: log0.txt, log5.txt, log9.txt
    // Should NOT match: loga.txt, logZ.txt
    const pattern = try std.fmt.allocPrint(allocator, "{s}/log[0-9].txt", .{tmp_path});
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
    
    // Should find exactly 3 files
    try testing.expect(results.items.len == 1);
    try testing.expectEqual(@as(usize, 3), results.items[0].files.items.len);
    
    // Verify we only got numeric logs
    for (results.items[0].files.items) |file| {
        try testing.expect(std.mem.endsWith(u8, file, "log0.txt") or
                          std.mem.endsWith(u8, file, "log5.txt") or
                          std.mem.endsWith(u8, file, "log9.txt"));
    }
    
    std.debug.print("✅ Character classes integration test passed!\n", .{});
}

test "escape sequences with real files" {
    const allocator = testing.allocator;
    
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    // Create files with special characters in names
    try tmp_dir.dir.writeFile(.{ .sub_path = "file*.txt", .data = "File with asterisk\n" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "file?.txt", .data = "File with question\n" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "file[1].txt", .data = "File with brackets\n" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "file123.txt", .data = "Normal file\n" });
    
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);
    
    var expander = GlobExpander.init(allocator);
    
    // Test escaped asterisk: file\*.txt
    // Should match only: file*.txt
    const pattern1 = try std.fmt.allocPrint(allocator, "{s}/file\\*.txt", .{tmp_path});
    defer allocator.free(pattern1);
    
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
    const pattern2 = try std.fmt.allocPrint(allocator, "{s}/file\\[1\\].txt", .{tmp_path});
    defer allocator.free(pattern2);
    
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
    
    std.debug.print("✅ Escape sequences integration test passed!\n", .{});
}