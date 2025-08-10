const std = @import("std");

pub const Config = @import("config.zig").Config;
pub const Entry = @import("entry.zig").Entry;
pub const Formatter = @import("formatter.zig").Formatter;
pub const Filter = @import("filter.zig").Filter;
pub const Walker = @import("walker.zig").Walker;

pub fn run(allocator: std.mem.Allocator, args: [][:0]const u8) !void {
    return runWithQuiet(allocator, args, false);
}

pub fn runQuiet(allocator: std.mem.Allocator, args: [][:0]const u8) !void {
    return runWithQuiet(allocator, args, true);
}

fn runWithQuiet(allocator: std.mem.Allocator, args: [][:0]const u8, quiet: bool) !void {
    // Default to current directory if no path provided
    const dir_path = if (args.len >= 2) args[1] else ".";

    // Create config from args (skip the "tree" command itself)
    var config = try Config.fromArgs(allocator, args);
    defer config.deinit(allocator);

    const walker = if (quiet)
        Walker.initQuiet(allocator, config)
    else
        Walker.init(allocator, config);

    try walker.walk(dir_path);
}
