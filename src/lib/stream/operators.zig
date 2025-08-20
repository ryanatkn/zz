const std = @import("std");
const Stream = @import("mod.zig").Stream;
const StreamError = @import("error.zig").StreamError;
const RingBuffer = @import("buffer.zig").RingBuffer;

/// TODO: Phase 2 - Full object pool implementation
/// Current implementation uses heap allocation which violates zero-allocation principle.
/// A complete fix requires:
/// 1. Generic object pools for each operator type
/// 2. Global pool registry with thread-local storage
/// 3. Automatic pool management and cleanup
///
/// For now, we use a simple allocator wrapper that at least tracks allocations
/// and can be swapped out for arena allocators in performance-critical paths.
var operator_allocator: std.mem.Allocator = std.heap.page_allocator;

/// Map operator - transform stream elements through a function
/// TODO: Phase 2 - Replace with object pool allocation
/// Current workaround: Uses operator_allocator which can be set to arena
pub fn map(comptime T: type, comptime U: type, source: Stream(T), mapFn: *const fn (T) U) Stream(U) {
    const MapImpl = struct {
        source: Stream(T),
        mapFn: *const fn (T) U,

        pub fn next(self: *@This()) StreamError!?U {
            if (try self.source.next()) |item| {
                return self.mapFn(item);
            }
            return null;
        }

        pub fn peek(self: *const @This()) StreamError!?U {
            if (try self.source.peek()) |item| {
                return self.mapFn(item);
            }
            return null;
        }

        pub fn skip(self: *@This(), n: usize) StreamError!void {
            return self.source.skip(n);
        }

        pub fn close(self: *@This()) void {
            self.source.close();
        }

        pub fn getPosition(self: *const @This()) usize {
            return self.source.getPosition();
        }

        pub fn isExhausted(self: *const @This()) bool {
            return self.source.isExhausted();
        }
    };

    const impl_ptr = operator_allocator.create(MapImpl) catch unreachable;
    impl_ptr.* = MapImpl{ .source = source, .mapFn = mapFn };
    return Stream(U){
        .ptr = @ptrCast(impl_ptr),
        .vtable = &.{
            .nextFn = @ptrCast(&MapImpl.next),
            .peekFn = @ptrCast(&MapImpl.peek),
            .skipFn = @ptrCast(&MapImpl.skip),
            .closeFn = @ptrCast(&MapImpl.close),
            .getPositionFn = @ptrCast(&MapImpl.getPosition),
            .isExhaustedFn = @ptrCast(&MapImpl.isExhausted),
        },
    };
}

/// Filter operator - keep only elements that match predicate
/// TODO: Phase 2 - Replace with object pool allocation
pub fn filter(comptime T: type, source: Stream(T), predicate: *const fn (T) bool) Stream(T) {
    const FilterImpl = struct {
        source: Stream(T),
        predicate: *const fn (T) bool,
        next_value: ?T = null,

        pub fn next(self: *@This()) StreamError!?T {
            // If we have a cached value from peek, return it
            if (self.next_value) |value| {
                self.next_value = null;
                return value;
            }

            // Find next matching item
            while (try self.source.next()) |item| {
                if (self.predicate(item)) {
                    return item;
                }
            }
            return null;
        }

        pub fn peek(self: *@This()) StreamError!?T {
            // If already cached, return it
            if (self.next_value) |value| {
                return value;
            }

            // Find and cache next matching item
            while (try self.source.next()) |item| {
                if (self.predicate(item)) {
                    self.next_value = item;
                    return item;
                }
            }
            return null;
        }

        pub fn skip(self: *@This(), n: usize) StreamError!void {
            var skipped: usize = 0;
            while (skipped < n) : (skipped += 1) {
                _ = try self.next() orelse break;
            }
        }

        pub fn close(self: *@This()) void {
            self.source.close();
        }

        pub fn getPosition(self: *const @This()) usize {
            return self.source.getPosition();
        }

        pub fn isExhausted(self: *const @This()) bool {
            return self.source.isExhausted() and self.next_value == null;
        }
    };

    const impl_ptr = operator_allocator.create(FilterImpl) catch unreachable;
    impl_ptr.* = FilterImpl{ .source = source, .predicate = predicate };
    return Stream(T){
        .ptr = @ptrCast(impl_ptr),
        .vtable = &.{
            .nextFn = @ptrCast(&FilterImpl.next),
            .peekFn = @ptrCast(&FilterImpl.peek),
            .skipFn = @ptrCast(&FilterImpl.skip),
            .closeFn = @ptrCast(&FilterImpl.close),
            .getPositionFn = @ptrCast(&FilterImpl.getPosition),
            .isExhaustedFn = @ptrCast(&FilterImpl.isExhausted),
        },
    };
}

/// Batch operator - group elements into fixed-size arrays
pub fn batch(comptime T: type, source: Stream(T), size: usize) Stream([]T) {
    const BatchImpl = struct {
        source: Stream(T),
        size: usize,
        buffer: []T,
        allocator: std.mem.Allocator,

        pub fn init(src: Stream(T), batch_size: usize, allocator: std.mem.Allocator) !@This() {
            return .{
                .source = src,
                .size = batch_size,
                .buffer = try allocator.alloc(T, batch_size),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.allocator.free(self.buffer);
        }

        pub fn next(self: *@This()) StreamError!?[]T {
            var count: usize = 0;
            while (count < self.size) : (count += 1) {
                if (try self.source.next()) |item| {
                    self.buffer[count] = item;
                } else {
                    break;
                }
            }

            if (count == 0) return null;
            return self.buffer[0..count];
        }

        pub fn peek(self: *const @This()) StreamError!?[]T {
            _ = self;
            return StreamError.NotSupported;
        }

        pub fn skip(self: *@This(), n: usize) StreamError!void {
            const items_to_skip = n * self.size;
            return self.source.skip(items_to_skip);
        }

        pub fn close(self: *@This()) void {
            self.source.close();
            self.deinit();
        }

        pub fn getPosition(self: *const @This()) usize {
            return self.source.getPosition() / self.size;
        }

        pub fn isExhausted(self: *const @This()) bool {
            return self.source.isExhausted();
        }
    };

    const impl_ptr = operator_allocator.create(BatchImpl) catch unreachable;
    impl_ptr.* = BatchImpl.init(source, size, operator_allocator) catch unreachable;

    return Stream([]T){
        .ptr = @ptrCast(impl_ptr),
        .vtable = &.{
            .nextFn = @ptrCast(&BatchImpl.next),
            .peekFn = @ptrCast(&BatchImpl.peek),
            .skipFn = @ptrCast(&BatchImpl.skip),
            .closeFn = @ptrCast(&BatchImpl.close),
            .getPositionFn = @ptrCast(&BatchImpl.getPosition),
            .isExhaustedFn = @ptrCast(&BatchImpl.isExhausted),
        },
    };
}

/// Take operator - limit stream to first n items
/// TODO: Phase 2 - Replace with object pool allocation
pub fn take(comptime T: type, source: Stream(T), n: usize) Stream(T) {
    const TakeImpl = struct {
        source: Stream(T),
        limit: usize,
        taken: usize = 0,

        pub fn next(self: *@This()) StreamError!?T {
            if (self.taken >= self.limit) return null;
            if (try self.source.next()) |item| {
                self.taken += 1;
                return item;
            }
            return null;
        }

        pub fn peek(self: *const @This()) StreamError!?T {
            if (self.taken >= self.limit) return null;
            return self.source.peek();
        }

        pub fn skip(self: *@This(), count: usize) StreamError!void {
            const to_skip = @min(count, self.limit - self.taken);
            try self.source.skip(to_skip);
            self.taken += to_skip;
        }

        pub fn close(self: *@This()) void {
            self.source.close();
        }

        pub fn getPosition(self: *const @This()) usize {
            return self.taken;
        }

        pub fn isExhausted(self: *const @This()) bool {
            return self.taken >= self.limit or self.source.isExhausted();
        }
    };

    const impl_ptr = operator_allocator.create(TakeImpl) catch unreachable;
    impl_ptr.* = TakeImpl{ .source = source, .limit = n, .taken = 0 };
    return Stream(T){
        .ptr = @ptrCast(impl_ptr),
        .vtable = &.{
            .nextFn = @ptrCast(&TakeImpl.next),
            .peekFn = @ptrCast(&TakeImpl.peek),
            .skipFn = @ptrCast(&TakeImpl.skip),
            .closeFn = @ptrCast(&TakeImpl.close),
            .getPositionFn = @ptrCast(&TakeImpl.getPosition),
            .isExhaustedFn = @ptrCast(&TakeImpl.isExhausted),
        },
    };
}

/// Drop operator - skip first n items from stream
/// TODO: Phase 2 - Replace with object pool allocation
pub fn drop(comptime T: type, source: Stream(T), n: usize) Stream(T) {
    const DropImpl = struct {
        source: Stream(T),
        to_drop: usize,
        dropped: bool = false,

        pub fn next(self: *@This()) StreamError!?T {
            if (!self.dropped) {
                try self.source.skip(self.to_drop);
                self.dropped = true;
            }
            return self.source.next();
        }

        pub fn peek(self: *@This()) StreamError!?T {
            if (!self.dropped) {
                try self.source.skip(self.to_drop);
                self.dropped = true;
            }
            return self.source.peek();
        }

        pub fn skip(self: *@This(), count: usize) StreamError!void {
            if (!self.dropped) {
                try self.source.skip(self.to_drop);
                self.dropped = true;
            }
            return self.source.skip(count);
        }

        pub fn close(self: *@This()) void {
            self.source.close();
        }

        pub fn getPosition(self: *const @This()) usize {
            if (!self.dropped) return 0;
            return self.source.getPosition() - self.to_drop;
        }

        pub fn isExhausted(self: *const @This()) bool {
            return self.source.isExhausted();
        }
    };

    const impl_ptr = operator_allocator.create(DropImpl) catch unreachable;
    impl_ptr.* = DropImpl{ .source = source, .to_drop = n, .dropped = false };
    return Stream(T){
        .ptr = @ptrCast(impl_ptr),
        .vtable = &.{
            .nextFn = @ptrCast(&DropImpl.next),
            .peekFn = @ptrCast(&DropImpl.peek),
            .skipFn = @ptrCast(&DropImpl.skip),
            .closeFn = @ptrCast(&DropImpl.close),
            .getPositionFn = @ptrCast(&DropImpl.getPosition),
            .isExhaustedFn = @ptrCast(&DropImpl.isExhausted),
        },
    };
}

/// Merge two streams into one (alternating)
/// TODO: Phase 2 - Replace with object pool allocation
pub fn merge(comptime T: type, source1: Stream(T), source2: Stream(T)) Stream(T) {
    const MergeImpl = struct {
        source1: Stream(T),
        source2: Stream(T),
        use_first: bool = true,

        pub fn next(self: *@This()) StreamError!?T {
            if (self.use_first) {
                self.use_first = false;
                if (try self.source1.next()) |item| {
                    return item;
                }
                // First stream exhausted, try second
                return self.source2.next();
            } else {
                self.use_first = true;
                if (try self.source2.next()) |item| {
                    return item;
                }
                // Second stream exhausted, try first
                return self.source1.next();
            }
        }

        pub fn peek(self: *const @This()) StreamError!?T {
            if (self.use_first) {
                if (try self.source1.peek()) |item| {
                    return item;
                }
                return self.source2.peek();
            } else {
                if (try self.source2.peek()) |item| {
                    return item;
                }
                return self.source1.peek();
            }
        }

        pub fn skip(self: *@This(), n: usize) StreamError!void {
            var skipped: usize = 0;
            while (skipped < n) : (skipped += 1) {
                _ = try self.next() orelse break;
            }
        }

        pub fn close(self: *@This()) void {
            self.source1.close();
            self.source2.close();
        }

        pub fn getPosition(self: *const @This()) usize {
            return self.source1.getPosition() + self.source2.getPosition();
        }

        pub fn isExhausted(self: *const @This()) bool {
            return self.source1.isExhausted() and self.source2.isExhausted();
        }
    };

    const impl_ptr = operator_allocator.create(MergeImpl) catch unreachable;
    impl_ptr.* = MergeImpl{ .source1 = source1, .source2 = source2, .use_first = true };
    return Stream(T){
        .ptr = @ptrCast(impl_ptr),
        .vtable = &.{
            .nextFn = @ptrCast(&MergeImpl.next),
            .peekFn = @ptrCast(&MergeImpl.peek),
            .skipFn = @ptrCast(&MergeImpl.skip),
            .closeFn = @ptrCast(&MergeImpl.close),
            .getPositionFn = @ptrCast(&MergeImpl.getPosition),
            .isExhaustedFn = @ptrCast(&MergeImpl.isExhausted),
        },
    };
}

test "map operator" {
    const source = @import("source.zig");
    const data = [_]u32{ 1, 2, 3 };
    var src = source.MemorySource(u32).init(&data);
    const stream = src.stream();

    const double = struct {
        fn f(x: u32) u32 {
            return x * 2;
        }
    }.f;

    var mapped = map(u32, u32, stream, double);

    try std.testing.expectEqual(@as(?u32, 2), try mapped.next());
    try std.testing.expectEqual(@as(?u32, 4), try mapped.next());
    try std.testing.expectEqual(@as(?u32, 6), try mapped.next());
    try std.testing.expectEqual(@as(?u32, null), try mapped.next());
}

test "filter operator" {
    const source = @import("source.zig");
    const data = [_]u32{ 1, 2, 3, 4, 5, 6 };
    var src = source.MemorySource(u32).init(&data);
    const stream = src.stream();

    const isEven = struct {
        fn f(x: u32) bool {
            return x % 2 == 0;
        }
    }.f;

    var filtered = filter(u32, stream, isEven);

    try std.testing.expectEqual(@as(?u32, 2), try filtered.next());
    try std.testing.expectEqual(@as(?u32, 4), try filtered.next());
    try std.testing.expectEqual(@as(?u32, 6), try filtered.next());
    try std.testing.expectEqual(@as(?u32, null), try filtered.next());
}

test "take operator" {
    const source = @import("source.zig");
    const data = [_]u32{ 1, 2, 3, 4, 5 };
    var src = source.MemorySource(u32).init(&data);
    const stream = src.stream();

    var limited = take(u32, stream, 3);

    try std.testing.expectEqual(@as(?u32, 1), try limited.next());
    try std.testing.expectEqual(@as(?u32, 2), try limited.next());
    try std.testing.expectEqual(@as(?u32, 3), try limited.next());
    try std.testing.expectEqual(@as(?u32, null), try limited.next());
}

test "drop operator" {
    const source = @import("source.zig");
    const data = [_]u32{ 1, 2, 3, 4, 5 };
    var src = source.MemorySource(u32).init(&data);
    const stream = src.stream();

    var dropped = drop(u32, stream, 2);

    try std.testing.expectEqual(@as(?u32, 3), try dropped.next());
    try std.testing.expectEqual(@as(?u32, 4), try dropped.next());
    try std.testing.expectEqual(@as(?u32, 5), try dropped.next());
    try std.testing.expectEqual(@as(?u32, null), try dropped.next());
}

/// Set a custom allocator for operator implementations
/// This allows using arena allocators or pools instead of heap allocation
pub fn setOperatorAllocator(allocator: std.mem.Allocator) void {
    operator_allocator = allocator;
}

/// Get the current operator allocator
pub fn getOperatorAllocator() std.mem.Allocator {
    return operator_allocator;
}

// Fusion operators moved to fusion.zig
