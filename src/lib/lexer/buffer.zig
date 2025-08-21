/// Buffer management for streaming lexers
///
/// Provides efficient buffer management for zero-copy streaming tokenization.
const std = @import("std");

/// Ring buffer for streaming input
pub const StreamBuffer = struct {
    data: []u8,
    head: usize = 0,
    tail: usize = 0,
    capacity: usize,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, capacity: usize) !Self {
        return .{
            .data = try allocator.alloc(u8, capacity),
            .capacity = capacity,
        };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
    }

    /// Write data to buffer
    pub fn write(self: *Self, data: []const u8) usize {
        const available = self.availableWrite();
        const to_write = @min(available, data.len);

        if (to_write == 0) return 0;

        const tail_to_end = self.capacity - self.tail;
        if (to_write <= tail_to_end) {
            @memcpy(self.data[self.tail..][0..to_write], data[0..to_write]);
        } else {
            @memcpy(self.data[self.tail..], data[0..tail_to_end]);
            @memcpy(self.data[0 .. to_write - tail_to_end], data[tail_to_end..to_write]);
        }

        self.tail = (self.tail + to_write) % self.capacity;
        return to_write;
    }

    /// Read data from buffer
    pub fn read(self: *Self, buf: []u8) usize {
        const available = self.availableRead();
        const to_read = @min(available, buf.len);

        if (to_read == 0) return 0;

        const head_to_end = self.capacity - self.head;
        if (to_read <= head_to_end) {
            @memcpy(buf[0..to_read], self.data[self.head..][0..to_read]);
        } else {
            @memcpy(buf[0..head_to_end], self.data[self.head..]);
            @memcpy(buf[head_to_end..to_read], self.data[0 .. to_read - head_to_end]);
        }

        self.head = (self.head + to_read) % self.capacity;
        return to_read;
    }

    /// Peek at data without consuming
    pub fn peek(self: *Self, buf: []u8) usize {
        const available = self.availableRead();
        const to_read = @min(available, buf.len);

        if (to_read == 0) return 0;

        const head_to_end = self.capacity - self.head;
        if (to_read <= head_to_end) {
            @memcpy(buf[0..to_read], self.data[self.head..][0..to_read]);
        } else {
            @memcpy(buf[0..head_to_end], self.data[self.head..]);
            @memcpy(buf[head_to_end..to_read], self.data[0 .. to_read - head_to_end]);
        }

        return to_read;
    }

    /// Skip n bytes
    pub fn skip(self: *Self, n: usize) void {
        const to_skip = @min(n, self.availableRead());
        self.head = (self.head + to_skip) % self.capacity;
    }

    fn availableRead(self: *Self) usize {
        if (self.tail >= self.head) {
            return self.tail - self.head;
        } else {
            return self.capacity - self.head + self.tail;
        }
    }

    fn availableWrite(self: *Self) usize {
        if (self.tail >= self.head) {
            return self.capacity - (self.tail - self.head) - 1;
        } else {
            return self.head - self.tail - 1;
        }
    }
};

/// Lookahead buffer for lexers that need to peek ahead
pub const LookaheadBuffer = struct {
    source: []const u8,
    position: usize = 0,
    mark: ?usize = null,

    const Self = @This();

    pub fn init(source: []const u8) Self {
        return .{ .source = source };
    }

    pub fn current(self: *Self) ?u8 {
        if (self.position >= self.source.len) return null;
        return self.source[self.position];
    }

    pub fn peek(self: *Self, offset: usize) ?u8 {
        const pos = self.position + offset;
        if (pos >= self.source.len) return null;
        return self.source[pos];
    }

    pub fn advance(self: *Self) void {
        if (self.position < self.source.len) {
            self.position += 1;
        }
    }

    pub fn skip(self: *Self, n: usize) void {
        self.position = @min(self.position + n, self.source.len);
    }

    pub fn setMark(self: *Self) void {
        self.mark = self.position;
    }

    pub fn resetToMark(self: *Self) void {
        if (self.mark) |m| {
            self.position = m;
        }
    }

    pub fn slice(self: *Self, start: usize, end: usize) []const u8 {
        const actual_end = @min(end, self.source.len);
        return self.source[start..actual_end];
    }

    pub fn remaining(self: *Self) []const u8 {
        return self.source[self.position..];
    }

    pub fn isEof(self: *Self) bool {
        return self.position >= self.source.len;
    }
};
