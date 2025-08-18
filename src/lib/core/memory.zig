const std = @import("std");

/// Memory utility functions for common allocation patterns
/// Reduces boilerplate and centralizes memory management

/// Duplicate an array of strings
pub fn dupeStringArray(allocator: std.mem.Allocator, array: []const []const u8) ![][]const u8 {
    const result = try allocator.alloc([]const u8, array.len);
    errdefer allocator.free(result);
    
    for (array, 0..) |str, i| {
        result[i] = try allocator.dupe(u8, str);
    }
    
    return result;
}

/// Free an array of strings that was allocated with dupeStringArray
pub fn freeStringArray(allocator: std.mem.Allocator, array: [][]const u8) void {
    for (array) |str| {
        allocator.free(str);
    }
    allocator.free(array);
}

/// Duplicate a string, returning null for empty strings
pub fn dupeStringOrNull(allocator: std.mem.Allocator, str: []const u8) !?[]const u8 {
    if (str.len == 0) return null;
    return try allocator.dupe(u8, str);
}

/// Duplicate an optional string
pub fn dupeOptionalString(allocator: std.mem.Allocator, str: ?[]const u8) !?[]const u8 {
    if (str) |s| {
        return try allocator.dupe(u8, s);
    }
    return null;
}

/// Arena-based string builder for efficient concatenation
pub const StringBuilder = struct {
    arena: std.heap.ArenaAllocator,
    buffer: std.ArrayList(u8),
    
    pub fn init(allocator: std.mem.Allocator) StringBuilder {
        return .{
            .arena = std.heap.ArenaAllocator.init(allocator),
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }
    
    pub fn deinit(self: *StringBuilder) void {
        self.buffer.deinit();
        self.arena.deinit();
    }
    
    pub fn append(self: *StringBuilder, str: []const u8) !void {
        try self.buffer.appendSlice(str);
    }
    
    pub fn appendFmt(self: *StringBuilder, comptime fmt: []const u8, args: anytype) !void {
        const formatted = try std.fmt.allocPrint(self.arena.allocator(), fmt, args);
        try self.buffer.appendSlice(formatted);
    }
    
    pub fn toOwnedSlice(self: *StringBuilder) ![]u8 {
        return self.buffer.toOwnedSlice();
    }
};

/// Memory pool for reusing allocations
pub const MemoryPool = struct {
    allocator: std.mem.Allocator,
    chunks: std.ArrayList([]u8),
    free_list: std.ArrayList([]u8),
    chunk_size: usize,
    
    pub fn init(allocator: std.mem.Allocator, chunk_size: usize) MemoryPool {
        return .{
            .allocator = allocator,
            .chunks = std.ArrayList([]u8).init(allocator),
            .free_list = std.ArrayList([]u8).init(allocator),
            .chunk_size = chunk_size,
        };
    }
    
    pub fn deinit(self: *MemoryPool) void {
        for (self.chunks.items) |chunk| {
            self.allocator.free(chunk);
        }
        self.chunks.deinit();
        self.free_list.deinit();
    }
    
    pub fn alloc(self: *MemoryPool) ![]u8 {
        if (self.free_list.pop()) |chunk| {
            return chunk;
        }
        
        const chunk = try self.allocator.alloc(u8, self.chunk_size);
        try self.chunks.append(chunk);
        return chunk;
    }
    
    pub fn free(self: *MemoryPool, chunk: []u8) !void {
        if (chunk.len != self.chunk_size) {
            return error.InvalidChunkSize;
        }
        try self.free_list.append(chunk);
    }
};

/// Scoped allocator that tracks all allocations for easy cleanup
pub const ScopedAllocator = struct {
    parent: std.mem.Allocator,
    allocations: std.ArrayList([]u8),
    
    pub fn init(parent: std.mem.Allocator) ScopedAllocator {
        return .{
            .parent = parent,
            .allocations = std.ArrayList([]u8).init(parent),
        };
    }
    
    pub fn deinit(self: *ScopedAllocator) void {
        // Free all tracked allocations in reverse order
        while (self.allocations.pop()) |allocation| {
            self.parent.free(allocation);
        }
        self.allocations.deinit();
    }
    
    pub fn alloc(self: *ScopedAllocator, comptime T: type, n: usize) ![]T {
        const bytes = try self.parent.alloc(T, n);
        if (T == u8) {
            try self.allocations.append(bytes);
        } else {
            const byte_slice = std.mem.sliceAsBytes(bytes);
            try self.allocations.append(byte_slice);
        }
        return bytes;
    }
    
    pub fn dupe(self: *ScopedAllocator, comptime T: type, data: []const T) ![]T {
        const bytes = try self.parent.dupe(T, data);
        if (T == u8) {
            try self.allocations.append(bytes);
        } else {
            const byte_slice = std.mem.sliceAsBytes(bytes);
            try self.allocations.append(byte_slice);
        }
        return bytes;
    }
};

// Tests
test "dupeStringArray" {
    const allocator = std.testing.allocator;
    
    const original = [_][]const u8{ "hello", "world", "test" };
    const duped = try dupeStringArray(allocator, &original);
    defer freeStringArray(allocator, duped);
    
    try std.testing.expectEqual(@as(usize, 3), duped.len);
    try std.testing.expectEqualStrings("hello", duped[0]);
    try std.testing.expectEqualStrings("world", duped[1]);
    try std.testing.expectEqualStrings("test", duped[2]);
}

test "dupeOptionalString" {
    const allocator = std.testing.allocator;
    
    const result1 = try dupeOptionalString(allocator, "test");
    defer if (result1) |r| allocator.free(r);
    try std.testing.expect(result1 != null);
    try std.testing.expectEqualStrings("test", result1.?);
    
    const result2 = try dupeOptionalString(allocator, null);
    try std.testing.expect(result2 == null);
}

test "StringBuilder" {
    const allocator = std.testing.allocator;
    
    var builder = StringBuilder.init(allocator);
    defer builder.deinit();
    
    try builder.append("Hello");
    try builder.append(" ");
    try builder.appendFmt("World {d}!", .{42});
    
    const result = try builder.toOwnedSlice();
    defer allocator.free(result);
    
    try std.testing.expectEqualStrings("Hello World 42!", result);
}

test "MemoryPool" {
    const allocator = std.testing.allocator;
    
    var pool = MemoryPool.init(allocator, 1024);
    defer pool.deinit();
    
    const chunk1 = try pool.alloc();
    const chunk2 = try pool.alloc();
    
    try pool.free(chunk1);
    
    const chunk3 = try pool.alloc();
    try std.testing.expectEqual(@intFromPtr(chunk1.ptr), @intFromPtr(chunk3.ptr));
    
    try pool.free(chunk2);
    try pool.free(chunk3);
}

test "ScopedAllocator" {
    const allocator = std.testing.allocator;
    
    var scoped = ScopedAllocator.init(allocator);
    defer scoped.deinit();
    
    const str1 = try scoped.dupe(u8, "test");
    const str2 = try scoped.alloc(u8, 100);
    const str3 = try scoped.dupe(u8, "another");
    
    // All allocations will be freed when scoped.deinit() is called
    try std.testing.expectEqualStrings("test", str1);
    try std.testing.expectEqual(@as(usize, 100), str2.len);
    try std.testing.expectEqualStrings("another", str3);
}