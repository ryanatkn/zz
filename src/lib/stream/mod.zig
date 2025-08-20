/// Stream module - Generic streaming infrastructure for zero-allocation data flow
/// Provides Stream(T) type with composable operators, ring buffers, and sources/sinks
const std = @import("std");

// Re-export core stream types and functions
pub const Stream = @import("stream.zig").Stream;
pub const fromSlice = @import("stream.zig").fromSlice;
pub const fromIterator = @import("stream.zig").fromIterator;
pub const StreamStats = @import("stream.zig").StreamStats;

// Re-export key types from other modules
pub const StreamError = @import("error.zig").StreamError;
pub const RingBuffer = @import("buffer.zig").RingBuffer;
pub const StreamSource = @import("source.zig").StreamSource;
pub const MemorySource = @import("source.zig").MemorySource;
pub const FileSource = @import("source.zig").FileSource;
pub const StreamSink = @import("sink.zig").StreamSink;
pub const BufferSink = @import("sink.zig").BufferSink;
pub const NullSink = @import("sink.zig").NullSink;
pub const operators = @import("operators.zig");
pub const fusion = @import("fusion.zig");

test "Stream basic operations" {
    const data = [_]u32{ 1, 2, 3, 4, 5 };
    var stream = fromSlice(u32, &data);

    try std.testing.expectEqual(@as(?u32, 1), try stream.next());
    try std.testing.expectEqual(@as(?u32, 2), try stream.next());
    try std.testing.expectEqual(@as(usize, 2), stream.getPosition());
}

test "Stream map operation" {
    const data = [_]u32{ 1, 2, 3 };
    var stream = fromSlice(u32, &data);

    const double = struct {
        fn f(x: u32) u32 {
            return x * 2;
        }
    }.f;

    var mapped = stream.map(u32, &double);
    try std.testing.expectEqual(@as(?u32, 2), try mapped.next());
    try std.testing.expectEqual(@as(?u32, 4), try mapped.next());
    try std.testing.expectEqual(@as(?u32, 6), try mapped.next());
}
