/// DirectStream - Optimal tagged union implementation 
/// Phase 5C - Clean break from legacy, arena-allocated operators
/// Achieves 1-2 cycle dispatch through enum-based dispatch

const std = @import("std");
const StreamError = @import("error.zig").StreamError;
const RingBuffer = @import("buffer.zig").RingBuffer;

// Import source types
const SliceStream = @import("direct_stream_sources.zig").SliceStream;
const RingBufferStream = @import("direct_stream_sources.zig").RingBufferStream;
pub const GeneratorStream = @import("direct_stream_sources.zig").GeneratorStream;
const EmptyStream = @import("direct_stream_sources.zig").EmptyStream;
const ErrorStream = @import("direct_stream_sources.zig").ErrorStream;

/// Tagged union stream - zero vtable overhead
/// Sources embedded directly, operators use pointers (arena allocated)
pub fn DirectStream(comptime T: type) type {
    return union(enum) {
        // Core stream sources (embedded directly)
        slice: SliceStream(T),
        ring_buffer: RingBufferStream(T),
        generator: GeneratorStream(T),
        empty: EmptyStream(T),
        error_stream: ErrorStream(T),
        
        // Operators (pointers to avoid recursion, arena allocated)
        filter: *FilterOperator(T),
        take: *TakeOperator(T),
        drop: *DropOperator(T),
        
        const Self = @This();
        
        /// Get next item from stream, advancing position
        /// Inlined for maximum performance (1-2 cycle dispatch)
        pub inline fn next(self: *Self) StreamError!?T {
            return switch (self.*) {
                .slice => |*s| s.next(),
                .ring_buffer => |*s| s.next(),
                .generator => |*s| s.next(),
                .empty => |*s| s.next(),
                .error_stream => |*s| s.next(),
                .filter => |s| s.next(),
                .take => |s| s.next(),
                .drop => |s| s.next(),
            };
        }
        
        /// Peek at next item without advancing
        /// Inlined for zero-overhead preview
        pub inline fn peek(self: *Self) StreamError!?T {
            return switch (self.*) {
                .slice => |*s| s.peek(),
                .ring_buffer => |*s| s.peek(),
                .generator => |*s| s.peek(),
                .empty => |*s| s.peek(),
                .error_stream => |*s| s.peek(),
                .filter => |s| s.peek(),
                .take => |s| s.peek(),
                .drop => |s| s.peek(),
            };
        }
        
        /// Skip n items in the stream
        /// Inlined for efficient bulk advancement
        pub inline fn skip(self: *Self, n: usize) StreamError!void {
            return switch (self.*) {
                .slice => |*s| s.skip(n),
                .ring_buffer => |*s| s.skip(n),
                .generator => |*s| s.skip(n),
                .empty => |*s| s.skip(n),
                .error_stream => |*s| s.skip(n),
                .filter => |s| s.skip(n),
                .take => |s| s.skip(n),
                .drop => |s| s.skip(n),
            };
        }
        
        /// Get current position in stream
        /// Inlined for immediate position access
        pub inline fn getPosition(self: *const Self) usize {
            return switch (self.*) {
                .slice => |*s| s.getPosition(),
                .ring_buffer => |*s| s.getPosition(),
                .generator => |*s| s.getPosition(),
                .empty => |*s| s.getPosition(),
                .error_stream => |*s| s.getPosition(),
                .filter => |s| s.getPosition(),
                .take => |s| s.getPosition(),
                .drop => |s| s.getPosition(),
            };
        }
        
        /// Check if stream is exhausted
        /// Inlined for fast termination checks
        pub inline fn isExhausted(self: *const Self) bool {
            return switch (self.*) {
                .slice => |*s| s.isExhausted(),
                .ring_buffer => |*s| s.isExhausted(),
                .generator => |*s| s.isExhausted(),
                .empty => |*s| s.isExhausted(),
                .error_stream => |*s| s.isExhausted(),
                .filter => |s| s.isExhausted(),
                .take => |s| s.isExhausted(),
                .drop => |s| s.isExhausted(),
            };
        }
        
        /// Close the stream and release resources
        pub inline fn close(self: *Self) void {
            switch (self.*) {
                .slice => |*s| s.close(),
                .ring_buffer => |*s| s.close(),
                .generator => |*s| s.close(),
                .empty => |*s| s.close(),
                .error_stream => |*s| s.close(),
                .filter => |s| s.close(),
                .take => |s| s.close(),
                .drop => |s| s.close(),
            }
        }
    };
}

// Re-export GeneratorStream for convenience
pub const GeneratorStreamType = GeneratorStream;

/// Filter operator - arena allocated
pub fn FilterOperator(comptime T: type) type {
    return struct {
        source: DirectStream(T),
        predicate: *const fn (T) bool,
        
        const Self = @This();
        
        pub fn init(source: DirectStream(T), predicate: *const fn (T) bool) Self {
            return .{
                .source = source,
                .predicate = predicate,
            };
        }
        
        pub fn next(self: *Self) StreamError!?T {
            while (try self.source.next()) |item| {
                if (self.predicate(item)) {
                    return item;
                }
            }
            return null;
        }
        
        pub fn peek(self: *Self) StreamError!?T {
            // Can't peek efficiently with filter
            // TODO: Consider caching peeked value
            while (try self.source.peek()) |item| {
                if (self.predicate(item)) {
                    return item;
                }
                try self.source.skip(1);
            }
            return null;
        }
        
        pub fn skip(self: *Self, n: usize) StreamError!void {
            var count: usize = 0;
            while (count < n) : (count += 1) {
                _ = try self.next() orelse break;
            }
        }
        
        pub fn getPosition(self: *const Self) usize {
            return self.source.getPosition();
        }
        
        pub fn isExhausted(self: *const Self) bool {
            // TODO: This isn't quite right - need to check if any items pass filter
            return self.source.isExhausted();
        }
        
        pub fn close(self: *Self) void {
            self.source.close();
        }
    };
}

/// Take operator - arena allocated
pub fn TakeOperator(comptime T: type) type {
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
            if (try self.source.next()) |item| {
                self.taken += 1;
                return item;
            }
            return null;
        }
        
        pub fn peek(self: *Self) StreamError!?T {
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

/// Drop operator - arena allocated
pub fn DropOperator(comptime T: type) type {
    return struct {
        source: DirectStream(T),
        drop_count: usize,
        dropped: bool,
        
        const Self = @This();
        
        pub fn init(source: DirectStream(T), drop_count: usize) Self {
            return .{
                .source = source,
                .drop_count = drop_count,
                .dropped = false,
            };
        }
        
        pub fn next(self: *Self) StreamError!?T {
            if (!self.dropped) {
                try self.source.skip(self.drop_count);
                self.dropped = true;
            }
            return self.source.next();
        }
        
        pub fn peek(self: *Self) StreamError!?T {
            if (!self.dropped) {
                try self.source.skip(self.drop_count);
                self.dropped = true;
            }
            return self.source.peek();
        }
        
        pub fn skip(self: *Self, n: usize) StreamError!void {
            if (!self.dropped) {
                try self.source.skip(self.drop_count);
                self.dropped = true;
            }
            return self.source.skip(n);
        }
        
        pub fn getPosition(self: *const Self) usize {
            if (!self.dropped) {
                return 0;
            }
            const pos = self.source.getPosition();
            return if (pos > self.drop_count) pos - self.drop_count else 0;
        }
        
        pub fn isExhausted(self: *const Self) bool {
            return self.source.isExhausted();
        }
        
        pub fn close(self: *Self) void {
            self.source.close();
        }
    };
}

/// Arena allocation for operators
const ArenaPool = @import("../memory/arena_pool.zig").ArenaPool;

threadlocal var operator_arena: ?*ArenaPool = null;

fn getArena() !*ArenaPool {
    if (operator_arena) |arena| {
        return arena;
    }
    const arena = try std.heap.page_allocator.create(ArenaPool);
    arena.* = ArenaPool.init(std.heap.page_allocator);
    operator_arena = arena;
    return arena;
}

/// Helper functions to create streams

pub fn fromSlice(comptime T: type, data: []const T) DirectStream(T) {
    return DirectStream(T){ .slice = SliceStream(T).init(data) };
}

pub fn fromRingBuffer(comptime T: type, buffer: *RingBuffer(T, 4096)) DirectStream(T) {
    return DirectStream(T){ .ring_buffer = RingBufferStream(T).init(buffer) };
}

pub fn fromGenerator(comptime T: type, state: *anyopaque, gen_fn: *const fn (*anyopaque) ?T) DirectStream(T) {
    return DirectStream(T){ .generator = GeneratorStream(T).init(state, gen_fn) };
}

pub fn empty(comptime T: type) DirectStream(T) {
    return DirectStream(T){ .empty = EmptyStream(T).init() };
}

pub fn errorStream(comptime T: type, err: StreamError) DirectStream(T) {
    return DirectStream(T){ .error_stream = ErrorStream(T).init(err) };
}

/// Helper functions to create operators with arena allocation

pub fn directFilter(comptime T: type, source: DirectStream(T), pred: *const fn (T) bool) !DirectStream(T) {
    const arena = try getArena();
    const op = try arena.allocator().create(FilterOperator(T));
    op.* = FilterOperator(T).init(source, pred);
    return DirectStream(T){ .filter = op };
}

pub fn directTake(comptime T: type, source: DirectStream(T), limit: usize) !DirectStream(T) {
    const arena = try getArena();
    const op = try arena.allocator().create(TakeOperator(T));
    op.* = TakeOperator(T).init(source, limit);
    return DirectStream(T){ .take = op };
}

pub fn directDrop(comptime T: type, source: DirectStream(T), count: usize) !DirectStream(T) {
    const arena = try getArena();
    const op = try arena.allocator().create(DropOperator(T));
    op.* = DropOperator(T).init(source, count);
    return DirectStream(T){ .drop = op };
}

/// Rotate arenas after processing (e.g., after processing a file)
pub fn rotateArenas() void {
    if (operator_arena) |arena| {
        arena.rotate();
    }
}

/// Clean up arena pool
pub fn deinitArenas() void {
    if (operator_arena) |arena| {
        arena.deinit();
        std.heap.page_allocator.destroy(arena);
        operator_arena = null;
    }
}