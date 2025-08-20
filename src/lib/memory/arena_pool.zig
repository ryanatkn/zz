const std = @import("std");

/// ArenaPool - Rotating arena allocator pool for zero-allocation patterns
///
/// Implements a 4-arena rotation strategy per TODO_STREAM_FIRST_PRINCIPLES.md
/// - 4 arenas to allow generational collection
/// - Rotate on generation boundaries
/// - Bulk allocate, bulk free
/// - Zero allocations in hot paths
///
/// Usage:
/// ```zig
/// var pool = ArenaPool.init(allocator);
/// defer pool.deinit();
///
/// const arena = pool.acquire();
/// const mem = arena.allocator().alloc(u8, 1024);
/// // ... use memory ...
/// pool.rotate(); // Clear current arena, move to next
/// ```
pub const ArenaPool = struct {
    /// Fixed 4 arenas for generational rotation
    arenas: [4]std.heap.ArenaAllocator,
    /// Current arena index (2 bits for 4 arenas)
    current: u2,
    /// Backing allocator for arena memory
    backing_allocator: std.mem.Allocator,
    /// Generation counter for tracking rotations
    generation: u32,

    /// Initialize the arena pool with backing allocator
    pub fn init(backing: std.mem.Allocator) ArenaPool {
        return .{
            .arenas = .{
                std.heap.ArenaAllocator.init(backing),
                std.heap.ArenaAllocator.init(backing),
                std.heap.ArenaAllocator.init(backing),
                std.heap.ArenaAllocator.init(backing),
            },
            .current = 0,
            .backing_allocator = backing,
            .generation = 0,
        };
    }

    /// Clean up all arenas
    pub fn deinit(self: *ArenaPool) void {
        for (&self.arenas) |*arena| {
            arena.deinit();
        }
    }

    /// Get the current active arena
    pub inline fn acquire(self: *ArenaPool) *std.heap.ArenaAllocator {
        return &self.arenas[self.current];
    }

    /// Get allocator from current arena
    pub inline fn allocator(self: *ArenaPool) std.mem.Allocator {
        return self.arenas[self.current].allocator();
    }

    /// Rotate to next arena, clearing the new current one
    /// This is the key operation for generational collection
    pub fn rotate(self: *ArenaPool) void {
        // Move to next arena (wraps automatically with u2)
        self.current +%= 1;
        self.generation += 1;

        // Reset the new current arena, retaining capacity
        _ = self.arenas[self.current].reset(.retain_capacity);
    }

    /// Force clear all arenas (useful for major collections)
    pub fn clearAll(self: *ArenaPool) void {
        for (&self.arenas) |*arena| {
            _ = arena.reset(.retain_capacity);
        }
    }

    /// Get current generation number
    pub inline fn getGeneration(self: *const ArenaPool) u32 {
        return self.generation;
    }

    /// Get memory statistics
    pub fn getStats(self: *const ArenaPool) PoolStats {
        // For now, just return basic stats
        // TODO: Phase 2 - Get actual memory usage from arenas
        return .{
            .total_allocated = 0,
            .total_capacity = 0,
            .current_arena = self.current,
            .generation = self.generation,
        };
    }
};

pub const PoolStats = struct {
    total_allocated: usize,
    total_capacity: usize,
    current_arena: u2,
    generation: u32,
};

/// Scoped arena helper - automatically restores arena state
pub const ScopedArena = struct {
    pool: *ArenaPool,
    saved_state: std.heap.ArenaAllocator.State,
    arena_index: u2,

    pub fn init(pool: *ArenaPool) ScopedArena {
        const arena = pool.acquire();
        return .{
            .pool = pool,
            .saved_state = arena.state,
            .arena_index = pool.current,
        };
    }

    pub fn deinit(self: *ScopedArena) void {
        // Only restore if we're still on the same arena
        if (self.pool.current == self.arena_index) {
            self.pool.arenas[self.arena_index].state = self.saved_state;
        }
    }

    pub fn allocator(self: *ScopedArena) std.mem.Allocator {
        return self.pool.arenas[self.arena_index].allocator();
    }
};

test "ArenaPool basic operations" {
    const testing = std.testing;

    var pool = ArenaPool.init(testing.allocator);
    defer pool.deinit();

    // Initial state
    try testing.expectEqual(@as(u2, 0), pool.current);
    try testing.expectEqual(@as(u32, 0), pool.generation);

    // Allocate from current arena
    const arena1 = pool.acquire();
    const mem1 = try arena1.allocator().alloc(u8, 100);
    @memset(mem1, 'A');

    // Rotate to next arena
    pool.rotate();
    try testing.expectEqual(@as(u2, 1), pool.current);
    try testing.expectEqual(@as(u32, 1), pool.generation);

    // Allocate from new arena
    const arena2 = pool.acquire();
    const mem2 = try arena2.allocator().alloc(u8, 200);
    @memset(mem2, 'B');

    // Verify different arenas
    try testing.expect(arena1 != arena2);
}

test "ArenaPool rotation wraps around" {
    const testing = std.testing;

    var pool = ArenaPool.init(testing.allocator);
    defer pool.deinit();

    // Rotate through all 4 arenas
    for (0..4) |i| {
        try testing.expectEqual(@as(u2, @intCast(i % 4)), pool.current);
        pool.rotate();
    }

    // Should wrap back to 0
    try testing.expectEqual(@as(u2, 0), pool.current);
    try testing.expectEqual(@as(u32, 4), pool.generation);
}

test "ArenaPool memory reuse after rotation" {
    const testing = std.testing;

    var pool = ArenaPool.init(testing.allocator);
    defer pool.deinit();

    // Allocate in arena 0
    const alloc = pool.allocator();
    _ = try alloc.alloc(u8, 1024);

    // Rotate through all arenas and back
    for (0..4) |_| {
        pool.rotate();
    }

    // Back at arena 0, memory should be reused
    try testing.expectEqual(@as(u2, 0), pool.current);

    // Can allocate again (memory was cleared)
    const alloc2 = pool.allocator();
    _ = try alloc2.alloc(u8, 2048);
}

// TODO: Phase 2 - Add ScopedArena cleanup test once arena state tracking is implemented
