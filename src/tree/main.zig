const std = @import("std");

pub const Config = @import("config.zig").Config;
pub const Entry = @import("entry.zig").Entry;
pub const Formatter = @import("formatter.zig").Formatter;
pub const Filter = @import("filter.zig").Filter;
pub const Walker = @import("walker.zig").Walker;

pub fn run(allocator: std.mem.Allocator, args: [][:0]u8) !void {
    // Default to current directory if no path provided
    const dir_path = if (args.len >= 2) args[1] else ".";

    // Create config from args (skip the "tree" command itself)
    const config = try Config.fromArgs(allocator, args);
    const walker = Walker.init(allocator, config);

    try walker.walk(dir_path);
}
