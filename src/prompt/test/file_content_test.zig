const std = @import("std");
const test_helpers = @import("../../lib/test/helpers.zig");
const PromptBuilder = @import("../builder.zig").PromptBuilder;
const ExtractionFlags = @import("../../lib/core/extraction.zig").ExtractionFlags;
const fence = @import("../fence.zig");

test "file with no newlines" {
    const allocator = std.testing.allocator;

    var ctx = test_helpers.MockTestContext.init(allocator);
    defer ctx.deinit();

    // Create file without any newlines
    const content = "const a = 1; const b = 2; const c = 3;";
    try ctx.addFile("nonewline.zig", content);

    const extraction_flags = ExtractionFlags{};
    var builder = try PromptBuilder.initForTest(allocator, ctx.filesystem, extraction_flags);
    defer builder.deinit();

    const file_path = "nonewline.zig";
    try builder.addFile(file_path);

    // Should handle file without newlines
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    try builder.write(buf.writer());
    try std.testing.expect(buf.items.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, content) != null);
}

test "file with only backticks" {
    const allocator = std.testing.allocator;

    var ctx = test_helpers.MockTestContext.init(allocator);
    defer ctx.deinit();

    // Create file with various backtick patterns
    const content =
        \\```
        \\````
        \\`````
        \\``````
    ;
    try ctx.addFile("backticks.md", content);

    // Test fence detection with this content
    const detected_fence = try fence.detectFence(content, allocator);
    defer allocator.free(detected_fence);

    // Should detect a fence longer than the longest in content
    try std.testing.expect(detected_fence.len >= 7);

    const extraction_flags = ExtractionFlags{};
    var builder = try PromptBuilder.initForTest(allocator, ctx.filesystem, extraction_flags);
    defer builder.deinit();

    const file_path = "backticks.md";
    try builder.addFile(file_path);

    // Should handle the file correctly
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    try builder.write(buf.writer());
    try std.testing.expect(buf.items.len > 0);
}

test "empty file" {
    const allocator = std.testing.allocator;

    var ctx = test_helpers.MockTestContext.init(allocator);
    defer ctx.deinit();

    // Create empty file
    try ctx.addFile("empty.zig", "");

    const extraction_flags = ExtractionFlags{};
    var builder = try PromptBuilder.initForTest(allocator, ctx.filesystem, extraction_flags);
    defer builder.deinit();

    const file_path = "empty.zig";
    try builder.addFile(file_path);

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

    var ctx = test_helpers.MockTestContext.init(allocator);
    defer ctx.deinit();

    // Create binary content
    var binary_data: [256]u8 = undefined;
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        binary_data[i] = @intCast(i);
    }

    try ctx.addFile("binary.zig", &binary_data);

    const extraction_flags = ExtractionFlags{};
    var builder = try PromptBuilder.initForTest(allocator, ctx.filesystem, extraction_flags);
    defer builder.deinit();

    const file_path = "binary.zig";

    // Should handle binary file (may skip or show as binary)
    try builder.addFile(file_path);

    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    try builder.write(buf.writer());
    // Should at least not crash
    try std.testing.expect(buf.items.len > 0);
}

test "file with null bytes" {
    const allocator = std.testing.allocator;

    var ctx = test_helpers.MockTestContext.init(allocator);
    defer ctx.deinit();

    // Create file with null bytes
    const content = "before\x00null\x00after";
    try ctx.addFile("nulls.txt", content);

    const extraction_flags = ExtractionFlags{};
    var builder = try PromptBuilder.initForTest(allocator, ctx.filesystem, extraction_flags);
    defer builder.deinit();

    const file_path = "nulls.txt";

    // Should handle file with nulls
    try builder.addFile(file_path);

    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    try builder.write(buf.writer());
    try std.testing.expect(buf.items.len > 0);
}

test "file with mixed line endings" {
    const allocator = std.testing.allocator;

    var ctx = test_helpers.MockTestContext.init(allocator);
    defer ctx.deinit();

    // Create file with mixed line endings (Unix, Windows, old Mac)
    const content = "line1\nline2\r\nline3\rline4\n\rline5";
    try ctx.addFile("mixed.txt", content);

    const extraction_flags = ExtractionFlags{};
    var builder = try PromptBuilder.initForTest(allocator, ctx.filesystem, extraction_flags);
    defer builder.deinit();

    const file_path = "mixed.txt";
    try builder.addFile(file_path);

    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    try builder.write(buf.writer());
    try std.testing.expect(buf.items.len > 0);
}

test "file with unicode and special chars" {
    const allocator = std.testing.allocator;

    var ctx = test_helpers.MockTestContext.init(allocator);
    defer ctx.deinit();

    // Create file with various unicode
    const content =
        \\// 日本語のコメント
        \\const emoji = "😀🎉🆗";
        \\const russian = "Привет мир";
        \\const arabic = "مرحبا بالعالم";
        \\const math = "∑ ∏ ∫ √ ∞";
        \\const symbols = "© ® ™ € £ ¥";
    ;
    try ctx.addFile("unicode.zig", content);

    const extraction_flags = ExtractionFlags{};
    var builder = try PromptBuilder.initForTest(allocator, ctx.filesystem, extraction_flags);
    defer builder.deinit();

    const file_path = "unicode.zig";
    try builder.addFile(file_path);

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

    var ctx = test_helpers.MockTestContext.init(allocator);
    defer ctx.deinit();

    // Create file with control characters
    var content: [32]u8 = undefined;
    var i: usize = 0;
    while (i < 32) : (i += 1) {
        content[i] = @intCast(i);
    }

    try ctx.addFile("control.txt", &content);

    const extraction_flags = ExtractionFlags{};
    var builder = try PromptBuilder.initForTest(allocator, ctx.filesystem, extraction_flags);
    defer builder.deinit();

    const file_path = "control.txt";

    // Should handle control characters
    try builder.addFile(file_path);

    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    try builder.write(buf.writer());
    try std.testing.expect(buf.items.len > 0);
}
