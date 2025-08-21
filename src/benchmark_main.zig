const std = @import("std");
const benchmark_main = @import("benchmark/main.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Skip program name, pass rest to benchmark runner
    const benchmark_args = if (args.len > 1) @as([][:0]const u8, @ptrCast(args[1..])) else @as([][:0]const u8, @ptrCast(args[0..0]));
    try benchmark_main.run(allocator, benchmark_args);
}
