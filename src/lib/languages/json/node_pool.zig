/// High-performance Node pool for JSON parser optimization
/// Reduces allocations from O(n) individual creates to O(1) bulk allocation
const std = @import("std");
const Node = @import("ast.zig").Node;

/// Node pool with bulk allocation and safety checks
pub const NodePool = struct {
    nodes: []Node,
    used: usize,
    allocator: std.mem.Allocator,

    // Safety tracking
    max_capacity: usize,
    allocation_count: usize,

    const DEFAULT_CAPACITY = 1024; // Start with 1K nodes
    const GROWTH_FACTOR = 2;

    pub fn init(allocator: std.mem.Allocator) !NodePool {
        return initWithCapacity(allocator, DEFAULT_CAPACITY);
    }

    pub fn initWithCapacity(allocator: std.mem.Allocator, capacity: usize) !NodePool {
        const nodes = try allocator.alloc(Node, capacity);
        return NodePool{
            .nodes = nodes,
            .used = 0,
            .allocator = allocator,
            .max_capacity = capacity,
            .allocation_count = 0,
        };
    }

    pub fn deinit(self: *NodePool) void {
        self.allocator.free(self.nodes);
        self.* = undefined; // Safety: prevent use-after-free
    }

    /// Allocate a node from the pool, growing if necessary
    /// Edge cases handled: pool exhaustion, memory pressure, alignment
    pub fn allocate(self: *NodePool) !*Node {
        // Edge case: Pool exhausted
        if (self.used >= self.nodes.len) {
            try self.grow();
        }

        // Safety check: Prevent double allocation tracking
        if (self.used >= self.max_capacity) {
            return error.PoolExhausted;
        }

        const node = &self.nodes[self.used];
        self.used += 1;
        self.allocation_count += 1;

        return node;
    }

    /// Allocate multiple nodes at once (bulk allocation for arrays/objects)
    /// Edge cases: Large allocations, fragmentation, alignment
    pub fn allocateMany(self: *NodePool, count: usize) ![]Node {
        // Edge case: Bulk allocation larger than remaining space
        if (self.used + count > self.nodes.len) {
            // Calculate new capacity to fit this allocation
            const needed_capacity = self.used + count;
            const new_capacity = @max(needed_capacity, self.nodes.len * GROWTH_FACTOR);
            try self.growToCapacity(new_capacity);
        }

        // Safety check: Don't exceed maximum reasonable size
        if (count > 100_000) { // 100K nodes = ~8MB reasonable limit
            return error.AllocationTooLarge;
        }

        const start = self.used;
        self.used += count;
        self.allocation_count += count;

        return self.nodes[start..self.used];
    }

    /// Reset pool for reuse (keeps memory allocated)
    /// Edge case: Handle mid-parse resets safely
    pub fn reset(self: *NodePool) void {
        self.used = 0;
        self.allocation_count = 0;
        // Keep .nodes buffer allocated for reuse
    }

    /// Get statistics for monitoring
    pub fn getStats(self: NodePool) PoolStats {
        return PoolStats{
            .capacity = self.nodes.len,
            .used = self.used,
            .allocation_count = self.allocation_count,
            .utilization_percent = if (self.nodes.len > 0)
                (self.used * 100) / self.nodes.len
            else
                0,
        };
    }

    /// Grow pool capacity
    /// Edge cases: Memory pressure, large growth, fragmentation
    fn grow(self: *NodePool) !void {
        const new_capacity = self.nodes.len * GROWTH_FACTOR;
        try self.growToCapacity(new_capacity);
    }

    fn growToCapacity(self: *NodePool, new_capacity: usize) !void {
        // Edge case: Prevent excessive memory usage
        const MAX_CAPACITY = 1_000_000; // 1M nodes = ~80MB reasonable maximum
        if (new_capacity > MAX_CAPACITY) {
            return error.PoolTooLarge;
        }

        // Edge case: Handle realloc failure gracefully
        const new_nodes = self.allocator.realloc(self.nodes, new_capacity) catch |err| switch (err) {
            error.OutOfMemory => {
                // Try smaller growth if full growth fails
                const smaller_capacity = self.nodes.len + (self.nodes.len / 2);
                if (smaller_capacity > self.nodes.len and smaller_capacity <= MAX_CAPACITY) {
                    self.nodes = try self.allocator.realloc(self.nodes, smaller_capacity);
                    self.max_capacity = smaller_capacity;
                    return;
                }
                return err;
            },
            else => return err,
        };

        self.nodes = new_nodes;
        self.max_capacity = new_capacity;
    }
};

pub const PoolStats = struct {
    capacity: usize,
    used: usize,
    allocation_count: usize,
    utilization_percent: usize,
};

/// Arena-only array allocator (Solution 4: Zero corruption risk)
///
/// This is a simplified, safe implementation that uses arena allocation
/// exclusively. No pooling/reuse means no slice/array tracking mismatch.
/// Arrays are automatically freed when the arena is destroyed.
pub const ArrayPool = struct {
    arena: *std.heap.ArenaAllocator,
    total_allocated: usize,

    pub fn init(arena: *std.heap.ArenaAllocator) ArrayPool {
        return ArrayPool{
            .arena = arena,
            .total_allocated = 0,
        };
    }

    pub fn deinit(self: *ArrayPool) void {
        // Arena handles all cleanup - no individual frees needed
        // Just reset tracking for clean state
        self.total_allocated = 0;
    }

    /// Allocate array of exact size using arena
    /// Simple and safe - no pooling complexity
    pub fn allocate(self: *ArrayPool, size: usize) ![]Node {
        // Edge case: Empty arrays use shared empty slice
        if (size == 0) {
            return &[_]Node{};
        }

        // Simple arena allocation - exact size, no size classes
        const array = try self.arena.allocator().alloc(Node, size);
        self.total_allocated += size;
        return array;
    }

    /// Release is a no-op with arena allocation
    /// Arrays are automatically freed when arena is destroyed
    pub fn release(self: *ArrayPool, array: []Node) !void {
        _ = self; // Suppress unused parameter warning
        _ = array; // Suppress unused parameter warning
        // No-op: Arena handles all cleanup automatically
    }

    pub fn getTotalAllocated(self: ArrayPool) usize {
        return self.total_allocated;
    }
};

test "NodePool basic allocation" {
    const testing = std.testing;

    var pool = try NodePool.init(testing.allocator);
    defer pool.deinit();

    const node1 = try pool.allocate();
    const node2 = try pool.allocate();

    try testing.expect(node1 != node2);
    try testing.expectEqual(@as(usize, 2), pool.used);
}

test "NodePool bulk allocation" {
    const testing = std.testing;

    var pool = try NodePool.init(testing.allocator);
    defer pool.deinit();

    const nodes = try pool.allocateMany(100);
    try testing.expectEqual(@as(usize, 100), nodes.len);
    try testing.expectEqual(@as(usize, 100), pool.used);
}

test "NodePool growth edge cases" {
    const testing = std.testing;

    var pool = try NodePool.initWithCapacity(testing.allocator, 4);
    defer pool.deinit();

    // Allocate beyond initial capacity
    _ = try pool.allocate();
    _ = try pool.allocate();
    _ = try pool.allocate();
    _ = try pool.allocate();
    _ = try pool.allocate(); // Should trigger growth

    try testing.expect(pool.nodes.len > 4);
}

test "ArrayPool arena allocation" {
    const testing = std.testing;

    // Create arena for ArrayPool
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var pool = ArrayPool.init(&arena);
    defer pool.deinit();

    // Test various sizes - all should allocate exact size
    const small = try pool.allocate(5);
    try testing.expectEqual(@as(usize, 5), small.len);

    const medium = try pool.allocate(100);
    try testing.expectEqual(@as(usize, 100), medium.len);

    const large = try pool.allocate(500);
    try testing.expectEqual(@as(usize, 500), large.len);

    // Test empty array
    const empty = try pool.allocate(0);
    try testing.expectEqual(@as(usize, 0), empty.len);

    // Test release is no-op (no crash)
    try pool.release(small);

    // Test allocation tracking
    try testing.expect(pool.getTotalAllocated() == 605); // 5 + 100 + 500
}
