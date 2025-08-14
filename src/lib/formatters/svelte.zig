const std = @import("std");
const FormatterOptions = @import("../formatter.zig").FormatterOptions;

pub fn format(allocator: std.mem.Allocator, source: []const u8, options: FormatterOptions) ![]const u8 {
    _ = options;
    // For now, return source as-is
    // TODO: Implement Svelte formatting (script/style/template sections)
    return allocator.dupe(u8, source);
}