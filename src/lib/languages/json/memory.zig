const std = @import("std");
const Node = @import("ast.zig").Node;
const NodePool = @import("node_pool.zig").NodePool;
const ArrayPool = @import("node_pool.zig").ArrayPool;

/// Memory usage statistics for performance monitoring
pub const MemoryStats = struct {
    node_pool_capacity: usize,
    node_pool_used: usize,
    node_pool_utilization: usize, // Percentage
    array_pool_allocated: usize,
};

/// Memory management for JSON parsing
///
/// This module provides proper memory management for the JSON parser,
/// ensuring all allocations are tracked and properly freed.
/// Uses arena allocator pattern for temporary parse-time allocations.
/// Context for managing parse-time allocations
pub const ParseContext = struct {
    /// Main allocator for final results
    allocator: std.mem.Allocator,

    /// Arena for temporary parse-time allocations
    arena: std.heap.ArenaAllocator,

    /// High-performance node pool for AST nodes
    node_pool: NodePool,

    /// Array pool for object properties and array elements
    array_pool: ArrayPool,

    /// List of texts that need to be transferred to AST
    transferred_texts: std.ArrayList([]const u8),

    /// List of node arrays that need to be transferred to AST
    transferred_nodes: std.ArrayList([]Node),

    const Self = @This();

    /// Initialize parse context with node pools
    /// Edge case handling: Graceful fallback on pool allocation failure
    pub fn init(allocator: std.mem.Allocator) ParseContext {
        // Try to initialize with standard capacity, fallback to smaller size on failure
        const node_pool = NodePool.init(allocator) catch
            NodePool.initWithCapacity(allocator, 256) catch
            NodePool.initWithCapacity(allocator, 64) catch
            NodePool.initWithCapacity(allocator, 16) catch blk: {
            // Last resort: very small pool, but still functional
            std.log.warn("JSON parser using minimal node pool due to memory pressure", .{});
            break :blk NodePool.initWithCapacity(allocator, 4) catch unreachable;
        };

        var context = ParseContext{
            .allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .node_pool = node_pool,
            .array_pool = undefined, // Will be initialized below
            .transferred_texts = std.ArrayList([]const u8).init(allocator),
            .transferred_nodes = std.ArrayList([]Node).init(allocator),
        };

        // Initialize ArrayPool with arena reference
        context.array_pool = ArrayPool.init(&context.arena);

        return context;
    }

    /// Deinitialize and free all memory
    pub fn deinit(self: *Self) void {
        // Clean up pools first
        self.node_pool.deinit();
        self.array_pool.deinit();

        // Arena automatically frees all temporary allocations
        self.arena.deinit();

        // Free the list of transferred texts (but not the texts themselves)
        self.transferred_texts.deinit();

        // Free the list of transferred nodes (but not the nodes themselves)
        self.transferred_nodes.deinit();
    }

    /// Get arena allocator for temporary allocations
    pub fn tempAllocator(self: *Self) std.mem.Allocator {
        return self.arena.allocator();
    }

    /// Allocate a node from the high-performance pool
    /// Edge case handling: Automatic pool growth on exhaustion
    pub fn allocateNode(self: *Self) !*Node {
        return self.node_pool.allocate();
    }

    /// Allocate multiple nodes for bulk operations (arrays/objects)
    /// Edge case handling: Large allocations, memory pressure
    pub fn allocateNodes(self: *Self, count: usize) ![]Node {
        return self.node_pool.allocateMany(count);
    }

    /// Allocate array for object properties or array elements
    /// Uses size-class pooling to reduce fragmentation
    pub fn allocateArray(self: *Self, size: usize) ![]Node {
        return self.array_pool.allocate(size);
    }

    /// Reset pools for parser reuse (keeps memory allocated)
    /// Useful for parsing multiple documents efficiently
    pub fn resetPools(self: *Self) void {
        self.node_pool.reset();
        // ArrayPool doesn't need reset - it reuses automatically
    }

    /// Get memory usage statistics for monitoring performance
    pub fn getPoolStats(self: *Self) MemoryStats {
        const node_stats = self.node_pool.getStats();
        return MemoryStats{
            .node_pool_capacity = node_stats.capacity,
            .node_pool_used = node_stats.used,
            .node_pool_utilization = node_stats.utilization_percent,
            .array_pool_allocated = self.array_pool.getTotalAllocated(),
        };
    }

    /// Track text that will be owned by the AST
    pub fn trackText(self: *Self, text: []const u8) ![]const u8 {
        // Text is already allocated by caller, just track it
        try self.transferred_texts.append(text);
        return text;
    }

    /// Track node array that will be owned by the AST
    pub fn trackNodes(self: *Self, nodes: []const Node) ![]Node {
        // Allocate permanent storage for the nodes
        const owned = try self.allocator.alloc(Node, nodes.len);
        @memcpy(owned, nodes);
        try self.transferred_nodes.append(owned);
        return owned;
    }

    /// Transfer ownership of all AST texts to caller
    /// After this, the caller is responsible for freeing the texts
    pub fn transferOwnership(self: *Self) []const []const u8 {
        const texts = self.transferred_texts.toOwnedSlice() catch &[_][]const u8{};
        return texts;
    }

    /// Free transferred texts (utility for cleanup)
    pub fn freeTransferredTexts(allocator: std.mem.Allocator, texts: []const []const u8) void {
        for (texts) |text| {
            allocator.free(text);
        }
        allocator.free(texts);
    }
};

/// AST memory tracker
/// Tracks allocations that are owned by the AST
pub const AstMemory = struct {
    allocator: std.mem.Allocator,
    owned_texts: []const []const u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, owned_texts: []const []const u8) AstMemory {
        return .{
            .allocator = allocator,
            .owned_texts = owned_texts,
        };
    }

    pub fn deinit(self: *Self) void {
        ParseContext.freeTransferredTexts(self.allocator, self.owned_texts);
    }
};
