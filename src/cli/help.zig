const std = @import("std");

pub fn show(program_name: []const u8) void {
    std.debug.print("zz - CLI Utilities\n\n", .{});
    std.debug.print("Usage: {s} <command> [args...]\n\n", .{program_name});
    std.debug.print("Commands:\n", .{});
    std.debug.print("  tree [directory] [max_depth] [--format=FORMAT]\n", .{});
    std.debug.print("                                Show directory tree (defaults to current dir)\n", .{});
    std.debug.print("                                FORMAT: tree (default) or list\n", .{});
    std.debug.print("                                Alternative: -f FORMAT\n", .{});
    std.debug.print("  help                          Show this help\n", .{});
}
