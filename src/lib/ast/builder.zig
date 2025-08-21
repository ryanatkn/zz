/// Generic AST Builder - Arena allocation patterns for any AST type
///
/// Provides memory management patterns for building ASTs with single-free cleanup.
/// Each language implements its own node creation methods using these utilities.
/// Uses comptime duck typing to work with any AST type that has:
/// - An arena field or arena allocator method
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Generic Arena Builder factory for any AST type
pub fn ArenaBuilder(comptime ASTType: type) type {
    return struct {
        arena: *std.heap.ArenaAllocator,
        source: []const u8,
        allocator: Allocator, // Parent allocator

        const Self = @This();

        pub fn init(allocator: Allocator, source: []const u8) !Self {
            const arena = try allocator.create(std.heap.ArenaAllocator);
            arena.* = std.heap.ArenaAllocator.init(allocator);

            return .{
                .arena = arena,
                .source = source,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.arena.deinit();
            self.allocator.destroy(self.arena);
        }

        /// Get arena allocator for node creation
        pub inline fn arenaAllocator(self: *Self) Allocator {
            return self.arena.allocator();
        }

        /// Duplicate string into arena for owned storage
        pub inline fn ownString(self: *Self, str: []const u8) ![]const u8 {
            return self.arena.allocator().dupe(u8, str);
        }

        /// Create array of nodes in arena
        pub inline fn createNodeArray(self: *Self, comptime NodeType: type, len: usize) ![]NodeType {
            return try self.arena.allocator().alloc(NodeType, len);
        }

        /// Create single node in arena
        pub inline fn createNode(self: *Self, comptime NodeType: type) !*NodeType {
            return try self.arena.allocator().create(NodeType);
        }

        /// Finalize into AST - language implements this
        pub fn build(self: *Self, root: anytype) ASTType {
            // This is implemented by each language's builder
            // since they know their AST structure
            return ASTType{
                .root = root,
                .arena = self.arena,
                .source = self.source,
                // ... other language-specific fields
            };
        }
    };
}

/// Convenience function to create an arena builder
pub fn createArenaBuilder(
    comptime ASTType: type,
    allocator: Allocator,
    source: []const u8,
) !ArenaBuilder(ASTType) {
    return ArenaBuilder(ASTType).init(allocator, source);
}

/// Generic node creation helper that can be used by any language
pub inline fn createNodeInArena(
    arena: Allocator,
    comptime NodeType: type,
    node_data: NodeType,
) !*NodeType {
    const node = try arena.create(NodeType);
    node.* = node_data;
    return node;
}

/// Generic string duplication helper
pub inline fn ownStringInArena(arena: Allocator, str: []const u8) ![]const u8 {
    return arena.dupe(u8, str);
}

/// Generic array creation helper
pub inline fn createArrayInArena(
    arena: Allocator,
    comptime T: type,
    items: []const T,
) ![]T {
    return arena.dupe(T, items);
}