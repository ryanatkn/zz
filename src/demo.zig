const std = @import("std");
const demo_main = @import("demo/main.zig");

pub fn run(allocator: std.mem.Allocator, args: [][:0]const u8) !void {
    _ = args; // Ignore args for now
    _ = allocator; // Not needed for the new demo
    try demo_main.main();
}
