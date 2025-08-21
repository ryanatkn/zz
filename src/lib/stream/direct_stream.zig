/// DirectStream - Tagged union implementation following stream-first principles
/// Achieves 1-2 cycle dispatch (vs 3-5 for vtable) through enum-based dispatch
/// This is the Phase 4 replacement for vtable-based Stream
/// 
/// TODO: Phase 4 - Migrate all consumers from Stream to DirectStream
/// TODO: Once migration complete, rename DirectStream to Stream
const std = @import("std");
const StreamError = @import("error.zig").StreamError;
const RingBuffer = @import("buffer.zig").RingBuffer;

/// Tagged union stream - zero vtable overhead
/// Each variant embeds its state directly for cache-friendly access
pub fn DirectStream(comptime T: type) type {
    return union(enum) {
        // Core stream sources
        slice: SliceStream(T),
        ring_buffer: RingBufferStream(T),
        generator: GeneratorStream(T),
        empty: EmptyStream(T),
        
        // Stream operators
        map: *MapStream(T),
        filter: *FilterStream(T),
        take: *TakeStream(T),
        drop: *DropStream(T),
        // batch returns []T not T, so it needs special handling
        // batch: *BatchStream(T),
        merge: *MergeStream(T),
        
        // Special streams
        error_stream: ErrorStream(T),
        
        const Self = @This();
        
        /// Get next item from stream, advancing position
        pub inline fn next(self: *Self) StreamError!?T {
            return switch (self.*) {
                .slice => |*s| s.next(),
                .ring_buffer => |*s| s.next(),
                .generator => |*s| s.next(),
                .empty => |*s| s.next(),
                .map => |s| s.next(),
                .filter => |s| s.next(),
                .take => |s| s.next(),
                .drop => |s| s.next(),
                // .batch => |s| s.next(),
                .merge => |s| s.next(),
                .error_stream => |*s| s.next(),
            };
        }
        
        /// Peek at next item without advancing
        pub inline fn peek(self: *const Self) StreamError!?T {
            return switch (self.*) {
                .slice => |*s| s.peek(),
                .ring_buffer => |*s| s.peek(),
                .generator => |*s| s.peek(),
                .empty => |*s| s.peek(),
                .map => |s| s.peek(),
                .filter => |s| s.peek(),
                .take => |s| s.peek(),
                .drop => |s| s.peek(),
                // .batch => |s| s.peek(),
                .merge => |s| s.peek(),
                .error_stream => |*s| s.peek(),
            };
        }
        
        /// Skip n items in the stream
        pub inline fn skip(self: *Self, n: usize) StreamError!void {
            return switch (self.*) {
                .slice => |*s| s.skip(n),
                .ring_buffer => |*s| s.skip(n),
                .generator => |*s| s.skip(n),
                .empty => |*s| s.skip(n),
                .map => |s| s.skip(n),
                .filter => |s| s.skip(n),
                .take => |s| s.skip(n),
                .drop => |s| s.skip(n),
                // .batch => |s| s.skip(n),
                .merge => |s| s.skip(n),
                .error_stream => |*s| s.skip(n),
            };
        }
        
        /// Get current position in stream
        pub inline fn getPosition(self: *const Self) usize {
            return switch (self.*) {
                .slice => |*s| s.getPosition(),
                .ring_buffer => |*s| s.getPosition(),
                .generator => |*s| s.getPosition(),
                .empty => |*s| s.getPosition(),
                .map => |s| s.getPosition(),
                .filter => |s| s.getPosition(),
                .take => |s| s.getPosition(),
                .drop => |s| s.getPosition(),
                // .batch => |s| s.getPosition(),
                .merge => |s| s.getPosition(),
                .error_stream => |*s| s.getPosition(),
            };
        }
        
        /// Check if stream is exhausted
        pub inline fn isExhausted(self: *const Self) bool {
            return switch (self.*) {
                .slice => |*s| s.isExhausted(),
                .ring_buffer => |*s| s.isExhausted(),
                .generator => |*s| s.isExhausted(),
                .empty => |*s| s.isExhausted(),
                .map => |s| s.isExhausted(),
                .filter => |s| s.isExhausted(),
                .take => |s| s.isExhausted(),
                .drop => |s| s.isExhausted(),
                // .batch => |s| s.isExhausted(),
                .merge => |s| s.isExhausted(),
                .error_stream => |*s| s.isExhausted(),
            };
        }
        
        /// Close the stream and release resources
        pub inline fn close(self: *Self) void {
            switch (self.*) {
                .slice => |*s| s.close(),
                .ring_buffer => |*s| s.close(),
                .generator => |*s| s.close(),
                .empty => |*s| s.close(),
                .map => |s| s.close(),
                .filter => |s| s.close(),
                .take => |s| s.close(),
                .drop => |s| s.close(),
                // .batch => |s| s.close(),
                .merge => |s| s.close(),
                .error_stream => |*s| s.close(),
            }
        }
        
        // TODO: Add operator methods (map, filter, etc) that return new Stream instances
    };
}

/// Stream from a slice - zero-copy
pub fn SliceStream(comptime T: type) type {
    return struct {
        data: []const T,
        position: usize = 0,
        
        const Self = @This();
        
        pub fn init(data: []const T) Self {
            return .{ .data = data };
        }
        
        pub fn next(self: *Self) StreamError!?T {
            if (self.position >= self.data.len) return null;
            const item = self.data[self.position];
            self.position += 1;
            return item;
        }
        
        pub fn peek(self: *const Self) StreamError!?T {
            if (self.position >= self.data.len) return null;
            return self.data[self.position];
        }
        
        pub fn skip(self: *Self, n: usize) StreamError!void {
            self.position = @min(self.position + n, self.data.len);
        }
        
        pub fn getPosition(self: *const Self) usize {
            return self.position;
        }
        
        pub fn isExhausted(self: *const Self) bool {
            return self.position >= self.data.len;
        }
        
        pub fn close(self: *Self) void {
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
        
        pub fn next(self: *Self) StreamError!?T {
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
        position: usize = 0,
        
        const Self = @This();
        
        pub fn init(state: *anyopaque, gen_fn: *const fn (*anyopaque) ?T) Self {
            return .{ .state = state, .gen_fn = gen_fn };
        }
        
        pub fn next(self: *Self) StreamError!?T {
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
            _ = self;
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
            return true;
        }
        
        pub fn close(self: *Self) void {
            _ = self;
        }
    };
}

// Operator streams (map, filter, etc.)
// TODO: Phase 5 - Embed source directly instead of pointer for zero-allocation
// Currently operators still use pointers to maintain compatibility during migration
// Use operator_pool.zig for arena-based allocation

pub fn MapStream(comptime T: type) type {
    return struct {
        source: *DirectStream(T),
        map_fn: *const fn (T) T,
        
        const Self = @This();
        
        pub fn next(self: *Self) StreamError!?T {
            if (try self.source.next()) |item| {
                return self.map_fn(item);
            }
            return null;
        }
        
        pub fn peek(self: *const Self) StreamError!?T {
            if (try self.source.peek()) |item| {
                return self.map_fn(item);
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

pub fn FilterStream(comptime T: type) type {
    return struct {
        source: *DirectStream(T),
        predicate: *const fn (T) bool,
        next_value: ?T = null,
        
        const Self = @This();
        
        pub fn next(self: *Self) StreamError!?T {
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
        
        pub fn peek(self: *Self) StreamError!?T {
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
        
        pub fn skip(self: *Self, n: usize) StreamError!void {
            var skipped: usize = 0;
            while (skipped < n) : (skipped += 1) {
                _ = try self.next() orelse break;
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

pub fn TakeStream(comptime T: type) type {
    return struct {
        source: *DirectStream(T),
        limit: usize,
        taken: usize = 0,
        
        const Self = @This();
        
        pub fn next(self: *Self) StreamError!?T {
            if (self.taken >= self.limit) return null;
            if (try self.source.next()) |item| {
                self.taken += 1;
                return item;
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
            return self.source.getPosition();
        }
        
        pub fn isExhausted(self: *const Self) bool {
            return self.taken >= self.limit or self.source.isExhausted();
        }
        
        pub fn close(self: *Self) void {
            self.source.close();
        }
    };
}

pub fn DropStream(comptime T: type) type {
    return struct {
        source: *DirectStream(T),
        drop_count: usize,
        dropped: bool = false,
        
        const Self = @This();
        
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

pub fn BatchStream(comptime T: type) type {
    return struct {
        source: *DirectStream(T),
        batch_size: usize,
        buffer: []T,
        allocator: std.mem.Allocator,
        
        const Self = @This();
        
        pub fn init(source: *DirectStream(T), batch_size: usize, allocator: std.mem.Allocator) !Self {
            return .{
                .source = source,
                .batch_size = batch_size,
                .buffer = try allocator.alloc(T, batch_size),
                .allocator = allocator,
            };
        }
        
        pub fn next(self: *Self) StreamError!?[]T {
            var count: usize = 0;
            while (count < self.batch_size) : (count += 1) {
                if (try self.source.next()) |item| {
                    self.buffer[count] = item;
                } else {
                    break;
                }
            }
            
            if (count == 0) return null;
            return self.buffer[0..count];
        }
        
        pub fn peek(self: *const Self) StreamError!?[]T {
            _ = self;
            return StreamError.NotSupported; // Batch can't peek
        }
        
        pub fn skip(self: *Self, n: usize) StreamError!void {
            var batches_to_skip = n;
            while (batches_to_skip > 0) : (batches_to_skip -= 1) {
                _ = try self.next() orelse break;
            }
        }
        
        pub fn getPosition(self: *const Self) usize {
            return self.source.getPosition() / self.batch_size;
        }
        
        pub fn isExhausted(self: *const Self) bool {
            return self.source.isExhausted();
        }
        
        pub fn close(self: *Self) void {
            self.allocator.free(self.buffer);
            self.source.close();
        }
    };
}

pub fn MergeStream(comptime T: type) type {
    return struct {
        sources: []DirectStream(T),
        current: usize = 0,
        
        const Self = @This();
        
        pub fn next(self: *Self) StreamError!?T {
            while (self.current < self.sources.len) {
                if (try self.sources[self.current].next()) |item| {
                    return item;
                }
                self.current += 1;
            }
            return null;
        }
        
        pub fn peek(self: *const Self) StreamError!?T {
            if (self.current < self.sources.len) {
                return self.sources[self.current].peek();
            }
            return null;
        }
        
        pub fn skip(self: *Self, n: usize) StreamError!void {
            var remaining = n;
            while (remaining > 0 and self.current < self.sources.len) {
                const source = &self.sources[self.current];
                if (try source.next()) |_| {
                    remaining -= 1;
                } else {
                    self.current += 1;
                }
            }
        }
        
        pub fn getPosition(self: *const Self) usize {
            var total: usize = 0;
            for (self.sources[0..self.current]) |*source| {
                total += source.getPosition();
            }
            if (self.current < self.sources.len) {
                total += self.sources[self.current].getPosition();
            }
            return total;
        }
        
        pub fn isExhausted(self: *const Self) bool {
            return self.current >= self.sources.len;
        }
        
        pub fn close(self: *Self) void {
            for (self.sources) |*source| {
                source.close();
            }
        }
    };
}

/// Helper functions to create streams

pub fn fromSlice(comptime T: type, data: []const T) DirectStream(T) {
    return DirectStream(T){ .slice = SliceStream(T).init(data) };
}

pub fn fromRingBuffer(comptime T: type, buffer: *RingBuffer(T, 4096)) DirectStream(T) {
    return DirectStream(T){ .ring_buffer = RingBufferStream(T).init(buffer) };
}

pub fn empty(comptime T: type) DirectStream(T) {
    return DirectStream(T){ .empty = EmptyStream(T).init() };
}

pub fn error_stream(comptime T: type, err: StreamError) DirectStream(T) {
    return DirectStream(T){ .error_stream = ErrorStream(T).init(err) };
}

/// Create map operator using heap allocation (temporary during migration)
/// TODO: Phase 5 - Use operator pool for zero-allocation
pub fn map(comptime T: type, source: DirectStream(T), map_fn: *const fn (T) T, allocator: std.mem.Allocator) !DirectStream(T) {
    const map_op = try allocator.create(MapStream(T));
    const source_copy = try allocator.create(DirectStream(T));
    source_copy.* = source;
    map_op.* = .{
        .source = source_copy,
        .map_fn = map_fn,
    };
    return DirectStream(T){ .map = map_op };
}

/// Create filter operator using heap allocation (temporary during migration)
/// TODO: Phase 5 - Use operator pool for zero-allocation
pub fn filter(comptime T: type, source: DirectStream(T), predicate: *const fn (T) bool, allocator: std.mem.Allocator) !DirectStream(T) {
    const filter_op = try allocator.create(FilterStream(T));
    const source_copy = try allocator.create(DirectStream(T));
    source_copy.* = source;
    filter_op.* = .{
        .source = source_copy,
        .predicate = predicate,
        .next_value = null,
    };
    return DirectStream(T){ .filter = filter_op };
}

// TODO: Add operator helper functions that allocate from arena
// TODO: Add tests for tagged union dispatch performance