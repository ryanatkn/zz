const std = @import("std");

pub fn show(program_name: []const u8) void {
    std.debug.print("zz - CLI utility toolkit\n\n", .{});
    std.debug.print("Usage: {s} <command> [args...]\n\n", .{program_name});
    std.debug.print("Commands:\n", .{});
    std.debug.print("  tree [directory] [max_depth]  Show directory tree (defaults to current dir)\n", .{});
    std.debug.print("  yar                           Play YAR - 2D top-down RPG\n", .{});
    std.debug.print("  help                          Show this help\n", .{});
}
