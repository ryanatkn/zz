const std = @import("std");

// Import foundation types
const Span = @import("../foundation/types/span.zig").Span;
const Fact = @import("../foundation/types/fact.zig").Fact;

// Hash context for Span keys
const SpanContext = struct {
    pub fn hash(self: @This(), span: Span) u64 {
        _ = self;
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(std.mem.asBytes(&span.start));
        hasher.update(std.mem.asBytes(&span.end));
        return hasher.final();
    }
    
    pub fn eql(self: @This(), a: Span, b: Span) bool {
        _ = self;
        return a.start == b.start and a.end == b.end;
    }
};

/// LRU cache for parsed boundary results to maximize cache hit rates
/// Target: >95% cache hit rate for repeated boundary parsing
pub const BoundaryCache = struct {
    /// Memory allocator
    allocator: std.mem.Allocator,
    
    /// Maximum number of cached boundaries
    max_capacity: usize,
    
    /// Current cache entries
    entries: std.HashMap(Span, CacheEntry, SpanContext, std.hash_map.default_max_load_percentage),
    
    /// LRU tracking (most recently used at the front)
    lru_list: std.DoublyLinkedList(Span),
    
    /// Node pool for LRU list to avoid allocations
    node_pool: std.ArrayList(*std.DoublyLinkedList(Span).Node),
    
    /// Statistics for monitoring cache performance
    stats: CacheStats,
    
    /// Generation counter for cache invalidation
    generation: u32,
    
    pub fn init(allocator: std.mem.Allocator, max_capacity: usize) !BoundaryCache {
        var cache = BoundaryCache{
            .allocator = allocator,
            .max_capacity = max_capacity,
            .entries = std.HashMap(Span, CacheEntry, SpanContext, 80).init(allocator),
            .lru_list = std.DoublyLinkedList(Span){},
            .node_pool = std.ArrayList(*std.DoublyLinkedList(Span).Node).init(allocator),
            .stats = CacheStats{},
            .generation = 0,
        };
        
        // Pre-allocate nodes for the LRU list
        try cache.node_pool.ensureTotalCapacity(max_capacity);
        for (0..max_capacity) |_| {
            const node = try allocator.create(std.DoublyLinkedList(Span).Node);
            try cache.node_pool.append(node);
        }
        
        return cache;
    }
    
    pub fn deinit(self: *BoundaryCache) void {
        // Clean up all cached facts
        var iterator = self.entries.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.value_ptr.facts);
        }
        self.entries.deinit();
        
        // Clean up node pool
        for (self.node_pool.items) |node| {
            self.allocator.destroy(node);
        }
        self.node_pool.deinit();
    }
    
    /// Get cached facts for a boundary (returns null if not cached)
    pub fn get(self: *BoundaryCache, span: Span) !?[]Fact {
        const start_time = std.time.nanoTimestamp();
        defer {
            const elapsed = std.time.nanoTimestamp() - start_time;
            self.stats.total_lookup_time_ns += @intCast(elapsed);
        }
        
        if (self.entries.getPtr(span)) |entry| {
            // Check if entry is still valid (not invalidated by generation change)
            if (entry.generation == self.generation) {
                // Move to front of LRU list (mark as most recently used)
                self.moveToFront(span);
                
                self.stats.hits += 1;
                
                // Return a copy of the cached facts
                return try self.allocator.dupe(Fact, entry.facts);
            } else {
                // Entry is stale, remove it
                self.removeEntry(span);
                self.stats.misses += 1;
                return null;
            }
        }
        
        self.stats.misses += 1;
        return null;
    }
    
    /// Put new facts in the cache for a boundary
    pub fn put(self: *BoundaryCache, span: Span, facts: []const Fact) !void {
        const start_time = std.time.nanoTimestamp();
        defer {
            const elapsed = std.time.nanoTimestamp() - start_time;
            self.stats.total_insert_time_ns += @intCast(elapsed);
        }
        
        // If already cached, update the entry
        if (self.entries.getPtr(span)) |entry| {
            // Free old facts
            self.allocator.free(entry.facts);
            
            // Store new facts
            entry.facts = try self.allocator.dupe(Fact, facts);
            entry.generation = self.generation;
            entry.size = self.calculateFactsSize(facts);
            entry.timestamp = std.time.timestamp();
            
            // Move to front
            self.moveToFront(span);
            
            self.stats.updates += 1;
            return;
        }
        
        // Check if we need to evict entries to make room
        if (self.entries.count() >= self.max_capacity) {
            try self.evictLRU();
        }
        
        // Create new cache entry
        const cached_facts = try self.allocator.dupe(Fact, facts);
        const entry = CacheEntry{
            .facts = cached_facts,
            .generation = self.generation,
            .size = self.calculateFactsSize(facts),
            .timestamp = std.time.timestamp(),
        };
        
        // Add to cache
        try self.entries.put(span, entry);
        
        // Add to front of LRU list
        try self.addToFront(span);
        
        self.stats.inserts += 1;
        self.stats.current_size += 1;
        self.stats.memory_used += entry.size;
    }
    
    /// Invalidate cache entry for a specific span and return old facts
    pub fn invalidate(self: *BoundaryCache, span: Span) ?[]Fact {
        if (self.entries.get(span)) |entry| {
            const old_facts = entry.facts;
            self.removeEntry(span);
            self.stats.invalidations += 1;
            return old_facts;
        }
        return null;
    }
    
    /// Invalidate all cache entries that overlap with a given span
    pub fn invalidateOverlapping(self: *BoundaryCache, span: Span) !void {
        var to_remove = std.ArrayList(Span).init(self.allocator);
        defer to_remove.deinit();
        
        var iterator = self.entries.iterator();
        while (iterator.next()) |entry| {
            if (entry.key_ptr.overlaps(span)) {
                try to_remove.append(entry.key_ptr.*);
            }
        }
        
        for (to_remove.items) |key| {
            _ = self.invalidate(key);
        }
    }
    
    /// Clear all cache entries
    pub fn clear(self: *BoundaryCache) void {
        // Free all cached facts
        var iterator = self.entries.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.value_ptr.facts);
        }
        
        self.entries.clearRetainingCapacity();
        self.lru_list = std.DoublyLinkedList(Span){};
        
        self.stats.current_size = 0;
        self.stats.memory_used = 0;
        self.stats.clears += 1;
    }
    
    /// Increment generation to invalidate all entries
    pub fn incrementGeneration(self: *BoundaryCache) void {
        self.generation += 1;
        // Entries will be cleaned up lazily on next access
    }
    
    /// Get old facts for a boundary (used for diff generation)
    pub fn getOldFacts(self: *BoundaryCache, span: Span) ?[]Fact {
        if (self.entries.get(span)) |entry| {
            // Return facts even if generation is old (for diffing)
            return entry.facts;
        }
        return null;
    }
    
    // ========================================================================
    // LRU List Management
    // ========================================================================
    
    /// Move an entry to the front of the LRU list
    fn moveToFront(self: *BoundaryCache, span: Span) void {
        // Find the node in the list
        var current = self.lru_list.first;
        while (current) |node| {
            if (std.meta.eql(node.data, span)) {
                // Remove from current position
                self.lru_list.remove(node);
                // Add to front
                self.lru_list.prepend(node);
                return;
            }
            current = node.next;
        }
    }
    
    /// Add a new entry to the front of the LRU list
    fn addToFront(self: *BoundaryCache, span: Span) !void {
        // Get a node from the pool
        if (self.node_pool.items.len > 0) {
            const node = self.node_pool.pop();
            if (node) |n| {
                n.* = .{ .data = span };
                self.lru_list.prepend(n);
            }
        } else {
            // Pool is empty, allocate new node
            const node = try self.allocator.create(std.DoublyLinkedList(Span).Node);
            node.* = .{ .data = span };
            self.lru_list.prepend(node);
        }
    }
    
    /// Remove an entry from the LRU list
    fn removeFromLRU(self: *BoundaryCache, span: Span) void {
        var current = self.lru_list.first;
        while (current) |node| {
            if (std.meta.eql(node.data, span)) {
                self.lru_list.remove(node);
                // Return node to pool
                self.node_pool.append(node) catch {
                    // Pool is full, just free the node
                    self.allocator.destroy(node);
                };
                return;
            }
            current = node.next;
        }
    }
    
    /// Evict the least recently used entry
    fn evictLRU(self: *BoundaryCache) !void {
        if (self.lru_list.last) |lru_node| {
            const span = lru_node.data;
            self.removeEntry(span);
            self.stats.evictions += 1;
        }
    }
    
    /// Remove an entry completely (from both map and LRU list)
    fn removeEntry(self: *BoundaryCache, span: Span) void {
        if (self.entries.fetchRemove(span)) |kv| {
            // Free the cached facts
            self.allocator.free(kv.value.facts);
            
            // Update stats
            self.stats.current_size -= 1;
            self.stats.memory_used -= kv.value.size;
            
            // Remove from LRU list
            self.removeFromLRU(span);
        }
    }
    
    // ========================================================================
    // Helper Methods
    // ========================================================================
    
    /// Calculate memory size of a facts array
    fn calculateFactsSize(self: *BoundaryCache, facts: []const Fact) usize {
        _ = self;
        return facts.len * @sizeOf(Fact);
    }
    
    // ========================================================================
    // Statistics and Performance Monitoring
    // ========================================================================
    
    pub fn getHitRate(self: BoundaryCache) f32 {
        const total_requests = self.stats.hits + self.stats.misses;
        if (total_requests == 0) return 0.0;
        return @as(f32, @floatFromInt(self.stats.hits)) / @as(f32, @floatFromInt(total_requests));
    }
    
    pub fn getStats(self: BoundaryCache) CacheStats {
        return self.stats;
    }
    
    pub fn resetStats(self: *BoundaryCache) void {
        self.stats = CacheStats{
            .current_size = self.stats.current_size,
            .memory_used = self.stats.memory_used,
        };
    }
    
    pub fn wasHit(self: BoundaryCache) bool {
        // Simple way to check if last operation was a hit
        return self.stats.hits > 0;
    }
    
    /// Get cache efficiency metrics
    pub fn getEfficiencyMetrics(self: BoundaryCache) CacheEfficiencyMetrics {
        const total_requests = self.stats.hits + self.stats.misses;
        const avg_lookup_time = if (total_requests > 0)
            @as(f64, @floatFromInt(self.stats.total_lookup_time_ns)) / @as(f64, @floatFromInt(total_requests))
        else
            0.0;
            
        const avg_insert_time = if (self.stats.inserts > 0)
            @as(f64, @floatFromInt(self.stats.total_insert_time_ns)) / @as(f64, @floatFromInt(self.stats.inserts))
        else
            0.0;
        
        return CacheEfficiencyMetrics{
            .hit_rate = self.getHitRate(),
            .memory_efficiency = if (self.max_capacity > 0)
                @as(f32, @floatFromInt(self.stats.current_size)) / @as(f32, @floatFromInt(self.max_capacity))
            else
                0.0,
            .average_lookup_time_ns = avg_lookup_time,
            .average_insert_time_ns = avg_insert_time,
            .eviction_rate = if (total_requests > 0)
                @as(f32, @floatFromInt(self.stats.evictions)) / @as(f32, @floatFromInt(total_requests))
            else
                0.0,
        };
    }
};

/// Cache entry containing parsed facts and metadata
const CacheEntry = struct {
    facts: []Fact,
    generation: u32,
    size: usize,
    timestamp: i64,
};

/// Statistics for monitoring cache performance
pub const CacheStats = struct {
    hits: u64 = 0,
    misses: u64 = 0,
    inserts: u64 = 0,
    updates: u64 = 0,
    evictions: u64 = 0,
    invalidations: u64 = 0,
    clears: u64 = 0,
    current_size: usize = 0,
    memory_used: usize = 0,
    total_lookup_time_ns: u64 = 0,
    total_insert_time_ns: u64 = 0,
    
    pub fn format(
        self: CacheStats,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        
        const total_requests = self.hits + self.misses;
        const hit_rate = if (total_requests > 0)
            @as(f32, @floatFromInt(self.hits)) / @as(f32, @floatFromInt(total_requests)) * 100.0
        else
            0.0;
            
        try writer.print("CacheStats{{ hit_rate: {d:.1}%, size: {}/{}, memory: {}KB, evictions: {} }}", .{
            hit_rate,
            self.current_size,
            self.current_size + self.evictions, // Approximate max size
            self.memory_used / 1024,
            self.evictions,
        });
    }
};

/// Efficiency metrics for cache performance analysis
pub const CacheEfficiencyMetrics = struct {
    hit_rate: f32,
    memory_efficiency: f32,
    average_lookup_time_ns: f64,
    average_insert_time_ns: f64,
    eviction_rate: f32,
    
    pub fn format(
        self: CacheEfficiencyMetrics,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        
        try writer.print("CacheEfficiency{{ hit_rate: {d:.1}%, memory: {d:.1}%, lookup: {d:.1}ns, insert: {d:.1}ns, eviction: {d:.1}% }}", .{
            self.hit_rate * 100.0,
            self.memory_efficiency * 100.0,
            self.average_lookup_time_ns,
            self.average_insert_time_ns,
            self.eviction_rate * 100.0,
        });
    }
};

// ============================================================================
// Testing Utilities
// ============================================================================

pub const TestHelpers = struct {
    /// Create a mock cache for testing
    pub fn createMockCache(allocator: std.mem.Allocator) !BoundaryCache {
        return BoundaryCache.init(allocator, 10); // Small cache for testing
    }
    
    /// Create mock facts for testing
    pub fn createMockFacts(allocator: std.mem.Allocator, count: usize) ![]Fact {
        var facts = std.ArrayList(Fact).init(allocator);
        errdefer facts.deinit();
        
        for (0..count) |i| {
            try facts.append(Fact{
                .id = @as(u32, @intCast(i + 1)),
                .subject = Span.init(i * 10, (i + 1) * 10),
                .predicate = .is_function,
                .object = .{ .string = "mock_function" },
                .confidence = 1.0,
                .generation = 0,
            });
        }
        
        return facts.toOwnedSlice();
    }
    
    /// Verify cache performance meets targets
    pub fn verifyCacheTargets(cache: BoundaryCache) !void {
        const metrics = cache.getEfficiencyMetrics();
        
        // Target: >95% hit rate
        if (metrics.hit_rate < 0.95) {
            std.log.warn("Cache hit rate too low: {d:.1}% < 95% target", .{metrics.hit_rate * 100.0});
            return error.CacheHitRateTarget;
        }
        
        // Target: <1000ns average lookup time
        if (metrics.average_lookup_time_ns > 1000.0) {
            std.log.warn("Cache lookup too slow: {d:.1}ns > 1000ns target", .{metrics.average_lookup_time_ns});
            return error.CacheLookupTarget;
        }
        
        // Target: <10% eviction rate
        if (metrics.eviction_rate > 0.1) {
            std.log.warn("Cache eviction rate too high: {d:.1}% > 10% target", .{metrics.eviction_rate * 100.0});
            return error.CacheEvictionTarget;
        }
    }
};