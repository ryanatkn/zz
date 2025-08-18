const std = @import("std");

/// Escape a string for JSON output
/// Returns newly allocated JSON-escaped string with surrounding quotes
pub fn escape(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    // Pre-scan to estimate size needed
    var extra_chars: usize = 2; // For surrounding quotes
    for (input) |c| {
        switch (c) {
            '"', '\\', '/' => extra_chars += 1, // Will become \"  \\  \/
            '\n', '\r', '\t', '\x08', '\x0C' => extra_chars += 1, // Will become \n \r \t \b \f
            0...7, 11, 14...0x1F => extra_chars += 5, // Will become \uXXXX
            else => {},
        }
    }

    var result = try std.ArrayList(u8).initCapacity(allocator, input.len + extra_chars);
    defer result.deinit();

    try result.append('"');

    for (input) |c| {
        switch (c) {
            '"' => try result.appendSlice("\\\""),
            '\\' => try result.appendSlice("\\\\"),
            '/' => try result.appendSlice("\\/"),
            '\n' => try result.appendSlice("\\n"),
            '\r' => try result.appendSlice("\\r"),
            '\t' => try result.appendSlice("\\t"),
            '\x08' => try result.appendSlice("\\b"), // Backspace
            '\x0C' => try result.appendSlice("\\f"), // Form feed
            0...7, 11, 14...0x1F => {
                // Control characters become \uXXXX
                try result.appendSlice("\\u00");
                const hex_chars = "0123456789abcdef";
                try result.append(hex_chars[c >> 4]);
                try result.append(hex_chars[c & 0xF]);
            },
            else => try result.append(c),
        }
    }

    try result.append('"');
    return result.toOwnedSlice();
}
