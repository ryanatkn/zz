const std = @import("std");

// NOTE: Legacy benchmark.zig deleted - this module needs reimplementation
// TODO: Reimplement benchmark functionality in new architecture

pub const OutputFormat = enum {
    markdown,
    json,
    csv,
    pretty,

    pub fn fromString(s: []const u8) ?OutputFormat {
        if (std.mem.eql(u8, s, "markdown")) return .markdown;
        if (std.mem.eql(u8, s, "json")) return .json;
        if (std.mem.eql(u8, s, "csv")) return .csv;
        if (std.mem.eql(u8, s, "pretty")) return .pretty;
        return null;
    }
};

pub fn run(_: std.mem.Allocator, _: [][:0]const u8) !void {
    std.debug.print("Benchmark functionality temporarily disabled - lib/benchmark.zig was deleted during legacy cleanup\n", .{});
    std.debug.print("TODO: Reimplement benchmarking in new architecture\n", .{});
}