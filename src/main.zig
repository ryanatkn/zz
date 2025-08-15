const std = @import("std");
const cli = @import("cli/main.zig");
const RealFilesystem = @import("lib/filesystem/real.zig").RealFilesystem;
const registry = @import("lib/language/registry.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create the filesystem once at the top level
    const filesystem = RealFilesystem.init();

    // Cleanup global registry on exit
    defer registry.deinitGlobalRegistry();

    try cli.run(allocator, filesystem);
}
