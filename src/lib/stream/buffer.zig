const std = @import("std");
const StreamError = @import("error.zig").StreamError;

/// Fixed-capacity ring buffer for zero-allocation streaming
/// Optimized for cache-friendly sequential access patterns
pub fn RingBuffer(comptime T: type, comptime capacity: usize) type {
    return struct {
        const Self = @This();

        // Fixed-size array allocated on stack or inline in parent struct
        items: [capacity]T = undefined,
        head: usize = 0, // Next write position
        tail: usize = 0, // Next read position
        count: usize = 0, // Current number of items

        /// Initialize an empty ring buffer
        pub fn init() Self {
            return .{};
        }

        /// Push item to buffer, returns error if full
        pub fn push(self: *Self, item: T) StreamError!void {
            if (self.isFull()) {
                return StreamError.BufferFull;
            }

            self.items[self.head] = item;
            self.head = (self.head + 1) % capacity;
            self.count += 1;
        }

        /// Push item to buffer, overwriting oldest if full
        pub fn pushOverwrite(self: *Self, item: T) void {
            self.items[self.head] = item;
            self.head = (self.head + 1) % capacity;

            if (self.count == capacity) {
                // Buffer was full, advance tail to drop oldest
                self.tail = (self.tail + 1) % capacity;
            } else {
                self.count += 1;
            }
        }

        /// Pop item from buffer, returns null if empty
        pub fn pop(self: *Self) ?T {
            if (self.isEmpty()) {
                return null;
            }

            const item = self.items[self.tail];
            self.tail = (self.tail + 1) % capacity;
            self.count -= 1;
            return item;
        }

        /// Peek at next item without removing
        pub fn peek(self: *const Self) ?T {
            if (self.isEmpty()) {
                return null;
            }
            return self.items[self.tail];
        }

        /// Peek at item at offset from tail
        pub fn peekAt(self: *const Self, offset: usize) ?T {
            if (offset >= self.count) {
                return null;
            }
            const index = (self.tail + offset) % capacity;
            return self.items[index];
        }

        /// Check if buffer is full
        pub inline fn isFull(self: *const Self) bool {
            return self.count == capacity;
        }

        /// Check if buffer is empty
        pub inline fn isEmpty(self: *const Self) bool {
            return self.count == 0;
        }

        /// Get current number of items
        pub inline fn len(self: *const Self) usize {
            return self.count;
        }

        /// Get remaining capacity
        pub inline fn available(self: *const Self) usize {
            return capacity - self.count;
        }

        /// Clear all items
        pub fn clear(self: *Self) void {
            self.head = 0;
            self.tail = 0;
            self.count = 0;
        }

        /// Write multiple items at once
        pub fn write(self: *Self, items: []const T) StreamError!usize {
            var written: usize = 0;
            for (items) |item| {
                self.push(item) catch break;
                written += 1;
            }
            return written;
        }

        /// Read up to n items into buffer
        pub fn read(self: *Self, buffer: []T) usize {
            var read_count: usize = 0;
            while (read_count < buffer.len) : (read_count += 1) {
                buffer[read_count] = self.pop() orelse break;
            }
            return read_count;
        }

        /// Get slice of current items (may be non-contiguous)
        pub fn toSlice(self: *const Self, allocator: std.mem.Allocator) ![]T {
            if (self.isEmpty()) {
                return &[_]T{};
            }

            var result = try allocator.alloc(T, self.count);
            var i: usize = 0;
            var current = self.tail;

            while (i < self.count) : (i += 1) {
                result[i] = self.items[current];
                current = (current + 1) % capacity;
            }

            return result;
        }

        /// Iterator for consuming buffer items
        pub const Iterator = struct {
            buffer: *Self,

            pub fn next(self: *Iterator) ?T {
                return self.buffer.pop();
            }
        };

        /// Get iterator for consuming items
        pub fn iterator(self: *Self) Iterator {
            return .{ .buffer = self };
        }

        /// Get current capacity
        pub fn getCapacity(self: *const Self) usize {
            _ = self;
            return capacity;
        }
    };
}

/// Dynamic ring buffer that can grow (allocates)
pub fn DynamicRingBuffer(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        items: []T,
        head: usize = 0,
        tail: usize = 0,
        count: usize = 0,

        pub fn init(allocator: std.mem.Allocator, initial_capacity: usize) !Self {
            return .{
                .allocator = allocator,
                .items = try allocator.alloc(T, initial_capacity),
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.items);
        }

        pub fn push(self: *Self, item: T) !void {
            if (self.count == self.items.len) {
                try self.grow();
            }

            self.items[self.head] = item;
            self.head = (self.head + 1) % self.items.len;
            self.count += 1;
        }

        pub fn pop(self: *Self) ?T {
            if (self.count == 0) {
                return null;
            }

            const item = self.items[self.tail];
            self.tail = (self.tail + 1) % self.items.len;
            self.count -= 1;
            return item;
        }

        fn grow(self: *Self) !void {
            const new_capacity = self.items.len * 2;
            var new_items = try self.allocator.alloc(T, new_capacity);

            // Copy items in order
            var i: usize = 0;
            var current = self.tail;
            while (i < self.count) : (i += 1) {
                new_items[i] = self.items[current];
                current = (current + 1) % self.items.len;
            }

            self.allocator.free(self.items);
            self.items = new_items;
            self.tail = 0;
            self.head = self.count;
        }
    };
}

test "RingBuffer basic operations" {
    var buffer = RingBuffer(u32, 4).init();

    try buffer.push(1);
    try buffer.push(2);
    try buffer.push(3);

    try std.testing.expectEqual(@as(usize, 3), buffer.len());
    try std.testing.expectEqual(@as(?u32, 1), buffer.pop());
    try std.testing.expectEqual(@as(?u32, 2), buffer.pop());
    try std.testing.expectEqual(@as(?u32, 3), buffer.pop());
    try std.testing.expectEqual(@as(?u32, null), buffer.pop());
}

test "RingBuffer wrap around" {
    var buffer = RingBuffer(u32, 3).init();

    try buffer.push(1);
    try buffer.push(2);
    try buffer.push(3);
    try std.testing.expectError(StreamError.BufferFull, buffer.push(4));

    try std.testing.expectEqual(@as(?u32, 1), buffer.pop());
    try buffer.push(4);

    try std.testing.expectEqual(@as(?u32, 2), buffer.pop());
    try std.testing.expectEqual(@as(?u32, 3), buffer.pop());
    try std.testing.expectEqual(@as(?u32, 4), buffer.pop());
}

test "RingBuffer overwrite mode" {
    var buffer = RingBuffer(u32, 3).init();

    buffer.pushOverwrite(1);
    buffer.pushOverwrite(2);
    buffer.pushOverwrite(3);
    buffer.pushOverwrite(4); // Overwrites 1

    try std.testing.expectEqual(@as(?u32, 2), buffer.pop());
    try std.testing.expectEqual(@as(?u32, 3), buffer.pop());
    try std.testing.expectEqual(@as(?u32, 4), buffer.pop());
}

test "RingBuffer batch operations" {
    var buffer = RingBuffer(u32, 10).init();
    const data = [_]u32{ 1, 2, 3, 4, 5 };

    const written = try buffer.write(&data);
    try std.testing.expectEqual(@as(usize, 5), written);

    var output: [3]u32 = undefined;
    const read_count = buffer.read(&output);
    try std.testing.expectEqual(@as(usize, 3), read_count);
    try std.testing.expectEqual(@as(u32, 1), output[0]);
    try std.testing.expectEqual(@as(u32, 2), output[1]);
    try std.testing.expectEqual(@as(u32, 3), output[2]);
}
