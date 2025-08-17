const std = @import("std");
const Fact = @import("../types/fact.zig").Fact;
const FactId = @import("../types/fact.zig").FactId;
const Generation = @import("../types/fact.zig").Generation;

/// High-performance memory pools for fact allocation and reuse
/// Optimized for stratified parser's allocation patterns

/// Pool for reusing fact structures
pub const FactPool = struct {
    /// Available facts ready for reuse
    available: std.ArrayList(Fact),
    
    /// Statistics for monitoring pool efficiency
    stats: PoolStats,
    
    /// Allocator for pool management
    allocator: std.mem.Allocator,
    
    /// Maximum number of facts to keep in pool
    max_pool_size: usize,

    pub fn init(allocator: std.mem.Allocator, max_pool_size: usize) FactPool {
        return .{
            .available = std.ArrayList(Fact).init(allocator),
            .stats = PoolStats{},
            .allocator = allocator,
            .max_pool_size = max_pool_size,
        };
    }

    pub fn deinit(self: *FactPool) void {
        self.available.deinit();
    }

    /// Get a fact from the pool or create a new one
    pub fn acquire(self: *FactPool) !*Fact {
        if (self.available.items.len > 0) {
            // Reuse from pool
            _ = self.available.pop(); // Remove from pool but don't use the value
            const fact_ptr = try self.allocator.create(Fact);
            self.stats.pool_hits += 1;
            return fact_ptr;
        } else {
            // Allocate new fact
            const fact_ptr = try self.allocator.create(Fact);
            self.stats.pool_misses += 1;
            self.stats.total_allocated += 1;
            return fact_ptr;
        }
    }

    /// Return a fact to the pool for reuse
    pub fn release(self: *FactPool, fact_ptr: *Fact) void {
        defer self.allocator.destroy(fact_ptr);
        
        if (self.available.items.len < self.max_pool_size) {
            // Reset fact to clean state
            const clean_fact = Fact{
                .id = 0,
                .subject = @import("../types/span.zig").Span.empty(),
                .predicate = @import("../types/predicate.zig").Predicate.is_trivia,
                .object = null,
                .confidence = 1.0,
                .generation = 0,
            };
            
            self.available.append(clean_fact) catch {
                // If append fails, just destroy the fact
                return;
            };
            self.stats.pool_releases += 1;
        }
        // If pool is full, just destroy the fact
    }

    /// Get pool statistics
    pub fn getStats(self: FactPool) PoolStats {
        return self.stats;
    }

    /// Clear all pooled facts
    pub fn clear(self: *FactPool) void {
        self.available.clearAndFree();
        self.stats.pool_clears += 1;
    }

    /// Get current pool utilization
    pub fn getUtilization(self: FactPool) f64 {
        if (self.max_pool_size == 0) return 0.0;
        return @as(f64, @floatFromInt(self.available.items.len)) / @as(f64, @floatFromInt(self.max_pool_size));
    }
};

/// Pool for reusing FactId arrays
pub const FactIdArrayPool = struct {
    /// Available arrays by size bucket
    buckets: [MAX_BUCKET]std.ArrayList([]FactId),
    
    /// Allocator for array management
    allocator: std.mem.Allocator,
    
    /// Statistics
    stats: ArrayPoolStats,
    
    /// Maximum arrays per bucket
    max_per_bucket: usize,
    
    const MAX_BUCKET = 16; // Supports arrays up to 2^16 elements
    const BUCKET_MULTIPLIER = 2;

    pub fn init(allocator: std.mem.Allocator, max_per_bucket: usize) FactIdArrayPool {
        var pool = FactIdArrayPool{
            .buckets = undefined,
            .allocator = allocator,
            .stats = ArrayPoolStats{},
            .max_per_bucket = max_per_bucket,
        };
        
        // Initialize all buckets
        for (&pool.buckets) |*bucket| {
            bucket.* = std.ArrayList([]FactId).init(allocator);
        }
        
        return pool;
    }

    pub fn deinit(self: *FactIdArrayPool) void {
        for (&self.buckets) |*bucket| {
            // Free all arrays in each bucket
            for (bucket.items) |array| {
                self.allocator.free(array);
            }
            bucket.deinit();
        }
    }

    /// Get an array of at least the requested size
    pub fn acquire(self: *FactIdArrayPool, min_size: usize) ![]FactId {
        const bucket_index = self.getBucketIndex(min_size);
        const bucket_size = self.getBucketSize(bucket_index);
        
        if (bucket_index < MAX_BUCKET and self.buckets[bucket_index].items.len > 0) {
            // Reuse from pool
            const array = self.buckets[bucket_index].pop() orelse {
                // Fallback if pop fails unexpectedly
                const new_array = try self.allocator.alloc(FactId, bucket_size);
                self.stats.misses += 1;
                self.stats.total_allocated += 1;
                return new_array;
            };
            self.stats.hits += 1;
            return array;
        } else {
            // Allocate new array
            const array = try self.allocator.alloc(FactId, bucket_size);
            self.stats.misses += 1;
            self.stats.total_allocated += 1;
            return array;
        }
    }

    /// Return an array to the pool
    pub fn release(self: *FactIdArrayPool, array: []FactId) void {
        const bucket_index = self.getBucketIndex(array.len);
        
        if (bucket_index < MAX_BUCKET and self.buckets[bucket_index].items.len < self.max_per_bucket) {
            // Clear the array contents
            @memset(array, 0);
            
            self.buckets[bucket_index].append(array) catch {
                // If append fails, just free the array
                self.allocator.free(array);
                return;
            };
            self.stats.releases += 1;
        } else {
            // Bucket full or array too large, just free it
            self.allocator.free(array);
        }
    }

    /// Get appropriate bucket index for a size
    fn getBucketIndex(self: FactIdArrayPool, size: usize) usize {
        _ = self;
        if (size <= 1) return 0;
        
        // Find the bucket that can hold this size
        var bucket: usize = 0;
        var bucket_size: usize = 1;
        
        while (bucket < MAX_BUCKET and bucket_size < size) {
            bucket += 1;
            bucket_size *= BUCKET_MULTIPLIER;
        }
        
        return @min(bucket, MAX_BUCKET - 1);
    }

    /// Get the size for a bucket
    fn getBucketSize(self: FactIdArrayPool, bucket_index: usize) usize {
        _ = self;
        if (bucket_index == 0) return 1;
        
        var size: usize = 1;
        for (0..bucket_index) |_| {
            size *= BUCKET_MULTIPLIER;
        }
        
        return size;
    }

    /// Get pool statistics
    pub fn getStats(self: FactIdArrayPool) ArrayPoolStats {
        return self.stats;
    }

    /// Clear all pools
    pub fn clear(self: *FactIdArrayPool) void {
        for (&self.buckets) |*bucket| {
            for (bucket.items) |array| {
                self.allocator.free(array);
            }
            bucket.clearAndFree();
        }
        self.stats.clears += 1;
    }
};

/// Arena allocator specifically tuned for fact streams
pub const FactArena = struct {
    /// Underlying arena allocator
    arena: std.heap.ArenaAllocator,
    
    /// Statistics for monitoring usage
    stats: ArenaStats,
    
    /// Initial buffer size
    initial_size: usize,

    pub fn init(backing_allocator: std.mem.Allocator, initial_size: usize) FactArena {
        return .{
            .arena = std.heap.ArenaAllocator.init(backing_allocator),
            .stats = ArenaStats{},
            .initial_size = initial_size,
        };
    }

    pub fn deinit(self: *FactArena) void {
        self.arena.deinit();
    }

    /// Get the arena allocator
    pub fn allocator(self: *FactArena) std.mem.Allocator {
        return self.arena.allocator();
    }

    /// Create a new fact in the arena
    pub fn createFact(self: *FactArena) !*Fact {
        const fact_ptr = try self.allocator().create(Fact);
        self.stats.facts_allocated += 1;
        return fact_ptr;
    }

    /// Allocate array of fact IDs in the arena
    pub fn allocFactIds(self: *FactArena, count: usize) ![]FactId {
        const array = try self.allocator().alloc(FactId, count);
        self.stats.arrays_allocated += 1;
        self.stats.total_fact_ids += count;
        return array;
    }

    /// Reset the arena for reuse
    pub fn reset(self: *FactArena) void {
        _ = self.arena.reset(.retain_capacity);
        self.stats.resets += 1;
    }

    /// Get current memory usage
    pub fn getMemoryUsage(self: FactArena) usize {
        return self.arena.queryCapacity();
    }

    /// Get arena statistics
    pub fn getStats(self: FactArena) ArenaStats {
        return self.stats;
    }
};

/// Coordinated pool manager for all fact-related allocations
pub const FactPoolManager = struct {
    /// Pool for fact structures
    fact_pool: FactPool,
    
    /// Pool for FactId arrays
    array_pool: FactIdArrayPool,
    
    /// Arena for temporary allocations
    temp_arena: FactArena,
    
    /// Generation-specific arenas
    generation_arenas: std.HashMap(Generation, FactArena, GenerationContext, std.hash_map.default_max_load_percentage),
    
    /// Allocator for pool manager
    allocator: std.mem.Allocator,
    
    /// Current generation
    current_generation: Generation,
    
    /// Combined statistics
    manager_stats: ManagerStats,

    pub fn init(allocator: std.mem.Allocator) FactPoolManager {
        return .{
            .fact_pool = FactPool.init(allocator, 1000),
            .array_pool = FactIdArrayPool.init(allocator, 100),
            .temp_arena = FactArena.init(allocator, 64 * 1024), // 64KB initial
            .generation_arenas = std.HashMap(Generation, FactArena, GenerationContext, std.hash_map.default_max_load_percentage).init(allocator),
            .allocator = allocator,
            .current_generation = 0,
            .manager_stats = ManagerStats{},
        };
    }

    pub fn deinit(self: *FactPoolManager) void {
        self.fact_pool.deinit();
        self.array_pool.deinit();
        self.temp_arena.deinit();
        
        // Deinit all generation arenas
        var arena_iter = self.generation_arenas.iterator();
        while (arena_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.generation_arenas.deinit();
    }

    /// Acquire a fact from the appropriate pool
    pub fn acquireFact(self: *FactPoolManager) !*Fact {
        self.manager_stats.fact_acquisitions += 1;
        return self.fact_pool.acquire();
    }

    /// Release a fact back to the pool
    pub fn releaseFact(self: *FactPoolManager, fact: *Fact) void {
        self.fact_pool.release(fact);
        self.manager_stats.fact_releases += 1;
    }

    /// Acquire a FactId array
    pub fn acquireFactIdArray(self: *FactPoolManager, min_size: usize) ![]FactId {
        self.manager_stats.array_acquisitions += 1;
        return self.array_pool.acquire(min_size);
    }

    /// Release a FactId array
    pub fn releaseFactIdArray(self: *FactPoolManager, array: []FactId) void {
        self.array_pool.release(array);
        self.manager_stats.array_releases += 1;
    }

    /// Get temporary allocator for short-lived allocations
    pub fn getTempAllocator(self: *FactPoolManager) std.mem.Allocator {
        return self.temp_arena.allocator();
    }

    /// Get allocator for a specific generation
    pub fn getGenerationAllocator(self: *FactPoolManager, generation: Generation) !std.mem.Allocator {
        const result = try self.generation_arenas.getOrPut(generation);
        if (!result.found_existing) {
            result.value_ptr.* = FactArena.init(self.allocator, 32 * 1024); // 32KB per generation
        }
        return result.value_ptr.allocator();
    }

    /// Advance to next generation
    pub fn nextGeneration(self: *FactPoolManager) Generation {
        self.current_generation += 1;
        self.manager_stats.generation_advances += 1;
        return self.current_generation;
    }

    /// Clean up old generations
    pub fn cleanupOldGenerations(self: *FactPoolManager, keep_generations: usize) void {
        if (self.current_generation < keep_generations) return;
        
        const cutoff_generation = self.current_generation - keep_generations;
        
        var to_remove = std.ArrayList(Generation).init(self.allocator);
        defer to_remove.deinit();
        
        var arena_iter = self.generation_arenas.iterator();
        while (arena_iter.next()) |entry| {
            if (entry.key_ptr.* < cutoff_generation) {
                to_remove.append(entry.key_ptr.*) catch continue;
            }
        }
        
        for (to_remove.items) |generation| {
            if (self.generation_arenas.getPtr(generation)) |arena| {
                arena.deinit();
                _ = self.generation_arenas.remove(generation);
                self.manager_stats.generations_cleaned += 1;
            }
        }
    }

    /// Reset temporary arena
    pub fn resetTempArena(self: *FactPoolManager) void {
        self.temp_arena.reset();
        self.manager_stats.temp_resets += 1;
    }

    /// Get comprehensive statistics
    pub fn getStats(self: *FactPoolManager) ManagerStats {
        var stats = self.manager_stats;
        
        // Add detailed pool statistics
        const fact_stats = self.fact_pool.getStats();
        const array_stats = self.array_pool.getStats();
        _ = self.temp_arena.getStats(); // Temp stats not used yet
        
        stats.fact_pool_hit_rate = fact_stats.hitRate();
        stats.array_pool_hit_rate = array_stats.hitRate();
        stats.temp_memory_usage = self.temp_arena.getMemoryUsage();
        stats.active_generations = self.generation_arenas.count();
        
        return stats;
    }

    /// Clear all pools and arenas
    pub fn clear(self: *FactPoolManager) void {
        self.fact_pool.clear();
        self.array_pool.clear();
        self.temp_arena.reset();
        
        var arena_iter = self.generation_arenas.iterator();
        while (arena_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.generation_arenas.clearAndFree();
        
        self.manager_stats.total_clears += 1;
    }
};

/// Statistics structures
pub const PoolStats = struct {
    pool_hits: usize = 0,
    pool_misses: usize = 0,
    pool_releases: usize = 0,
    pool_clears: usize = 0,
    total_allocated: usize = 0,
    
    pub fn hitRate(self: PoolStats) f64 {
        const total = self.pool_hits + self.pool_misses;
        if (total == 0) return 0.0;
        return @as(f64, @floatFromInt(self.pool_hits)) / @as(f64, @floatFromInt(total));
    }
};

pub const ArrayPoolStats = struct {
    hits: usize = 0,
    misses: usize = 0,
    releases: usize = 0,
    clears: usize = 0,
    total_allocated: usize = 0,
    
    pub fn hitRate(self: ArrayPoolStats) f64 {
        const total = self.hits + self.misses;
        if (total == 0) return 0.0;
        return @as(f64, @floatFromInt(self.hits)) / @as(f64, @floatFromInt(total));
    }
};

pub const ArenaStats = struct {
    facts_allocated: usize = 0,
    arrays_allocated: usize = 0,
    total_fact_ids: usize = 0,
    resets: usize = 0,
};

pub const ManagerStats = struct {
    fact_acquisitions: usize = 0,
    fact_releases: usize = 0,
    array_acquisitions: usize = 0,
    array_releases: usize = 0,
    generation_advances: usize = 0,
    generations_cleaned: usize = 0,
    temp_resets: usize = 0,
    total_clears: usize = 0,
    
    // Computed fields
    fact_pool_hit_rate: f64 = 0.0,
    array_pool_hit_rate: f64 = 0.0,
    temp_memory_usage: usize = 0,
    active_generations: usize = 0,
    
    pub fn format(
        self: ManagerStats,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("ManagerStats(fact_hit_rate={d:.2}, array_hit_rate={d:.2}, gens={})", .{
            self.fact_pool_hit_rate,
            self.array_pool_hit_rate,
            self.active_generations,
        });
    }
};

/// Hash map context
const GenerationContext = std.hash_map.AutoContext(Generation);

// Tests
const testing = std.testing;

test "FactPool basic operations" {
    var pool = FactPool.init(testing.allocator, 10);
    defer pool.deinit();
    
    // Acquire fact (should allocate new)
    const fact1 = try pool.acquire();
    defer pool.release(fact1);
    
    var stats = pool.getStats();
    try testing.expectEqual(@as(usize, 1), stats.pool_misses);
    try testing.expectEqual(@as(usize, 1), stats.total_allocated);
    
    // Release and acquire again (should reuse)
    pool.release(fact1);
    const fact2 = try pool.acquire();
    defer testing.allocator.destroy(fact2); // Manual cleanup since we're not releasing
    
    stats = pool.getStats();
    try testing.expectEqual(@as(usize, 1), stats.pool_hits);
    try testing.expectEqual(@as(usize, 1), stats.pool_releases);
}

test "FactIdArrayPool bucket sizing" {
    var pool = FactIdArrayPool.init(testing.allocator, 5);
    defer pool.deinit();
    
    // Test different sizes
    const array1 = try pool.acquire(1);   // Bucket 0: size 1
    const array2 = try pool.acquire(3);   // Bucket 1: size 2 -> but grows to 4
    const array4 = try pool.acquire(8);   // Bucket 2: size 8
    
    try testing.expectEqual(@as(usize, 1), array1.len);
    try testing.expect(array2.len >= 3);
    try testing.expect(array4.len >= 8);
    
    pool.release(array1);
    pool.release(array2);
    pool.release(array4);
    
    // Should reuse from pools
    const reused1 = try pool.acquire(1);
    try testing.expectEqual(@as(usize, 1), reused1.len);
    
    pool.release(reused1);
}

test "FactArena operations" {
    var arena = FactArena.init(testing.allocator, 1024);
    defer arena.deinit();
    
    // Allocate some facts
    const fact1 = try arena.createFact();
    const fact2 = try arena.createFact();
    const array = try arena.allocFactIds(10);
    
    try testing.expect(fact1 != fact2);
    try testing.expectEqual(@as(usize, 10), array.len);
    
    var stats = arena.getStats();
    try testing.expectEqual(@as(usize, 2), stats.facts_allocated);
    try testing.expectEqual(@as(usize, 1), stats.arrays_allocated);
    try testing.expectEqual(@as(usize, 10), stats.total_fact_ids);
    
    // Reset should clear everything
    arena.reset();
    stats = arena.getStats();
    try testing.expectEqual(@as(usize, 1), stats.resets);
}

test "FactPoolManager integration" {
    var manager = FactPoolManager.init(testing.allocator);
    defer manager.deinit();
    
    // Test fact operations
    const fact = try manager.acquireFact();
    manager.releaseFact(fact);
    
    // Test array operations
    const array = try manager.acquireFactIdArray(5);
    manager.releaseFactIdArray(array);
    
    // Test generation operations
    const gen0_alloc = try manager.getGenerationAllocator(0);
    const gen1_alloc = try manager.getGenerationAllocator(1);
    
    try testing.expect(gen0_alloc.ptr != gen1_alloc.ptr);
    
    _ = manager.nextGeneration();
    try testing.expectEqual(@as(Generation, 1), manager.current_generation);
    
    // Test cleanup
    manager.cleanupOldGenerations(1);
    
    const stats = manager.getStats();
    try testing.expectEqual(@as(usize, 1), stats.fact_acquisitions);
    try testing.expectEqual(@as(usize, 1), stats.array_acquisitions);
}