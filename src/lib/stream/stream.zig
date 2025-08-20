const std = @import("std");
const StreamError = @import("error.zig").StreamError;
const operators = @import("operators.zig");
const MemorySource = @import("source.zig").MemorySource;

/// Generic streaming interface for zero-allocation data flow
/// Designed for composition and lazy evaluation
pub fn Stream(comptime T: type) type {
    return struct {
        const Self = @This();

        // Core vtable for stream operations (zero-cost abstraction)
        ptr: *anyopaque,
        vtable: *const VTable,

        pub const VTable = struct {
            // Core operations
            nextFn: *const fn (ptr: *anyopaque) StreamError!?T,
            peekFn: *const fn (ptr: *const anyopaque) StreamError!?T,
            skipFn: *const fn (ptr: *anyopaque, n: usize) StreamError!void,
            closeFn: *const fn (ptr: *anyopaque) void,

            // Metadata
            getPositionFn: *const fn (ptr: *const anyopaque) usize,
            isExhaustedFn: *const fn (ptr: *const anyopaque) bool,
        };

        /// Get next item from stream, advancing position
        pub inline fn next(self: *Self) StreamError!?T {
            return self.vtable.nextFn(self.ptr);
        }

        /// Peek at next item without advancing
        pub inline fn peek(self: *const Self) StreamError!?T {
            return self.vtable.peekFn(self.ptr);
        }

        /// Skip n items in the stream
        pub inline fn skip(self: *Self, n: usize) StreamError!void {
            return self.vtable.skipFn(self.ptr, n);
        }

        /// Close the stream and release resources
        pub inline fn close(self: *Self) void {
            self.vtable.closeFn(self.ptr);
        }

        /// Get current position in stream
        pub inline fn getPosition(self: *const Self) usize {
            return self.vtable.getPositionFn(self.ptr);
        }

        /// Check if stream is exhausted
        pub inline fn isExhausted(self: *const Self) bool {
            return self.vtable.isExhaustedFn(self.ptr);
        }

        /// Map stream elements through a function
        pub fn map(self: Self, comptime U: type, mapFn: *const fn (T) U) Stream(U) {
            return operators.map(T, U, self, mapFn);
        }

        /// Filter stream elements by predicate
        pub fn filter(self: Self, predicate: *const fn (T) bool) Stream(T) {
            return operators.filter(T, self, predicate);
        }

        /// Batch stream elements into fixed-size arrays
        pub fn batch(self: Self, size: usize) Stream([]T) {
            return operators.batch(T, self, size);
        }

        /// Collect all stream elements into an array
        pub fn collect(self: *Self, allocator: std.mem.Allocator) StreamError![]T {
            var items = std.ArrayList(T).init(allocator);
            defer items.deinit();

            while (try self.next()) |item| {
                try items.append(item);
            }

            return items.toOwnedSlice();
        }

        /// Count total items in stream (consumes stream)
        pub fn count(self: *Self) StreamError!usize {
            var n: usize = 0;
            while (try self.next()) |_| {
                n += 1;
            }
            return n;
        }

        /// Take first n items from stream
        pub fn take(self: Self, n: usize) Stream(T) {
            return operators.take(T, self, n);
        }

        /// Drop first n items from stream
        pub fn drop(self: Self, n: usize) Stream(T) {
            return operators.drop(T, self, n);
        }
    };
}

/// Create a stream from a slice (zero-copy)
/// TODO: Phase 2 - Add arena allocator support
/// Stream chains should use arena for all operators
/// Allows bulk free at end of pipeline
pub fn fromSlice(comptime T: type, slice: []const T) Stream(T) {
    const src_ptr = std.heap.page_allocator.create(MemorySource(T)) catch unreachable;
    src_ptr.* = MemorySource(T).init(slice);
    return src_ptr.stream();
}

/// Create a stream from an iterator
pub fn fromIterator(comptime T: type, iterator: anytype) Stream(T) {
    const Iterator = @TypeOf(iterator);
    const Impl = struct {
        iter: Iterator,

        pub fn next(self: *@This()) StreamError!?T {
            return self.iter.next();
        }

        pub fn peek(self: *const @This()) StreamError!?T {
            _ = self;
            return StreamError.NotSupported;
        }

        pub fn skip(self: *@This(), n: usize) StreamError!void {
            var i: usize = 0;
            while (i < n) : (i += 1) {
                _ = self.iter.next() orelse break;
            }
        }

        pub fn close(self: *@This()) void {
            _ = self;
        }

        pub fn getPosition(self: *const @This()) usize {
            _ = self;
            return 0;
        }

        pub fn isExhausted(self: *const @This()) bool {
            _ = self;
            return false;
        }
    };

    var impl = Impl{ .iter = iterator };
    return Stream(T){
        .ptr = @ptrCast(&impl),
        .vtable = &.{
            .nextFn = @ptrCast(&Impl.next),
            .peekFn = @ptrCast(&Impl.peek),
            .skipFn = @ptrCast(&Impl.skip),
            .closeFn = @ptrCast(&Impl.close),
            .getPositionFn = @ptrCast(&Impl.getPosition),
            .isExhaustedFn = @ptrCast(&Impl.isExhausted),
        },
    };
}

/// Stream statistics for monitoring and debugging
pub const StreamStats = struct {
    items_processed: usize = 0,
    bytes_processed: usize = 0,
    errors_encountered: usize = 0,
    position: usize = 0,
    is_exhausted: bool = false,
};

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
