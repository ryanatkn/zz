const std = @import("std");

const cli = @import("cli/main.zig");
const RealFilesystem = @import("filesystem/real.zig").RealFilesystem;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create the filesystem once at the top level
    const filesystem = RealFilesystem.init();

    try cli.run(allocator, filesystem);
}
