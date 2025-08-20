const std = @import("std");
const Stream = @import("mod.zig").Stream;
const StreamError = @import("error.zig").StreamError;

/// Get the operator allocator from operators.zig
/// This allows fusion operators to use the same allocator configuration
const operators = @import("operators.zig");

/// Operator fusion - combine adjacent map operations into a single operation
/// This reduces intermediate allocations and function call overhead
/// TODO: Phase 2 - Extend to more operator combinations (filter+filter, map+filter, etc.)
pub fn fusedMap(comptime T: type, comptime U: type, comptime V: type, 
                 source: Stream(T), 
                 fn1: *const fn (T) U, 
                 fn2: *const fn (U) V) Stream(V) {
    const FusedMapImpl = struct {
        source: Stream(T),
        fn1: *const fn (T) U,
        fn2: *const fn (U) V,

        pub fn next(self: *@This()) StreamError!?V {
            if (try self.source.next()) |item| {
                // Apply both functions in sequence without intermediate storage
                const intermediate = self.fn1(item);
                return self.fn2(intermediate);
            }
            return null;
        }

        pub fn peek(self: *const @This()) StreamError!?V {
            if (try self.source.peek()) |item| {
                const intermediate = self.fn1(item);
                return self.fn2(intermediate);
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

    const impl_ptr = operators.getOperatorAllocator().create(FusedMapImpl) catch unreachable;
    impl_ptr.* = FusedMapImpl{ 
        .source = source, 
        .fn1 = fn1,
        .fn2 = fn2,
    };
    
    return Stream(V){
        .ptr = @ptrCast(impl_ptr),
        .vtable = &.{
            .nextFn = @ptrCast(&FusedMapImpl.next),
            .peekFn = @ptrCast(&FusedMapImpl.peek),
            .skipFn = @ptrCast(&FusedMapImpl.skip),
            .closeFn = @ptrCast(&FusedMapImpl.close),
            .getPositionFn = @ptrCast(&FusedMapImpl.getPosition),
            .isExhaustedFn = @ptrCast(&FusedMapImpl.isExhausted),
        },
    };
}

/// Fused filter - combine adjacent filter operations
/// Applies both predicates without intermediate stream creation
pub fn fusedFilter(comptime T: type, 
                   source: Stream(T), 
                   pred1: *const fn (T) bool, 
                   pred2: *const fn (T) bool) Stream(T) {
    const FusedFilterImpl = struct {
        source: Stream(T),
        pred1: *const fn (T) bool,
        pred2: *const fn (T) bool,
        next_value: ?T = null,

        pub fn next(self: *@This()) StreamError!?T {
            if (self.next_value) |value| {
                self.next_value = null;
                return value;
            }

            // Find next item that passes both predicates
            while (try self.source.next()) |item| {
                if (self.pred1(item) and self.pred2(item)) {
                    return item;
                }
            }
            return null;
        }

        pub fn peek(self: *@This()) StreamError!?T {
            if (self.next_value) |value| {
                return value;
            }

            while (try self.source.next()) |item| {
                if (self.pred1(item) and self.pred2(item)) {
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

    const impl_ptr = operators.getOperatorAllocator().create(FusedFilterImpl) catch unreachable;
    impl_ptr.* = FusedFilterImpl{ 
        .source = source, 
        .pred1 = pred1,
        .pred2 = pred2,
    };
    
    return Stream(T){
        .ptr = @ptrCast(impl_ptr),
        .vtable = &.{
            .nextFn = @ptrCast(&FusedFilterImpl.next),
            .peekFn = @ptrCast(&FusedFilterImpl.peek),
            .skipFn = @ptrCast(&FusedFilterImpl.skip),
            .closeFn = @ptrCast(&FusedFilterImpl.close),
            .getPositionFn = @ptrCast(&FusedFilterImpl.getPosition),
            .isExhaustedFn = @ptrCast(&FusedFilterImpl.isExhausted),
        },
    };
}

test "fusedMap operator" {
    const source = @import("source.zig");
    const data = [_]u32{ 1, 2, 3 };
    var src = source.MemorySource(u32).init(&data);
    const stream = src.stream();

    const double = struct {
        fn f(x: u32) u32 {
            return x * 2;
        }
    }.f;
    
    const addOne = struct {
        fn f(x: u32) u32 {
            return x + 1;
        }
    }.f;

    // Fused: (x * 2) + 1
    var fused = fusedMap(u32, u32, u32, stream, double, addOne);

    try std.testing.expectEqual(@as(?u32, 3), try fused.next());  // (1*2)+1 = 3
    try std.testing.expectEqual(@as(?u32, 5), try fused.next());  // (2*2)+1 = 5
    try std.testing.expectEqual(@as(?u32, 7), try fused.next());  // (3*2)+1 = 7
    try std.testing.expectEqual(@as(?u32, null), try fused.next());
}

test "fusedFilter operator" {
    const source = @import("source.zig");
    const data = [_]u32{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    var src = source.MemorySource(u32).init(&data);
    const stream = src.stream();

    const isEven = struct {
        fn f(x: u32) bool {
            return x % 2 == 0;
        }
    }.f;
    
    const greaterThan4 = struct {
        fn f(x: u32) bool {
            return x > 4;
        }
    }.f;

    // Fused: even AND > 4
    var fused = fusedFilter(u32, stream, isEven, greaterThan4);

    try std.testing.expectEqual(@as(?u32, 6), try fused.next());
    try std.testing.expectEqual(@as(?u32, 8), try fused.next());
    try std.testing.expectEqual(@as(?u32, 10), try fused.next());
    try std.testing.expectEqual(@as(?u32, null), try fused.next());
}