const std = @import("std");
const PromptBuilder = @import("../builder.zig").PromptBuilder;
const fence = @import("../fence.zig");

test "file with no newlines" {
    const allocator = std.testing.allocator;
    
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    // Create file without any newlines
    const content = "const a = 1; const b = 2; const c = 3;";
    try tmp_dir.dir.writeFile(.{ .sub_path = "nonewline.zig", .data = content });
    
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);
    
    var builder = PromptBuilder.init(allocator);
    defer builder.deinit();
    
    const file_path = try std.fmt.allocPrint(allocator, "{s}/nonewline.zig", .{tmp_path});
    defer allocator.free(file_path);
    
    var files = [_][]u8{file_path};
    try builder.addFiles(&files);
    
    // Should handle file without newlines
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    
    try builder.write(buf.writer());
    try std.testing.expect(buf.items.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, content) != null);
}

test "file with only backticks" {
    const allocator = std.testing.allocator;
    
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    // Create file with various backtick patterns
    const content = 
        \\```
        \\````
        \\`````
        \\``````
    ;
    try tmp_dir.dir.writeFile(.{ .sub_path = "backticks.md", .data = content });
    
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);
    
    // Test fence detection with this content
    const detected_fence = try fence.detectFence(content, allocator);
    defer allocator.free(detected_fence);
    
    // Should detect a fence longer than the longest in content
    try std.testing.expect(detected_fence.len >= 7);
    
    var builder = PromptBuilder.init(allocator);
    defer builder.deinit();
    
    const file_path = try std.fmt.allocPrint(allocator, "{s}/backticks.md", .{tmp_path});
    defer allocator.free(file_path);
    
    var files = [_][]u8{file_path};
    try builder.addFiles(&files);
    
    // Should handle the file correctly
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    
    try builder.write(buf.writer());
    try std.testing.expect(buf.items.len > 0);
}

test "empty file" {
    const allocator = std.testing.allocator;
    
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    // Create empty file
    try tmp_dir.dir.writeFile(.{ .sub_path = "empty.zig", .data = "" });
    
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);
    
    var builder = PromptBuilder.init(allocator);
    defer builder.deinit();
    
    const file_path = try std.fmt.allocPrint(allocator, "{s}/empty.zig", .{tmp_path});
    defer allocator.free(file_path);
    
    var files = [_][]u8{file_path};
    try builder.addFiles(&files);
    
    // Should handle empty file
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    
    try builder.write(buf.writer());
    try std.testing.expect(buf.items.len > 0);
    // Should contain file marker even if empty
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "empty.zig") != null);
}

test "binary file incorrectly named .zig" {
    const allocator = std.testing.allocator;
    
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    // Create binary content
    var binary_data: [256]u8 = undefined;
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        binary_data[i] = @intCast(i);
    }
    
    try tmp_dir.dir.writeFile(.{ .sub_path = "binary.zig", .data = &binary_data });
    
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);
    
    var builder = PromptBuilder.init(allocator);
    defer builder.deinit();
    
    const file_path = try std.fmt.allocPrint(allocator, "{s}/binary.zig", .{tmp_path});
    defer allocator.free(file_path);
    
    var files = [_][]u8{file_path};
    
    // Should handle binary file (may skip or show as binary)
    try builder.addFiles(&files);
    
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    
    try builder.write(buf.writer());
    // Should at least not crash
    try std.testing.expect(buf.items.len > 0);
}

test "file with null bytes" {
    const allocator = std.testing.allocator;
    
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    // Create file with null bytes
    const content = "before\x00null\x00after";
    try tmp_dir.dir.writeFile(.{ .sub_path = "nulls.txt", .data = content });
    
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);
    
    var builder = PromptBuilder.init(allocator);
    defer builder.deinit();
    
    const file_path = try std.fmt.allocPrint(allocator, "{s}/nulls.txt", .{tmp_path});
    defer allocator.free(file_path);
    
    var files = [_][]u8{file_path};
    
    // Should handle file with nulls
    try builder.addFiles(&files);
    
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    
    try builder.write(buf.writer());
    try std.testing.expect(buf.items.len > 0);
}

test "file with mixed line endings" {
    const allocator = std.testing.allocator;
    
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    // Create file with mixed line endings (Unix, Windows, old Mac)
    const content = "line1\nline2\r\nline3\rline4\n\rline5";
    try tmp_dir.dir.writeFile(.{ .sub_path = "mixed.txt", .data = content });
    
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);
    
    var builder = PromptBuilder.init(allocator);
    defer builder.deinit();
    
    const file_path = try std.fmt.allocPrint(allocator, "{s}/mixed.txt", .{tmp_path});
    defer allocator.free(file_path);
    
    var files = [_][]u8{file_path};
    try builder.addFiles(&files);
    
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    
    try builder.write(buf.writer());
    try std.testing.expect(buf.items.len > 0);
}

test "file with unicode and special chars" {
    const allocator = std.testing.allocator;
    
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    // Create file with various unicode
    const content = 
        \\// 日本語のコメント
        \\const emoji = "😀🎉🚀";
        \\const russian = "Привет мир";
        \\const arabic = "مرحبا بالعالم";
        \\const math = "∑ ∏ ∫ √ ∞";
        \\const symbols = "© ® ™ € £ ¥";
    ;
    try tmp_dir.dir.writeFile(.{ .sub_path = "unicode.zig", .data = content });
    
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);
    
    var builder = PromptBuilder.init(allocator);
    defer builder.deinit();
    
    const file_path = try std.fmt.allocPrint(allocator, "{s}/unicode.zig", .{tmp_path});
    defer allocator.free(file_path);
    
    var files = [_][]u8{file_path};
    try builder.addFiles(&files);
    
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    
    try builder.write(buf.writer());
    try std.testing.expect(buf.items.len > 0);
    // Unicode should be preserved
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "😀") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "日本語") != null);
}

test "file with control characters" {
    const allocator = std.testing.allocator;
    
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    // Create file with control characters
    var content: [32]u8 = undefined;
    var i: usize = 0;
    while (i < 32) : (i += 1) {
        content[i] = @intCast(i);
    }
    
    try tmp_dir.dir.writeFile(.{ .sub_path = "control.txt", .data = &content });
    
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp_dir.dir.realpath(".", &path_buf);
    
    var builder = PromptBuilder.init(allocator);
    defer builder.deinit();
    
    const file_path = try std.fmt.allocPrint(allocator, "{s}/control.txt", .{tmp_path});
    defer allocator.free(file_path);
    
    var files = [_][]u8{file_path};
    
    // Should handle control characters
    try builder.addFiles(&files);
    
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    
    try builder.write(buf.writer());
    try std.testing.expect(buf.items.len > 0);
}