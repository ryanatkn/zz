const std = @import("std");
const Stream = @import("mod.zig").Stream;

/// Object pool for stream operator implementations
/// Provides zero-allocation operator creation through pre-allocated pools
///
/// Design:
/// - Pre-allocate fixed number of operator instances
/// - Use free list for O(1) acquire/release
/// - Each operator type has its own pool
/// - Thread-local pools to avoid contention (future)
pub fn OperatorPool(comptime Impl: type, comptime capacity: usize) type {
    return struct {
        const Self = @This();
        
        /// Pre-allocated operator instances
        items: [capacity]Impl,
        /// Free list as a bitset (1 = free, 0 = in use)
        free_mask: std.bit_set.IntegerBitSet(capacity),
        /// Allocator for any dynamic needs
        allocator: std.mem.Allocator,
        /// Statistics
        stats: Stats,
        
        pub const Stats = struct {
            total_acquires: u64 = 0,
            total_releases: u64 = 0,
            current_used: usize = 0,
            peak_used: usize = 0,
        };
        
        /// Initialize the pool with all items free
        pub fn init(allocator: std.mem.Allocator) Self {
            var pool = Self{
                .items = undefined,
                .free_mask = std.bit_set.IntegerBitSet(capacity).initFull(),
                .allocator = allocator,
                .stats = .{},
            };
            
            // Initialize all items to a safe state
            for (&pool.items) |*item| {
                item.* = std.mem.zeroes(Impl);
            }
            
            return pool;
        }
        
        /// Acquire an operator instance from the pool
        /// Returns null if pool is exhausted
        pub fn acquire(self: *Self) ?*Impl {
            // Find first free slot
            const index = self.free_mask.findFirstSet() orelse return null;
            
            // Mark as in use
            self.free_mask.unset(index);
            
            // Update stats
            self.stats.total_acquires += 1;
            self.stats.current_used += 1;
            if (self.stats.current_used > self.stats.peak_used) {
                self.stats.peak_used = self.stats.current_used;
            }
            
            return &self.items[index];
        }
        
        /// Release an operator instance back to the pool
        pub fn release(self: *Self, impl: *Impl) void {
            // Find the index of this item
            const ptr_int = @intFromPtr(impl);
            const base_int = @intFromPtr(&self.items[0]);
            
            if (ptr_int < base_int) return; // Not from this pool
            
            const offset = ptr_int - base_int;
            const index = offset / @sizeOf(Impl);
            
            if (index >= capacity) return; // Not from this pool
            
            // Clear the operator state
            impl.* = std.mem.zeroes(Impl);
            
            // Mark as free
            self.free_mask.set(index);
            
            // Update stats
            self.stats.total_releases += 1;
            self.stats.current_used -= 1;
        }
        
        /// Get current pool statistics
        pub inline fn getStats(self: *const Self) Stats {
            return self.stats;
        }
        
        /// Check if pool has available slots
        pub inline fn hasAvailable(self: *const Self) bool {
            return self.free_mask.count() > 0;
        }
        
        /// Get number of available slots
        pub inline fn availableCount(self: *const Self) usize {
            return self.free_mask.count();
        }
        
        /// Reset the pool, freeing all items
        pub fn reset(self: *Self) void {
            // Clear all items
            for (&self.items) |*item| {
                item.* = std.mem.zeroes(Impl);
            }
            
            // Mark all as free
            self.free_mask = std.bit_set.IntegerBitSet(capacity).initFull();
            
            // Reset current used count
            self.stats.current_used = 0;
        }
    };
}

/// Global operator pools (initialized on first use)
/// TODO: Make these thread-local in multi-threaded contexts
pub const GlobalPools = struct {
    var initialized = false;
    var allocator: std.mem.Allocator = undefined;
    
    // Pools for different operator types
    // Adjust capacity based on expected usage patterns
    pub var map_pool_64: ?*OperatorPool(MapImpl64, 64) = null;
    pub var filter_pool_64: ?*OperatorPool(FilterImpl64, 64) = null;
    pub var batch_pool_32: ?*OperatorPool(BatchImpl32, 32) = null;
    
    /// Dummy types for sizing - actual types defined in operators.zig
    const MapImpl64 = [64]u8; // Placeholder size
    const FilterImpl64 = [64]u8;
    const BatchImpl32 = [128]u8; // Batch needs more space
    
    pub fn init(alloc: std.mem.Allocator) !void {
        if (initialized) return;
        
        allocator = alloc;
        
        // Create pools
        // TODO: These should use actual operator impl types
        // For now, using placeholder pools for testing
        
        initialized = true;
    }
    
    pub fn deinit() void {
        if (!initialized) return;
        
        // Free pools if allocated
        if (map_pool_64) |pool| {
            allocator.destroy(pool);
            map_pool_64 = null;
        }
        if (filter_pool_64) |pool| {
            allocator.destroy(pool);
            filter_pool_64 = null;
        }
        if (batch_pool_32) |pool| {
            allocator.destroy(pool);
            batch_pool_32 = null;
        }
        
        initialized = false;
    }
};

test "OperatorPool basic operations" {
    const testing = std.testing;
    
    // Simple test operator type
    const TestOp = struct {
        value: u32,
        active: bool,
    };
    
    var pool = OperatorPool(TestOp, 4).init(testing.allocator);
    
    // Pool should start with all slots available
    try testing.expectEqual(@as(usize, 4), pool.availableCount());
    try testing.expect(pool.hasAvailable());
    
    // Acquire operators
    const op1 = pool.acquire().?;
    const op2 = pool.acquire().?;
    
    try testing.expectEqual(@as(usize, 2), pool.availableCount());
    try testing.expectEqual(@as(usize, 2), pool.stats.current_used);
    
    // Use the operators
    op1.value = 42;
    op1.active = true;
    op2.value = 100;
    op2.active = false;
    
    // Release back to pool
    pool.release(op1);
    try testing.expectEqual(@as(usize, 3), pool.availableCount());
    try testing.expectEqual(@as(usize, 1), pool.stats.current_used);
    
    // Released operator should be zeroed
    try testing.expectEqual(@as(u32, 0), op1.value);
    try testing.expect(!op1.active);
    
    pool.release(op2);
    try testing.expectEqual(@as(usize, 4), pool.availableCount());
    try testing.expectEqual(@as(usize, 0), pool.stats.current_used);
}

test "OperatorPool exhaustion" {
    const testing = std.testing;
    
    const TestOp = struct { id: u32 };
    
    var pool = OperatorPool(TestOp, 2).init(testing.allocator);
    
    // Acquire all slots
    const op1 = pool.acquire().?;
    _ = pool.acquire().?;
    
    // Pool should be exhausted
    try testing.expect(!pool.hasAvailable());
    try testing.expect(pool.acquire() == null);
    
    // Release one and try again
    pool.release(op1);
    const op3 = pool.acquire();
    try testing.expect(op3 != null);
}

test "OperatorPool statistics" {
    const testing = std.testing;
    
    const TestOp = struct { data: [16]u8 };
    
    var pool = OperatorPool(TestOp, 8).init(testing.allocator);
    
    // Acquire and release multiple times
    var ops: [5]*TestOp = undefined;
    
    for (&ops) |*op| {
        op.* = pool.acquire().?;
    }
    
    // Check peak usage
    try testing.expectEqual(@as(usize, 5), pool.stats.peak_used);
    try testing.expectEqual(@as(usize, 5), pool.stats.current_used);
    
    // Release some
    for (ops[0..3]) |op| {
        pool.release(op);
    }
    
    try testing.expectEqual(@as(usize, 2), pool.stats.current_used);
    try testing.expectEqual(@as(usize, 5), pool.stats.peak_used); // Peak unchanged
    
    // Reset pool
    pool.reset();
    try testing.expectEqual(@as(usize, 0), pool.stats.current_used);
    try testing.expectEqual(@as(usize, 8), pool.availableCount());
}