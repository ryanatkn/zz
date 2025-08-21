/// Phase 5B: Embedded state operators for zero-allocation DirectStream
/// These operators embed their state directly, avoiding heap allocation entirely
/// Following stream-first principles: 1-2 cycle dispatch, zero allocations
const std = @import("std");
const DirectStream = @import("direct_stream.zig").DirectStream;
const StreamError = @import("error.zig").StreamError;

/// Map stream with embedded state (zero-allocation)
pub fn MapEmbedded(comptime T: type, comptime U: type) type {
    return struct {
        source: DirectStream(T),
        map_fn: *const fn (T) U,

        const Self = @This();

        pub fn init(source: DirectStream(T), map_fn: *const fn (T) U) Self {
            return .{
                .source = source,
                .map_fn = map_fn,
            };
        }

        pub fn next(self: *Self) StreamError!?U {
            if (try self.source.next()) |value| {
                return self.map_fn(value);
            }
            return null;
        }

        pub fn peek(self: *const Self) StreamError!?U {
            if (try self.source.peek()) |value| {
                return self.map_fn(value);
            }
            return null;
        }

        pub fn skip(self: *Self, n: usize) StreamError!void {
            return self.source.skip(n);
        }

        pub fn getPosition(self: *const Self) usize {
            return self.source.getPosition();
        }

        pub fn isExhausted(self: *const Self) bool {
            return self.source.isExhausted();
        }

        pub fn close(self: *Self) void {
            self.source.close();
        }
    };
}

/// Filter stream with embedded state (zero-allocation)
pub fn FilterEmbedded(comptime T: type) type {
    return struct {
        source: DirectStream(T),
        predicate: *const fn (T) bool,
        next_value: ?T,

        const Self = @This();

        pub fn init(source: DirectStream(T), predicate: *const fn (T) bool) Self {
            return .{
                .source = source,
                .predicate = predicate,
                .next_value = null,
            };
        }

        pub fn next(self: *Self) StreamError!?T {
            while (try self.source.next()) |value| {
                if (self.predicate(value)) {
                    return value;
                }
            }
            return null;
        }

        pub fn peek(self: *Self) StreamError!?T {
            if (self.next_value) |value| {
                return value;
            }

            while (try self.source.next()) |value| {
                if (self.predicate(value)) {
                    self.next_value = value;
                    return value;
                }
            }
            return null;
        }

        pub fn skip(self: *Self, n: usize) StreamError!void {
            var skipped: usize = 0;
            while (skipped < n) : (skipped += 1) {
                if (try self.next() == null) break;
            }
        }

        pub fn getPosition(self: *const Self) usize {
            return self.source.getPosition();
        }

        pub fn isExhausted(self: *const Self) bool {
            return self.next_value == null and self.source.isExhausted();
        }

        pub fn close(self: *Self) void {
            self.source.close();
        }
    };
}

/// Take stream with embedded state (zero-allocation)
pub fn TakeEmbedded(comptime T: type) type {
    return struct {
        source: DirectStream(T),
        limit: usize,
        taken: usize,

        const Self = @This();

        pub fn init(source: DirectStream(T), limit: usize) Self {
            return .{
                .source = source,
                .limit = limit,
                .taken = 0,
            };
        }

        pub fn next(self: *Self) StreamError!?T {
            if (self.taken >= self.limit) return null;
            if (try self.source.next()) |value| {
                self.taken += 1;
                return value;
            }
            return null;
        }

        pub fn peek(self: *const Self) StreamError!?T {
            if (self.taken >= self.limit) return null;
            return self.source.peek();
        }

        pub fn skip(self: *Self, n: usize) StreamError!void {
            const to_skip = @min(n, self.limit - self.taken);
            try self.source.skip(to_skip);
            self.taken += to_skip;
        }

        pub fn getPosition(self: *const Self) usize {
            return self.taken;
        }

        pub fn isExhausted(self: *const Self) bool {
            return self.taken >= self.limit or self.source.isExhausted();
        }

        pub fn close(self: *Self) void {
            self.source.close();
        }
    };
}

/// Drop stream with embedded state (zero-allocation)
pub fn DropEmbedded(comptime T: type) type {
    return struct {
        source: DirectStream(T),
        to_drop: usize,
        dropped: usize,

        const Self = @This();

        pub fn init(source: DirectStream(T), to_drop: usize) Self {
            return .{
                .source = source,
                .to_drop = to_drop,
                .dropped = 0,
            };
        }

        pub fn next(self: *Self) StreamError!?T {
            // Drop initial elements if needed
            while (self.dropped < self.to_drop) {
                if (try self.source.next() == null) return null;
                self.dropped += 1;
            }
            return self.source.next();
        }

        pub fn peek(self: *Self) StreamError!?T {
            // Drop initial elements if needed
            while (self.dropped < self.to_drop) {
                if (try self.source.next() == null) return null;
                self.dropped += 1;
            }
            return self.source.peek();
        }

        pub fn skip(self: *Self, n: usize) StreamError!void {
            // First drop required elements
            while (self.dropped < self.to_drop) {
                if (try self.source.next() == null) return;
                self.dropped += 1;
            }
            // Then skip requested elements
            return self.source.skip(n);
        }

        pub fn getPosition(self: *const Self) usize {
            return self.source.getPosition();
        }

        pub fn isExhausted(self: *const Self) bool {
            return self.source.isExhausted();
        }

        pub fn close(self: *Self) void {
            self.source.close();
        }
    };
}

/// Fused map+filter operator for optimized chaining
pub fn MapFilterEmbedded(comptime T: type, comptime U: type) type {
    return struct {
        source: DirectStream(T),
        map_fn: *const fn (T) U,
        predicate: *const fn (U) bool,

        const Self = @This();

        pub fn init(source: DirectStream(T), map_fn: *const fn (T) U, predicate: *const fn (U) bool) Self {
            return .{
                .source = source,
                .map_fn = map_fn,
                .predicate = predicate,
            };
        }

        pub fn next(self: *Self) StreamError!?U {
            while (try self.source.next()) |value| {
                const mapped = self.map_fn(value);
                if (self.predicate(mapped)) {
                    return mapped;
                }
            }
            return null;
        }

        pub fn peek(self: *Self) StreamError!?U {
            // For simplicity, we don't cache peek for fused operators
            // TODO: Add caching if needed
            var temp_source = self.source;
            while (try temp_source.next()) |value| {
                const mapped = self.map_fn(value);
                if (self.predicate(mapped)) {
                    return mapped;
                }
            }
            return null;
        }

        pub fn skip(self: *Self, n: usize) StreamError!void {
            var skipped: usize = 0;
            while (skipped < n) : (skipped += 1) {
                if (try self.next() == null) break;
            }
        }

        pub fn getPosition(self: *const Self) usize {
            return self.source.getPosition();
        }

        pub fn isExhausted(self: *const Self) bool {
            return self.source.isExhausted();
        }

        pub fn close(self: *Self) void {
            self.source.close();
        }
    };
}

// TODO: Phase 5C - Add these embedded operators to DirectStream union as variants
// TODO: Add comptime operator fusion detection for common patterns
// TODO: Add SIMD variants for numeric operations
// TODO: Add benchmarks comparing embedded vs heap-allocated operators
