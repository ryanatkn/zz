const std = @import("std");
const FormatterOptions = @import("../../parsing/formatter.zig").FormatterOptions;

/// Format Zig source code (delegate to external zig fmt)
pub fn format(allocator: std.mem.Allocator, source: []const u8, options: FormatterOptions) ![]const u8 {
    // For now, return source unchanged since external zig fmt integration is complex
    _ = options; // Zig fmt doesn't use our custom options
    return allocator.dupe(u8, source);
}