const std = @import("std");
const StreamError = @import("error.zig").StreamError;
const RingBuffer = @import("buffer.zig").RingBuffer;

/// Union of all stream sink types
pub const StreamSink = union(enum) {
    buffer: BufferSink,
    file: FileSink,
    null: NullSink,
    channel: ChannelSink,

    pub fn write(self: *StreamSink, data: []const u8) StreamError!usize {
        return switch (self.*) {
            .buffer => |*s| s.write(data),
            .file => |*s| s.write(data),
            .null => |*s| s.write(data),
            .channel => |*s| s.write(data),
        };
    }

    pub fn close(self: *StreamSink) void {
        switch (self.*) {
            .buffer => |*s| s.close(),
            .file => |*s| s.close(),
            .null => |*s| s.close(),
            .channel => |*s| s.close(),
        }
    }
};

/// Buffer-based sink that accumulates data in memory
pub const BufferSink = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),
    max_size: ?usize = null,

    pub fn init(allocator: std.mem.Allocator) BufferSink {
        return .{
            .allocator = allocator,
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn initWithCapacity(allocator: std.mem.Allocator, capacity: usize) !BufferSink {
        var buffer = std.ArrayList(u8).init(allocator);
        try buffer.ensureTotalCapacity(capacity);
        return .{
            .allocator = allocator,
            .buffer = buffer,
        };
    }

    pub fn deinit(self: *BufferSink) void {
        self.buffer.deinit();
    }

    pub fn write(self: *BufferSink, data: []const u8) StreamError!usize {
        if (self.max_size) |max| {
            const available = max -| self.buffer.items.len;
            if (available == 0) {
                return StreamError.BufferFull;
            }
            const to_write = @min(data.len, available);
            self.buffer.appendSlice(data[0..to_write]) catch {
                return StreamError.OutOfMemory;
            };
            return to_write;
        } else {
            self.buffer.appendSlice(data) catch {
                return StreamError.OutOfMemory;
            };
            return data.len;
        }
    }

    pub fn writeItem(self: *BufferSink, item: u8) StreamError!void {
        if (self.max_size) |max| {
            if (self.buffer.items.len >= max) {
                return StreamError.BufferFull;
            }
        }
        self.buffer.append(item) catch {
            return StreamError.OutOfMemory;
        };
    }

    pub fn close(self: *BufferSink) void {
        _ = self;
    }

    pub fn getBuffer(self: *const BufferSink) []const u8 {
        return self.buffer.items;
    }

    pub fn clear(self: *BufferSink) void {
        self.buffer.clearRetainingCapacity();
    }

    pub fn toOwnedSlice(self: *BufferSink) ![]u8 {
        return self.buffer.toOwnedSlice();
    }
};

/// File-based sink with buffered writing
pub const FileSink = struct {
    file: std.fs.File,
    buffer: [4096]u8 = undefined,
    buffer_len: usize = 0,
    total_written: usize = 0,

    pub fn init(file: std.fs.File) FileSink {
        return .{ .file = file };
    }

    pub fn write(self: *FileSink, data: []const u8) StreamError!usize {
        var written: usize = 0;

        // If data fits in buffer, just buffer it
        if (self.buffer_len + data.len <= self.buffer.len) {
            @memcpy(self.buffer[self.buffer_len..][0..data.len], data);
            self.buffer_len += data.len;
            written = data.len;
        } else {
            // Flush existing buffer first
            if (self.buffer_len > 0) {
                try self.flush();
            }

            // Write large data directly
            if (data.len >= self.buffer.len) {
                written = self.file.write(data) catch {
                    return StreamError.IoError;
                };
            } else {
                // Buffer small data
                @memcpy(self.buffer[0..data.len], data);
                self.buffer_len = data.len;
                written = data.len;
            }
        }

        self.total_written += written;
        return written;
    }

    pub fn flush(self: *FileSink) StreamError!void {
        if (self.buffer_len == 0) return;

        _ = self.file.write(self.buffer[0..self.buffer_len]) catch {
            return StreamError.IoError;
        };
        self.buffer_len = 0;
    }

    pub fn close(self: *FileSink) void {
        _ = self.flush() catch {};
        self.file.close();
    }

    pub fn getTotalWritten(self: *const FileSink) usize {
        return self.total_written;
    }
};

/// Null sink that discards all data (like /dev/null)
pub const NullSink = struct {
    bytes_written: usize = 0,

    pub fn init() NullSink {
        return .{};
    }

    pub fn write(self: *NullSink, data: []const u8) StreamError!usize {
        self.bytes_written += data.len;
        return data.len;
    }

    pub fn close(self: *NullSink) void {
        _ = self;
    }

    pub fn getBytesWritten(self: *const NullSink) usize {
        return self.bytes_written;
    }
};

/// Channel-based sink for inter-thread communication
pub const ChannelSink = struct {
    buffer: *RingBuffer(u8, 4096),
    closed: bool = false,

    pub fn init(buffer: *RingBuffer(u8, 4096)) ChannelSink {
        return .{ .buffer = buffer };
    }

    pub fn write(self: *ChannelSink, data: []const u8) StreamError!usize {
        if (self.closed) {
            return StreamError.StreamClosed;
        }

        var written: usize = 0;
        for (data) |byte| {
            self.buffer.push(byte) catch {
                if (written == 0) {
                    return StreamError.BufferFull;
                }
                break;
            };
            written += 1;
        }

        return written;
    }

    pub fn close(self: *ChannelSink) void {
        self.closed = true;
    }

    pub fn isClosed(self: *const ChannelSink) bool {
        return self.closed;
    }
};

/// Tee sink that writes to multiple sinks
pub fn TeeSink(comptime n: usize) type {
    return struct {
        sinks: [n]*StreamSink,

        pub fn write(self: *@This(), data: []const u8) StreamError!usize {
            var min_written: usize = data.len;
            for (self.sinks) |sink| {
                const written = try sink.write(data);
                min_written = @min(min_written, written);
            }
            return min_written;
        }

        pub fn close(self: *@This()) void {
            for (self.sinks) |sink| {
                sink.close();
            }
        }
    };
}

test "BufferSink basic operations" {
    var sink = BufferSink.init(std.testing.allocator);
    defer sink.deinit();

    _ = try sink.write("Hello, ");
    _ = try sink.write("World!");

    const result = sink.getBuffer();
    try std.testing.expectEqualStrings("Hello, World!", result);
}

test "BufferSink with max size" {
    var sink = BufferSink.init(std.testing.allocator);
    defer sink.deinit();
    sink.max_size = 5;

    const written = try sink.write("Hello");
    try std.testing.expectEqual(@as(usize, 5), written);

    try std.testing.expectError(StreamError.BufferFull, sink.write("World"));
}

test "NullSink" {
    var sink = NullSink.init();

    _ = try sink.write("Hello");
    _ = try sink.write("World");

    try std.testing.expectEqual(@as(usize, 10), sink.getBytesWritten());
}

test "ChannelSink" {
    var buffer = RingBuffer(u8, 4096).init();
    var sink = ChannelSink.init(&buffer);

    _ = try sink.write("Test");

    try std.testing.expectEqual(@as(?u8, 'T'), buffer.pop());
    try std.testing.expectEqual(@as(?u8, 'e'), buffer.pop());
    try std.testing.expectEqual(@as(?u8, 's'), buffer.pop());
    try std.testing.expectEqual(@as(?u8, 't'), buffer.pop());
}
