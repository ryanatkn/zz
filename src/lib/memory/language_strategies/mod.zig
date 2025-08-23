const std = @import("std");

// Re-export core types
pub const MemoryStrategy = @import("strategy.zig").MemoryStrategy;
pub const NodeStrategy = @import("strategy.zig").NodeStrategy;
pub const ArrayStrategy = @import("strategy.zig").ArrayStrategy;
pub const StringStrategy = @import("strategy.zig").StringStrategy;

pub const MemoryStats = @import("stats.zig").MemoryStats;
pub const MemoryContext = @import("context.zig").MemoryContext;

// Re-export allocators
pub const NodeAllocator = @import("node_allocator.zig").NodeAllocator;
pub const ArrayAllocator = @import("array_allocator.zig").ArrayAllocator;
pub const StringAllocator = @import("string_allocator.zig").StringAllocator;

// Re-export language defaults
pub const language_defaults = @import("language_defaults.zig");

// Convenience functions
pub fn createDefault(comptime NodeType: type, allocator: std.mem.Allocator) !MemoryContext(NodeType) {
    return MemoryContext(NodeType).init(allocator, language_defaults.DEFAULT_STRATEGY);
}

pub fn createForJson(comptime NodeType: type, allocator: std.mem.Allocator) !MemoryContext(NodeType) {
    return MemoryContext(NodeType).init(allocator, language_defaults.JSON_DEFAULT_STRATEGY);
}

pub fn createForZon(comptime NodeType: type, allocator: std.mem.Allocator) !MemoryContext(NodeType) {
    return MemoryContext(NodeType).init(allocator, language_defaults.ZON_DEFAULT_STRATEGY);
}