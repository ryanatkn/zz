/// FactCache - High-performance cache for facts with multi-indexing
///
/// Replaces BoundaryCache with a more general fact caching system.
/// Uses multiple indices for fast lookups by span, predicate, or ID.
///
/// TODO: SIMD-accelerated fact lookups using @Vector
/// TODO: Compressed fact storage using delta encoding
/// TODO: Incremental updates with edit tracking
/// TODO: Parallel cache construction for large files
/// TODO: Cache warming strategies for common queries
const std = @import("std");
const Fact = @import("../fact/mod.zig").Fact;
const FactId = @import("../fact/mod.zig").FactId;
const FactStore = @import("../fact/mod.zig").FactStore;
const Predicate = @import("../fact/mod.zig").Predicate;
const PackedSpan = @import("../span/mod.zig").PackedSpan;
const Span = @import("../span/mod.zig").Span;
const unpackSpan = @import("../span/mod.zig").unpackSpan;
const LruList = @import("lru.zig").LruList;

/// Cache statistics for monitoring performance
pub const CacheStats = struct {
    hits: u64 = 0,
    misses: u64 = 0,
    evictions: u64 = 0,
    insertions: u64 = 0,
    size_bytes: usize = 0,
    fact_count: usize = 0,
    generation: u32 = 0,

    /// Calculate cache hit rate
    pub fn hitRate(self: CacheStats) f32 {
        const total = self.hits + self.misses;
        if (total == 0) return 0.0;
        return @as(f32, @floatFromInt(self.hits)) / @as(f32, @floatFromInt(total));
    }

    /// Calculate average facts per cache entry
    pub fn avgFactsPerEntry(self: CacheStats) f32 {
        if (self.insertions == 0) return 0.0;
        return @as(f32, @floatFromInt(self.fact_count)) / @as(f32, @floatFromInt(self.insertions));
    }
};

/// Hash context for PackedSpan keys
const SpanContext = struct {
    pub fn hash(self: @This(), span: PackedSpan) u64 {
        _ = self;
        // TODO: Use faster hash like xxhash or wyhash
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(std.mem.asBytes(&span));
        return hasher.final();
    }

    pub fn eql(self: @This(), a: PackedSpan, b: PackedSpan) bool {
        _ = self;
        return a == b;
    }
};

/// Cache entry containing facts for a span
const CacheEntry = struct {
    facts: []Fact,
    generation: u32,
    access_count: u32 = 0,
    last_access: i64 = 0,

    // TODO: Add bloom filter for quick existence checks
    // bloom: BloomFilter,
};

/// High-performance fact cache with multi-indexing
pub const FactCache = struct {
    allocator: std.mem.Allocator,

    /// Primary storage for facts
    store: FactStore,

    /// Index by span for spatial queries
    by_span: std.HashMap(PackedSpan, []FactId, SpanContext, 80),

    /// Index by predicate for type queries
    /// TODO: Use EnumMap for better performance
    by_predicate: std.AutoHashMap(Predicate, []FactId),

    /// Index by confidence for quality filtering
    /// TODO: Implement confidence buckets
    // by_confidence: [10][]FactId, // 0.0-0.1, 0.1-0.2, etc.

    /// LRU tracking for eviction
    lru: LruList,

    /// Maximum cache size in bytes
    max_size: usize,

    /// Current size in bytes
    current_size: usize = 0,

    /// Cache generation for invalidation
    generation: u32 = 0,

    /// Statistics for monitoring
    stats: CacheStats = .{},

    /// Initialize a new fact cache
    pub fn init(allocator: std.mem.Allocator, max_size: usize) !FactCache {
        return .{
            .allocator = allocator,
            .store = FactStore.init(allocator),
            .by_span = std.HashMap(PackedSpan, []FactId, SpanContext, 80).init(allocator),
            .by_predicate = std.AutoHashMap(Predicate, []FactId).init(allocator),
            .lru = try LruList.init(allocator, @divTrunc(max_size, @sizeOf(Fact))),
            .max_size = max_size,
        };
    }

    /// Clean up all resources
    pub fn deinit(self: *FactCache) void {
        // Free index arrays
        var span_iter = self.by_span.iterator();
        while (span_iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.by_span.deinit();

        var pred_iter = self.by_predicate.iterator();
        while (pred_iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.by_predicate.deinit();

        self.store.deinit();
        self.lru.deinit();
    }

    /// Get facts for a span
    pub fn get(self: *FactCache, span: PackedSpan) ?[]Fact {
        if (self.by_span.get(span)) |fact_ids| {
            self.stats.hits += 1;

            // Update LRU
            self.lru.touch(span);

            // TODO: This is inefficient - consider storing facts directly
            var facts = self.allocator.alloc(Fact, fact_ids.len) catch return null;
            for (fact_ids, 0..) |id, i| {
                facts[i] = self.store.get(id) orelse continue;
            }

            return facts;
        }

        self.stats.misses += 1;
        return null;
    }

    /// Put facts for a span
    pub fn put(self: *FactCache, span: PackedSpan, facts: []const Fact) !void {
        // Check if we need to evict
        const new_size = facts.len * @sizeOf(Fact);
        if (self.current_size + new_size > self.max_size) {
            try self.evict(new_size);
        }

        // Store facts
        var fact_ids = try self.allocator.alloc(FactId, facts.len);
        errdefer self.allocator.free(fact_ids);

        for (facts, 0..) |fact, i| {
            const id = try self.store.append(fact);
            fact_ids[i] = id;

            // Update predicate index
            try self.updatePredicateIndex(fact.predicate, id);
        }

        // Update span index
        try self.by_span.put(span, fact_ids);

        // Update LRU
        try self.lru.add(span);

        // Update stats
        self.current_size += new_size;
        self.stats.insertions += 1;
        self.stats.fact_count += facts.len;
        self.stats.size_bytes = self.current_size;
    }

    /// Query facts by predicate
    pub fn getByPredicate(self: *FactCache, predicate: Predicate) ?[]Fact {
        if (self.by_predicate.get(predicate)) |fact_ids| {
            self.stats.hits += 1;

            var facts = self.allocator.alloc(Fact, fact_ids.len) catch return null;
            for (fact_ids, 0..) |id, i| {
                facts[i] = self.store.get(id) orelse continue;
            }

            return facts;
        }

        self.stats.misses += 1;
        return null;
    }

    /// Invalidate facts for a span
    pub fn invalidate(self: *FactCache, span: PackedSpan) void {
        if (self.by_span.fetchRemove(span)) |entry| {
            self.allocator.free(entry.value);
            self.lru.remove(span);

            // TODO: Update predicate index
            // This requires tracking which facts belong to which spans
        }
    }

    /// Clear the entire cache
    pub fn clear(self: *FactCache) void {
        // Free all index arrays
        var span_iter = self.by_span.iterator();
        while (span_iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.by_span.clearRetainingCapacity();

        var pred_iter = self.by_predicate.iterator();
        while (pred_iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.by_predicate.clearRetainingCapacity();

        self.store.clear();
        self.lru.clear();
        self.current_size = 0;
        self.generation += 1;
        self.stats.generation = self.generation;
    }

    /// Get cache statistics
    pub fn getStats(self: *const FactCache) CacheStats {
        return self.stats;
    }

    /// Evict entries to make room
    fn evict(self: *FactCache, needed_size: usize) !void {
        var freed: usize = 0;

        while (freed < needed_size) {
            const victim = self.lru.evict() orelse break;

            if (self.by_span.fetchRemove(victim)) |entry| {
                freed += entry.value.len * @sizeOf(Fact);
                self.allocator.free(entry.value);
                self.stats.evictions += 1;
            }
        }

        self.current_size -= freed;
    }

    /// Update predicate index
    fn updatePredicateIndex(self: *FactCache, predicate: Predicate, fact_id: FactId) !void {
        const result = try self.by_predicate.getOrPut(predicate);
        if (!result.found_existing) {
            result.value_ptr.* = try self.allocator.alloc(FactId, 1);
            result.value_ptr.*[0] = fact_id;
        } else {
            // TODO: This is inefficient - use ArrayList instead
            const old = result.value_ptr.*;
            const new = try self.allocator.alloc(FactId, old.len + 1);
            @memcpy(new[0..old.len], old);
            new[old.len] = fact_id;
            self.allocator.free(old);
            result.value_ptr.* = new;
        }
    }

    /// Prefetch facts for a span range
    /// TODO: Implement prefetching for better performance
    pub fn prefetch(self: *FactCache, start: PackedSpan, end: PackedSpan) void {
        _ = self;
        _ = start;
        _ = end;
        // TODO: Implement range prefetching
        // TODO: Use @prefetch intrinsic for cache warming
    }

    /// Compact the cache to reduce memory usage
    /// TODO: Implement compaction
    pub fn compact(self: *FactCache) !void {
        _ = self;
        // TODO: Remove duplicate facts
        // TODO: Merge overlapping spans
        // TODO: Rebuild indices for better locality
    }
};

test "FactCache basic operations" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const Builder = @import("../fact/mod.zig").Builder;

    var cache = try FactCache.init(allocator, 1024 * 1024); // 1MB cache
    defer cache.deinit();

    // Create some facts
    const span1 = @as(PackedSpan, 0x0000000100000010); // Start: 1, length: 16
    const span2 = @as(PackedSpan, 0x0000001000000020); // Start: 16, length: 32

    var facts1 = [_]Fact{
        try Builder.new()
            .withSubject(span1)
            .withPredicate(.is_string)
            .withConfidence(0.9)
            .build(),
        try Builder.new()
            .withSubject(span1)
            .withPredicate(.has_text)
            .withAtom(42)
            .build(),
    };

    // Put facts in cache
    try cache.put(span1, &facts1);

    // Get facts back
    const retrieved = cache.get(span1);
    try testing.expect(retrieved != null);
    try testing.expectEqual(@as(usize, 2), retrieved.?.len);
    defer allocator.free(retrieved.?);

    // Check stats
    const stats = cache.getStats();
    try testing.expectEqual(@as(u64, 1), stats.hits);
    try testing.expectEqual(@as(u64, 0), stats.misses);
    try testing.expectEqual(@as(u64, 1), stats.insertions);

    // Test miss
    const missing = cache.get(span2);
    try testing.expect(missing == null);
    try testing.expectEqual(@as(u64, 1), cache.stats.misses);

    // Test by predicate
    const by_pred = cache.getByPredicate(.is_string);
    try testing.expect(by_pred != null);
    try testing.expectEqual(@as(usize, 1), by_pred.?.len);
    defer allocator.free(by_pred.?);

    // Test invalidation
    cache.invalidate(span1);
    const after_invalidate = cache.get(span1);
    try testing.expect(after_invalidate == null);

    // TODO: Test eviction
    // TODO: Test compaction
    // TODO: Test prefetching
}
