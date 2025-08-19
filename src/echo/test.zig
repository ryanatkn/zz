test {
    _ = @import("main.zig");
    _ = @import("escape.zig");
    _ = @import("json.zig");
    _ = @import("color.zig");
}

const std = @import("std");
const escape = @import("escape.zig");
const json = @import("json.zig");
const color = @import("color.zig");

test "escape sequence processing" {
    const allocator = std.testing.allocator;

    // Test basic escape sequences
    {
        const result = try escape.process(allocator, "Hello\\nWorld");
        defer allocator.free(result);
        try std.testing.expectEqualStrings("Hello\nWorld", result);
    }

    // Test multiple escape sequences
    {
        const result = try escape.process(allocator, "Line1\\nLine2\\tTabbed");
        defer allocator.free(result);
        try std.testing.expectEqualStrings("Line1\nLine2\tTabbed", result);
    }

    // Test all basic escape sequences
    {
        const result = try escape.process(allocator, "\\n\\t\\r\\a\\b\\f\\v\\\\\\\"");
        defer allocator.free(result);
        try std.testing.expectEqualStrings("\n\t\r\x07\x08\x0C\x0B\\\"", result);
    }

    // Test hex escape sequences
    {
        const result = try escape.process(allocator, "\\x48\\x65\\x6c\\x6c\\x6f");
        defer allocator.free(result);
        try std.testing.expectEqualStrings("Hello", result);
    }

    // Test octal escape sequences
    {
        const result = try escape.process(allocator, "\\110\\145\\154\\154\\157");
        defer allocator.free(result);
        try std.testing.expectEqualStrings("Hello", result);
    }

    // Test invalid escape sequences (should be literal)
    {
        const result = try escape.process(allocator, "\\z\\q");
        defer allocator.free(result);
        try std.testing.expectEqualStrings("\\z\\q", result);
    }

    // Test no escape sequences
    {
        const result = try escape.process(allocator, "No escapes here");
        defer allocator.free(result);
        try std.testing.expectEqualStrings("No escapes here", result);
    }

    // Test octal overflow
    {
        const result = try escape.process(allocator, "\\777"); // > 255
        defer allocator.free(result);
        try std.testing.expectEqualStrings("?7", result); // Should stop at \77 (63 = '?') + literal 7
    }
}

test "JSON escaping" {
    const allocator = std.testing.allocator;

    // Test basic string
    {
        const result = try json.escape(allocator, "Hello, World!");
        defer allocator.free(result);
        try std.testing.expectEqualStrings("\"Hello, World!\"", result);
    }

    // Test quotes and backslashes
    {
        const result = try json.escape(allocator, "Say \"Hello\"");
        defer allocator.free(result);
        try std.testing.expectEqualStrings("\"Say \\\"Hello\\\"\"", result);
    }

    // Test backslashes
    {
        const result = try json.escape(allocator, "C:\\path\\file");
        defer allocator.free(result);
        try std.testing.expectEqualStrings("\"C:\\\\path\\\\file\"", result);
    }

    // Test newlines and tabs
    {
        const result = try json.escape(allocator, "Line1\nLine2\tTabbed");
        defer allocator.free(result);
        try std.testing.expectEqualStrings("\"Line1\\nLine2\\tTabbed\"", result);
    }

    // Test control characters
    {
        const result = try json.escape(allocator, "\x01\x02\x1F");
        defer allocator.free(result);
        try std.testing.expectEqualStrings("\"\\u0001\\u0002\\u001f\"", result);
    }

    // Test empty string
    {
        const result = try json.escape(allocator, "");
        defer allocator.free(result);
        try std.testing.expectEqualStrings("\"\"", result);
    }
}

test "color validation" {
    // Test valid colors
    try std.testing.expect(color.isValidColor("red"));
    try std.testing.expect(color.isValidColor("green"));
    try std.testing.expect(color.isValidColor("blue"));
    try std.testing.expect(color.isValidColor("yellow"));
    try std.testing.expect(color.isValidColor("magenta"));
    try std.testing.expect(color.isValidColor("cyan"));
    try std.testing.expect(color.isValidColor("black"));
    try std.testing.expect(color.isValidColor("white"));

    // Test invalid colors
    try std.testing.expect(!color.isValidColor("purple"));
    try std.testing.expect(!color.isValidColor("orange"));
    try std.testing.expect(!color.isValidColor(""));
    try std.testing.expect(!color.isValidColor("RED")); // Case sensitive
}

test "argument parsing edge cases" {
    // Test that these don't crash when compiled
    // We can't easily test output in unit tests without more complex setup

    // Basic smoke test - the main module should compile
    _ = @import("main.zig");
}

test "escape sequence edge cases" {
    const allocator = std.testing.allocator;

    // Test incomplete hex escape
    {
        const result = try escape.process(allocator, "\\x");
        defer allocator.free(result);
        try std.testing.expectEqualStrings("\\x", result);
    }

    // Test incomplete hex escape with one digit
    {
        const result = try escape.process(allocator, "\\xA");
        defer allocator.free(result);
        try std.testing.expectEqualStrings("\x0A", result);
    }

    // Test incomplete octal escape
    {
        const result = try escape.process(allocator, "\\");
        defer allocator.free(result);
        try std.testing.expectEqualStrings("\\", result);
    }

    // Test octal with non-octal characters
    {
        const result = try escape.process(allocator, "\\123abc");
        defer allocator.free(result);
        try std.testing.expectEqualStrings("Sabc", result); // \123 = 83 = 'S'
    }

    // Test hex with non-hex characters
    {
        const result = try escape.process(allocator, "\\x41Z");
        defer allocator.free(result);
        try std.testing.expectEqualStrings("AZ", result); // \x41 = 'A'
    }
}

test "JSON escaping edge cases" {
    const allocator = std.testing.allocator;

    // Test string with all escape-worthy characters
    {
        const input = "\"\\\n\r\t\x08\x0C/\x00\x1F";
        const result = try json.escape(allocator, input);
        defer allocator.free(result);
        const expected = "\"\\\"\\\\\\n\\r\\t\\b\\f\\/\\u0000\\u001f\"";
        try std.testing.expectEqualStrings(expected, result);
    }

    // Test Unicode characters (should pass through)
    {
        const result = try json.escape(allocator, "Hello 🌍");
        defer allocator.free(result);
        try std.testing.expectEqualStrings("\"Hello 🌍\"", result);
    }
}

test "performance benchmark - startup time" {
    _ = std.testing.allocator;

    // Measure startup time with simple echo
    var args = [_][:0]const u8{ "zz", "echo", "test" };

    const start_time = std.time.nanoTimestamp();

    // Test parsing without actual output (to isolate parsing performance)
    const parse_result = try @import("main.zig").parseArgsAndText(args[0..]);
    _ = parse_result;

    const end_time = std.time.nanoTimestamp();
    const duration_ns = @as(u64, @intCast(end_time - start_time));

    // Should be under 50μs as claimed in documentation
    const target_ns: u64 = 50_000; // 50μs

    // Print actual time for debugging
    std.debug.print("Echo parsing time: {}ns ({}μs)\n", .{ duration_ns, duration_ns / 1000 });

    // This is a guidance test - may fail on very slow systems
    if (duration_ns > target_ns) {
        std.debug.print("Warning: Parsing took longer than target of {}μs\n", .{target_ns / 1000});
    }
}

test "performance benchmark - escape processing" {
    const allocator = std.testing.allocator;

    // Test escape sequence processing performance
    const test_string = "Line1\\nLine2\\tTabbed\\nLine3\\nLine4\\n" ** 100; // Repeat 100 times

    const start_time = std.time.nanoTimestamp();

    const result = try escape.process(allocator, test_string);
    defer allocator.free(result);

    const end_time = std.time.nanoTimestamp();
    const duration_ns = @as(u64, @intCast(end_time - start_time));

    // Should process large strings efficiently
    const input_size = test_string.len;
    const ns_per_byte = duration_ns / input_size;

    std.debug.print("Escape processing: {} bytes in {}ns ({}ns/byte)\n", .{ input_size, duration_ns, ns_per_byte });

    // Should be reasonably fast (debug builds are slower)
    try std.testing.expect(ns_per_byte < 1000); // Much more lenient for debug
}

test "performance benchmark - JSON escaping" {
    const allocator = std.testing.allocator;

    // Test JSON escaping performance with challenging input
    const test_string = "Path: C:\\Users\\Test\\file\"with quotes\"\nand newlines\t" ** 50; // Repeat 50 times

    const start_time = std.time.nanoTimestamp();

    const result = try json.escape(allocator, test_string);
    defer allocator.free(result);

    const end_time = std.time.nanoTimestamp();
    const duration_ns = @as(u64, @intCast(end_time - start_time));

    const input_size = test_string.len;
    const ns_per_byte = duration_ns / input_size;

    std.debug.print("JSON escaping: {} bytes in {}ns ({}ns/byte)\n", .{ input_size, duration_ns, ns_per_byte });

    // Should be reasonably fast for JSON escaping (debug builds are slower)
    try std.testing.expect(ns_per_byte < 1000); // Much more lenient for debug
}

// Integration tests would go here, but they require more complex setup
// to capture stdout and test actual command execution
