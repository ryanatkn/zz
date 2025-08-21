/// Source types for DirectStream
/// These are the basic stream sources that produce values
const std = @import("std");
const StreamError = @import("error.zig").StreamError;
const RingBuffer = @import("buffer.zig").RingBuffer;

/// Stream from a slice - zero-copy
/// Optimized for maximum performance with inline dispatch
pub fn SliceStream(comptime T: type) type {
    return struct {
        data: []const T,
        position: usize = 0,

        const Self = @This();

        pub fn init(data: []const T) Self {
            return .{ .data = data };
        }

        pub inline fn next(self: *Self) StreamError!?T {
            if (self.position >= self.data.len) {
                return null;
            }
            const value = self.data[self.position];
            self.position += 1;
            return value;
        }

        pub inline fn peek(self: *const Self) StreamError!?T {
            if (self.position >= self.data.len) {
                return null;
            }
            return self.data[self.position];
        }

        pub inline fn skip(self: *Self, n: usize) StreamError!void {
            self.position = @min(self.position + n, self.data.len);
        }

        pub inline fn getPosition(self: *const Self) usize {
            return self.position;
        }

        pub inline fn isExhausted(self: *const Self) bool {
            return self.position >= self.data.len;
        }

        pub inline fn close(self: *Self) void {
            _ = self;
        }
    };
}

/// Stream from a ring buffer
pub fn RingBufferStream(comptime T: type) type {
    return struct {
        buffer: *RingBuffer(T, 4096),

        const Self = @This();

        pub fn init(buffer: *RingBuffer(T, 4096)) Self {
            return .{ .buffer = buffer };
        }

        pub inline fn next(self: *Self) StreamError!?T {
            return self.buffer.pop();
        }

        pub fn peek(self: *const Self) StreamError!?T {
            return self.buffer.peek();
        }

        pub fn skip(self: *Self, n: usize) StreamError!void {
            var i: usize = 0;
            while (i < n) : (i += 1) {
                _ = self.buffer.pop() orelse break;
            }
        }

        pub fn getPosition(self: *const Self) usize {
            _ = self;
            return 0; // Ring buffers don't track position
        }

        pub fn isExhausted(self: *const Self) bool {
            return self.buffer.isEmpty();
        }

        pub fn close(self: *Self) void {
            _ = self;
        }
    };
}

/// Generator stream - computes values on demand
pub fn GeneratorStream(comptime T: type) type {
    return struct {
        state: *anyopaque,
        gen_fn: *const fn (*anyopaque) ?T,
        cleanup_fn: ?*const fn (*anyopaque) void = null,
        position: usize = 0,

        const Self = @This();

        pub fn init(state: *anyopaque, gen_fn: *const fn (*anyopaque) ?T) Self {
            return .{ .state = state, .gen_fn = gen_fn, .cleanup_fn = null };
        }

        pub fn initWithCleanup(
            state: *anyopaque,
            gen_fn: *const fn (*anyopaque) ?T,
            cleanup_fn: *const fn (*anyopaque) void,
        ) Self {
            return .{ .state = state, .gen_fn = gen_fn, .cleanup_fn = cleanup_fn };
        }

        pub inline fn next(self: *Self) StreamError!?T {
            if (self.gen_fn(self.state)) |value| {
                self.position += 1;
                return value;
            }
            return null;
        }

        pub fn peek(self: *const Self) StreamError!?T {
            _ = self;
            return StreamError.NotSupported; // Generators can't peek
        }

        pub fn skip(self: *Self, n: usize) StreamError!void {
            var i: usize = 0;
            while (i < n) : (i += 1) {
                _ = self.gen_fn(self.state) orelse break;
                self.position += 1;
            }
        }

        pub fn getPosition(self: *const Self) usize {
            return self.position;
        }

        pub fn isExhausted(self: *const Self) bool {
            _ = self;
            return false; // Can't know without consuming
        }

        pub fn close(self: *Self) void {
            if (self.cleanup_fn) |cleanup| {
                cleanup(self.state);
            }
        }
    };
}

/// Empty stream - always returns null
pub fn EmptyStream(comptime T: type) type {
    return struct {
        const Self = @This();

        pub fn init() Self {
            return .{};
        }

        pub fn next(self: *Self) StreamError!?T {
            _ = self;
            return null;
        }

        pub fn peek(self: *const Self) StreamError!?T {
            _ = self;
            return null;
        }

        pub fn skip(self: *Self, n: usize) StreamError!void {
            _ = self;
            _ = n;
        }

        pub fn getPosition(self: *const Self) usize {
            _ = self;
            return 0;
        }

        pub fn isExhausted(self: *const Self) bool {
            _ = self;
            return true;
        }

        pub fn close(self: *Self) void {
            _ = self;
        }
    };
}

/// Error stream - always returns an error
pub fn ErrorStream(comptime T: type) type {
    return struct {
        err: StreamError,

        const Self = @This();

        pub fn init(err: StreamError) Self {
            return .{ .err = err };
        }

        pub fn next(self: *Self) StreamError!?T {
            return self.err;
        }

        pub fn peek(self: *const Self) StreamError!?T {
            return self.err;
        }

        pub fn skip(self: *Self, n: usize) StreamError!void {
            _ = n;
            return self.err;
        }

        pub fn getPosition(self: *const Self) usize {
            _ = self;
            return 0;
        }

        pub fn isExhausted(self: *const Self) bool {
            _ = self;
            return false;
        }

        pub fn close(self: *Self) void {
            _ = self;
        }
    };
}
