const std = @import("std");
const Stream = @import("mod.zig").Stream;
const StreamError = @import("error.zig").StreamError;

/// Union of all stream source types
pub const StreamSource = union(enum) {
    memory: MemorySource,
    file: FileSource,
    generator: GeneratorSource,

    pub fn stream(self: *StreamSource) Stream(u8) {
        return switch (self.*) {
            .memory => |*s| s.stream(),
            .file => |*s| s.stream(),
            .generator => |*s| s.stream(),
        };
    }
};

/// Memory-based stream source (zero-copy slice iteration)
pub fn MemorySource(comptime T: type) type {
    return struct {
        const Self = @This();

        data: []const T,
        position: usize = 0,

        pub fn init(data: []const T) Self {
            return .{ .data = data };
        }

        pub fn next(self: *Self) StreamError!?T {
            if (self.position >= self.data.len) {
                return null;
            }
            const item = self.data[self.position];
            self.position += 1;
            return item;
        }

        pub fn peek(self: *const Self) StreamError!?T {
            if (self.position >= self.data.len) {
                return null;
            }
            return self.data[self.position];
        }

        pub fn skip(self: *Self, n: usize) StreamError!void {
            self.position = @min(self.position + n, self.data.len);
        }

        pub fn close(self: *Self) void {
            _ = self;
        }

        pub fn getPosition(self: *const Self) usize {
            return self.position;
        }

        pub fn isExhausted(self: *const Self) bool {
            return self.position >= self.data.len;
        }

        pub fn stream(self: *Self) Stream(T) {
            return .{
                .ptr = @ptrCast(self),
                .vtable = &.{
                    .nextFn = @ptrCast(&next),
                    .peekFn = @ptrCast(&peek),
                    .skipFn = @ptrCast(&skip),
                    .closeFn = @ptrCast(&close),
                    .getPositionFn = @ptrCast(&getPosition),
                    .isExhaustedFn = @ptrCast(&isExhausted),
                },
            };
        }

        /// Reset to beginning
        pub fn reset(self: *Self) void {
            self.position = 0;
        }

        /// Get remaining items
        pub fn remaining(self: *const Self) usize {
            if (self.position >= self.data.len) return 0;
            return self.data.len - self.position;
        }
    };
}

/// File-based stream source with buffered reading
pub const FileSource = struct {
    file: std.fs.File,
    buffer: [4096]u8 = undefined,
    buffer_len: usize = 0,
    buffer_pos: usize = 0,
    position: usize = 0,
    eof: bool = false,

    pub fn init(file: std.fs.File) FileSource {
        return .{ .file = file };
    }

    pub fn next(self: *FileSource) StreamError!?u8 {
        if (self.buffer_pos >= self.buffer_len) {
            if (self.eof) return null;

            // Refill buffer
            self.buffer_len = self.file.read(&self.buffer) catch |err| {
                return switch (err) {
                    error.EndOfStream => {
                        self.eof = true;
                        return null;
                    },
                    else => StreamError.IoError,
                };
            };

            if (self.buffer_len == 0) {
                self.eof = true;
                return null;
            }

            self.buffer_pos = 0;
        }

        const byte = self.buffer[self.buffer_pos];
        self.buffer_pos += 1;
        self.position += 1;
        return byte;
    }

    pub fn peek(self: *const FileSource) StreamError!?u8 {
        if (self.buffer_pos >= self.buffer_len) {
            if (self.eof) return null;
            return StreamError.NotSupported; // Would need to modify state
        }
        return self.buffer[self.buffer_pos];
    }

    pub fn skip(self: *FileSource, n: usize) StreamError!void {
        var remaining = n;
        while (remaining > 0) {
            const in_buffer = @min(remaining, self.buffer_len - self.buffer_pos);
            self.buffer_pos += in_buffer;
            self.position += in_buffer;
            remaining -= in_buffer;

            if (remaining > 0) {
                _ = try self.next(); // Force buffer refill
                if (self.eof) break;
                self.buffer_pos -= 1; // Undo the increment from next()
                self.position -= 1;
            }
        }
    }

    pub fn close(self: *FileSource) void {
        self.file.close();
    }

    pub fn getPosition(self: *const FileSource) usize {
        return self.position;
    }

    pub fn isExhausted(self: *const FileSource) bool {
        return self.eof and self.buffer_pos >= self.buffer_len;
    }

    pub fn stream(self: *FileSource) Stream(u8) {
        return .{
            .ptr = @ptrCast(self),
            .vtable = &.{
                .nextFn = @ptrCast(&next),
                .peekFn = @ptrCast(&peek),
                .skipFn = @ptrCast(&skip),
                .closeFn = @ptrCast(&close),
                .getPositionFn = @ptrCast(&getPosition),
                .isExhaustedFn = @ptrCast(&isExhausted),
            },
        };
    }
};

/// Generator-based stream source (produces values on demand)
pub const GeneratorSource = struct {
    state: *anyopaque,
    generateFn: *const fn (state: *anyopaque) ?u8,
    position: usize = 0,
    next_value: ?u8 = null,
    exhausted: bool = false,

    pub fn init(
        state: *anyopaque,
        generateFn: *const fn (state: *anyopaque) ?u8,
    ) GeneratorSource {
        return .{
            .state = state,
            .generateFn = generateFn,
        };
    }

    pub fn next(self: *GeneratorSource) StreamError!?u8 {
        if (self.exhausted) return null;

        const value = if (self.next_value) |v| blk: {
            self.next_value = null;
            break :blk v;
        } else self.generateFn(self.state);

        if (value) |v| {
            self.position += 1;
            return v;
        } else {
            self.exhausted = true;
            return null;
        }
    }

    pub fn peek(self: *GeneratorSource) StreamError!?u8 {
        if (self.exhausted) return null;

        if (self.next_value == null) {
            self.next_value = self.generateFn(self.state);
            if (self.next_value == null) {
                self.exhausted = true;
            }
        }

        return self.next_value;
    }

    pub fn skip(self: *GeneratorSource, n: usize) StreamError!void {
        var i: usize = 0;
        while (i < n) : (i += 1) {
            _ = try self.next() orelse break;
        }
    }

    pub fn close(self: *GeneratorSource) void {
        _ = self;
    }

    pub fn getPosition(self: *const GeneratorSource) usize {
        return self.position;
    }

    pub fn isExhausted(self: *const GeneratorSource) bool {
        return self.exhausted;
    }

    pub fn stream(self: *GeneratorSource) Stream(u8) {
        return .{
            .ptr = @ptrCast(self),
            .vtable = &.{
                .nextFn = @ptrCast(&next),
                .peekFn = @ptrCast(&peek),
                .skipFn = @ptrCast(&skip),
                .closeFn = @ptrCast(&close),
                .getPositionFn = @ptrCast(&getPosition),
                .isExhaustedFn = @ptrCast(&isExhausted),
            },
        };
    }
};

/// Network stream source (placeholder for future implementation)
pub const NetworkSource = struct {
    // TODO: Phase 3 - Implement NetworkSource for streaming from sockets
    // TODO: Phase 3 - Add mmap support for FileSource (zero-copy file reading)
};

test "MemorySource basic operations" {
    const data = [_]u32{ 1, 2, 3, 4, 5 };
    var source = MemorySource(u32).init(&data);
    var stream = source.stream();

    try std.testing.expectEqual(@as(?u32, 1), try stream.next());
    try std.testing.expectEqual(@as(?u32, 2), try stream.next());
    try std.testing.expectEqual(@as(usize, 2), stream.getPosition());

    try stream.skip(2);
    try std.testing.expectEqual(@as(?u32, 5), try stream.next());
    try std.testing.expectEqual(@as(?u32, null), try stream.next());
}

test "MemorySource peek operation" {
    const data = "hello";
    var source = MemorySource(u8).init(data);
    var stream = source.stream();

    try std.testing.expectEqual(@as(?u8, 'h'), try stream.peek());
    try std.testing.expectEqual(@as(?u8, 'h'), try stream.next());
    try std.testing.expectEqual(@as(?u8, 'e'), try stream.peek());
    try std.testing.expectEqual(@as(?u8, 'e'), try stream.peek());
    try std.testing.expectEqual(@as(?u8, 'e'), try stream.next());
}

test "GeneratorSource" {
    const CounterState = struct {
        count: u8 = 0,
        max: u8 = 5,
    };

    var state = CounterState{};

    const genFn = struct {
        fn generate(s: *anyopaque) ?u8 {
            const counter = @as(*CounterState, @ptrCast(@alignCast(s)));
            if (counter.count >= counter.max) return null;
            counter.count += 1;
            return counter.count;
        }
    }.generate;

    var source = GeneratorSource.init(@ptrCast(&state), genFn);
    var stream = source.stream();

    try std.testing.expectEqual(@as(?u8, 1), try stream.next());
    try std.testing.expectEqual(@as(?u8, 2), try stream.next());
    try std.testing.expectEqual(@as(?u8, 3), try stream.peek());
    try std.testing.expectEqual(@as(?u8, 3), try stream.next());
}
