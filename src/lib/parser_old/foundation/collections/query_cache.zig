const std = @import("std");
const Fact = @import("../types/fact.zig").Fact;
const FactId = @import("../types/fact.zig").FactId;
const Generation = @import("../types/fact.zig").Generation;
const Span = @import("../types/span.zig").Span;
const Predicate = @import("../types/predicate.zig").Predicate;
const PredicateCategory = @import("../types/predicate.zig").PredicateCategory;

/// Unique identifier for cached queries
pub const QueryId = u64;

/// Query specification for cache lookups
pub const Query = union(enum) {
    /// Find facts overlapping with a span
    overlapping_span: Span,

    /// Find facts by predicate category
    by_category: PredicateCategory,

    /// Find facts by generation
    by_generation: Generation,

    /// Find facts by exact predicate
    by_predicate: Predicate,

    /// Find facts containing a specific position
    containing_position: usize,

    /// Complex query combining multiple criteria
    complex: ComplexQuery,

    /// Calculate hash for this query for use as cache key
    pub fn hash(self: Query) QueryId {
        var hasher = std.hash.Wyhash.init(0);

        // Hash the query type
        hasher.update(std.mem.asBytes(&@intFromEnum(self)));

        switch (self) {
            .overlapping_span => |span| {
                hasher.update(std.mem.asBytes(&span.start));
                hasher.update(std.mem.asBytes(&span.end));
            },
            .by_category => |category| {
                hasher.update(std.mem.asBytes(&@intFromEnum(category)));
            },
            .by_generation => |generation| {
                hasher.update(std.mem.asBytes(&generation));
            },
            .by_predicate => |predicate| {
                hasher.update(std.mem.asBytes(&@intFromEnum(predicate)));
            },
            .containing_position => |position| {
                hasher.update(std.mem.asBytes(&position));
            },
            .complex => |complex| {
                hasher.update(std.mem.asBytes(&complex.hash()));
            },
        }

        return hasher.final();
    }

    /// Get the spans that would invalidate this query
    pub fn getInvalidationSpans(self: Query, allocator: std.mem.Allocator) ![]Span {
        switch (self) {
            .overlapping_span => |span| {
                const spans = try allocator.alloc(Span, 1);
                spans[0] = span;
                return spans;
            },
            .containing_position => |pos| {
                const spans = try allocator.alloc(Span, 1);
                spans[0] = Span.point(pos);
                return spans;
            },
            .complex => |complex| {
                return complex.getInvalidationSpans(allocator);
            },
            else => {
                // Category and generation queries are not span-specific
                return allocator.alloc(Span, 0);
            },
        }
    }

    pub fn format(
        self: Query,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        switch (self) {
            .overlapping_span => |span| try writer.print("OverlappingSpan({})", .{span}),
            .by_category => |cat| try writer.print("ByCategory({})", .{cat}),
            .by_generation => |gen| try writer.print("ByGeneration({})", .{gen}),
            .by_predicate => |pred| try writer.print("ByPredicate({})", .{pred}),
            .containing_position => |pos| try writer.print("ContainingPosition({})", .{pos}),
            .complex => |complex| try writer.print("Complex({})", .{complex}),
        }
    }
};

/// Complex query with multiple criteria
pub const ComplexQuery = struct {
    /// Optional span constraint
    span: ?Span = null,

    /// Optional category constraint
    category: ?PredicateCategory = null,

    /// Optional generation constraint
    generation: ?Generation = null,

    /// Minimum confidence level
    min_confidence: f32 = 0.0,

    /// Whether to include speculative facts
    include_speculative: bool = true,

    pub fn hash(self: ComplexQuery) u64 {
        var hasher = std.hash.Wyhash.init(0);

        if (self.span) |span| {
            hasher.update(std.mem.asBytes(&span.start));
            hasher.update(std.mem.asBytes(&span.end));
        }

        if (self.category) |category| {
            hasher.update(std.mem.asBytes(&@intFromEnum(category)));
        }

        if (self.generation) |generation| {
            hasher.update(std.mem.asBytes(&generation));
        }

        hasher.update(std.mem.asBytes(&self.min_confidence));
        hasher.update(std.mem.asBytes(&self.include_speculative));

        return hasher.final();
    }

    pub fn getInvalidationSpans(self: ComplexQuery, allocator: std.mem.Allocator) ![]Span {
        if (self.span) |span| {
            const spans = try allocator.alloc(Span, 1);
            spans[0] = span;
            return spans;
        }
        return allocator.alloc(Span, 0);
    }

    pub fn format(
        self: ComplexQuery,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("ComplexQuery(hash={})", .{self.hash()});
    }
};

/// Cached query result
pub const CacheEntry = struct {
    /// The original query
    query: Query,

    /// Cached result fact IDs
    result: []FactId,

    /// Generation when this result was cached
    cached_generation: Generation,

    /// Last access time for LRU eviction (nanoseconds)
    last_access: i128,

    /// Spans that would invalidate this cache entry
    invalidation_spans: []Span,

    /// Number of times this entry has been accessed
    access_count: usize,

    /// Allocator used for result and spans
    allocator: std.mem.Allocator,

    pub fn init(
        allocator: std.mem.Allocator,
        query: Query,
        result: []FactId,
        generation: Generation,
    ) !CacheEntry {
        const result_copy = try allocator.dupe(FactId, result);
        const invalidation_spans = try query.getInvalidationSpans(allocator);

        return CacheEntry{
            .query = query,
            .result = result_copy,
            .cached_generation = generation,
            .last_access = std.time.nanoTimestamp(),
            .invalidation_spans = invalidation_spans,
            .access_count = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CacheEntry) void {
        self.allocator.free(self.result);
        self.allocator.free(self.invalidation_spans);
    }

    /// Check if this cache entry is still valid for the given generation
    pub fn isValid(self: *CacheEntry, current_generation: Generation) bool {
        return self.cached_generation >= current_generation;
    }

    /// Update access time and count for LRU
    pub fn markAccessed(self: *CacheEntry) void {
        self.last_access = std.time.nanoTimestamp();
        self.access_count += 1;
    }

    /// Check if this entry is invalidated by changes to a span
    pub fn isInvalidatedBy(self: CacheEntry, changed_span: Span) bool {
        for (self.invalidation_spans) |span| {
            if (span.overlaps(changed_span)) {
                return true;
            }
        }
        return false;
    }

    /// Get age in seconds
    pub fn getAge(self: CacheEntry) i64 {
        const current_ns = std.time.nanoTimestamp();
        const age_ns = current_ns - self.last_access;
        const age_seconds = @divFloor(age_ns, std.time.ns_per_s);
        return @intCast(age_seconds); // Safe cast since age won't exceed i64 range
    }
};

/// High-performance query cache with generation-based invalidation
pub const QueryCache = struct {
    /// Main cache storage
    entries: std.HashMap(QueryId, CacheEntry, QueryIdContext, std.hash_map.default_max_load_percentage),

    /// Spatial index for span-based invalidation
    invalidation_map: std.HashMap(Span, QueryIdList, SpanContext, std.hash_map.default_max_load_percentage),

    /// Current generation for cache validity
    current_generation: Generation,

    /// Maximum number of entries before eviction
    max_entries: usize,

    /// Maximum age in seconds before eviction
    max_age_seconds: i64,

    /// Memory allocator
    allocator: std.mem.Allocator,

    /// Cache statistics
    stats: CacheStats,

    pub fn init(allocator: std.mem.Allocator, max_entries: usize, max_age_seconds: i64) QueryCache {
        return .{
            .entries = std.HashMap(QueryId, CacheEntry, QueryIdContext, std.hash_map.default_max_load_percentage).init(allocator),
            .invalidation_map = std.HashMap(Span, QueryIdList, SpanContext, std.hash_map.default_max_load_percentage).init(allocator),
            .current_generation = 0,
            .max_entries = max_entries,
            .max_age_seconds = max_age_seconds,
            .allocator = allocator,
            .stats = CacheStats{},
        };
    }

    pub fn deinit(self: *QueryCache) void {
        // Free all cache entries
        var entries_iter = self.entries.iterator();
        while (entries_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.entries.deinit();

        // Free all invalidation map lists
        var invalidation_iter = self.invalidation_map.iterator();
        while (invalidation_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.invalidation_map.deinit();
    }

    /// Get cached result for a query
    pub fn get(self: *QueryCache, query: Query) ?[]const FactId {
        const query_id = query.hash();

        if (self.entries.getPtr(query_id)) |entry| {
            // Check if entry is still valid
            if (!entry.isValid(self.current_generation)) {
                self.removeEntry(query_id);
                self.stats.misses += 1;
                return null;
            }

            // Check age-based expiration
            if (entry.getAge() > self.max_age_seconds) {
                self.removeEntry(query_id);
                self.stats.misses += 1;
                self.stats.age_evictions += 1;
                return null;
            }

            // Cache hit
            entry.markAccessed();
            self.stats.hits += 1;
            return entry.result;
        }

        self.stats.misses += 1;
        return null;
    }

    /// Store result for a query
    pub fn put(self: *QueryCache, query: Query, result: []FactId) !void {
        const query_id = query.hash();

        // Remove existing entry if present
        if (self.entries.contains(query_id)) {
            self.removeEntry(query_id);
        }

        // Check if we need to evict entries
        if (self.entries.count() >= self.max_entries) {
            try self.evictLRU();
        }

        // Create new cache entry
        const entry = try CacheEntry.init(self.allocator, query, result, self.current_generation);

        // Add to main cache
        try self.entries.put(query_id, entry);

        // Add to invalidation map
        for (entry.invalidation_spans) |span| {
            const map_result = try self.invalidation_map.getOrPut(span);
            if (!map_result.found_existing) {
                map_result.value_ptr.* = QueryIdList.init(self.allocator);
            }
            try map_result.value_ptr.append(query_id);
        }

        self.stats.entries_added += 1;
    }

    /// Invalidate cache entries affected by changes to a span
    pub fn invalidateSpan(self: *QueryCache, changed_span: Span) void {
        var to_remove = std.ArrayList(QueryId).init(self.allocator);
        defer to_remove.deinit();

        // Find all entries that overlap with the changed span
        var entries_iter = self.entries.iterator();
        while (entries_iter.next()) |entry| {
            if (entry.value_ptr.isInvalidatedBy(changed_span)) {
                to_remove.append(entry.key_ptr.*) catch continue;
            }
        }

        // Remove invalidated entries
        for (to_remove.items) |query_id| {
            self.removeEntry(query_id);
            self.stats.span_invalidations += 1;
        }
    }

    /// Advance to next generation and invalidate old entries
    pub fn nextGeneration(self: *QueryCache) Generation {
        self.current_generation += 1;

        // Remove entries from previous generations
        var to_remove = std.ArrayList(QueryId).init(self.allocator);
        defer to_remove.deinit();

        var entries_iter = self.entries.iterator();
        while (entries_iter.next()) |entry| {
            if (!entry.value_ptr.isValid(self.current_generation)) {
                to_remove.append(entry.key_ptr.*) catch continue;
            }
        }

        for (to_remove.items) |query_id| {
            self.removeEntry(query_id);
            self.stats.generation_invalidations += 1;
        }

        return self.current_generation;
    }

    /// Get current generation
    pub fn getCurrentGeneration(self: QueryCache) Generation {
        return self.current_generation;
    }

    /// Get cache statistics
    pub fn getStats(self: QueryCache) CacheStats {
        return self.stats;
    }

    /// Clear all cache entries
    pub fn clear(self: *QueryCache) void {
        // Free all cache entries
        var entries_iter = self.entries.iterator();
        while (entries_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.entries.clearAndFree();

        // Free all invalidation map lists
        var invalidation_iter = self.invalidation_map.iterator();
        while (invalidation_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.invalidation_map.clearAndFree();

        self.stats = CacheStats{};
    }

    /// Force eviction of least recently used entries
    fn evictLRU(self: *QueryCache) !void {
        if (self.entries.count() == 0) return;

        // Find entry with oldest access time
        var oldest_query_id: QueryId = 0;
        var oldest_time: i128 = std.math.maxInt(i128);

        var entries_iter = self.entries.iterator();
        while (entries_iter.next()) |entry| {
            if (entry.value_ptr.last_access < oldest_time) {
                oldest_time = entry.value_ptr.last_access;
                oldest_query_id = entry.key_ptr.*;
            }
        }

        self.removeEntry(oldest_query_id);
        self.stats.lru_evictions += 1;
    }

    /// Remove a cache entry and update invalidation map
    fn removeEntry(self: *QueryCache, query_id: QueryId) void {
        if (self.entries.getPtr(query_id)) |entry| {
            // Remove from invalidation map
            for (entry.invalidation_spans) |span| {
                if (self.invalidation_map.getPtr(span)) |list| {
                    if (findQueryIdIndex(list, query_id)) |index| {
                        _ = list.swapRemove(index);

                        // Remove empty lists
                        if (list.items.len == 0) {
                            list.deinit();
                            _ = self.invalidation_map.remove(span);
                        }
                    }
                }
            }

            // Free the entry and remove from main cache
            entry.deinit();
            _ = self.entries.remove(query_id);
            self.stats.entries_removed += 1;
        }
    }
};

/// Cache performance statistics
pub const CacheStats = struct {
    hits: usize = 0,
    misses: usize = 0,
    entries_added: usize = 0,
    entries_removed: usize = 0,
    lru_evictions: usize = 0,
    age_evictions: usize = 0,
    span_invalidations: usize = 0,
    generation_invalidations: usize = 0,

    pub fn hitRate(self: CacheStats) f64 {
        const total = self.hits + self.misses;
        if (total == 0) return 0.0;
        return @as(f64, @floatFromInt(self.hits)) / @as(f64, @floatFromInt(total));
    }

    pub fn format(
        self: CacheStats,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("CacheStats(hit_rate={d:.2}, hits={}, misses={}, evictions={})", .{
            self.hitRate(),
            self.hits,
            self.misses,
            self.lru_evictions + self.age_evictions,
        });
    }
};

/// Type aliases and contexts
const QueryIdList = std.ArrayList(QueryId);
const QueryIdContext = std.hash_map.AutoContext(QueryId);
const SpanContext = std.hash_map.AutoContext(Span);

/// Helper functions
fn findQueryIdIndex(list: *QueryIdList, query_id: QueryId) ?usize {
    for (list.items, 0..) |id, i| {
        if (id == query_id) return i;
    }
    return null;
}

// Tests
const testing = std.testing;

test "Query hashing" {
    const span = Span.init(10, 20);
    const query1 = Query{ .overlapping_span = span };
    const query2 = Query{ .overlapping_span = span };
    const query3 = Query{ .overlapping_span = Span.init(10, 21) };

    // Same queries should have same hash
    try testing.expectEqual(query1.hash(), query2.hash());

    // Different queries should have different hashes (with high probability)
    try testing.expect(query1.hash() != query3.hash());
}

test "CacheEntry lifecycle" {
    const query = Query{ .by_category = .lexical };
    var result = [_]FactId{ 1, 2, 3 };

    var entry = try CacheEntry.init(testing.allocator, query, result[0..], 5);
    defer entry.deinit();

    try testing.expectEqual(@as(Generation, 5), entry.cached_generation);
    try testing.expectEqual(@as(usize, 3), entry.result.len);
    try testing.expectEqual(@as(FactId, 1), entry.result[0]);

    // Test validity
    try testing.expect(entry.isValid(5));
    try testing.expect(entry.isValid(4));
    try testing.expect(!entry.isValid(6));

    // Test access tracking
    const initial_count = entry.access_count;
    entry.markAccessed();
    try testing.expectEqual(initial_count + 1, entry.access_count);
}

test "QueryCache basic operations" {
    var cache = QueryCache.init(testing.allocator, 100, 3600);
    defer cache.deinit();

    const query = Query{ .by_category = .lexical };
    var result = [_]FactId{ 1, 2, 3 };

    // Cache miss initially
    try testing.expectEqual(@as(?[]const FactId, null), cache.get(query));

    // Store result
    try cache.put(query, result[0..]);

    // Cache hit
    const cached = cache.get(query);
    try testing.expect(cached != null);
    try testing.expectEqual(@as(usize, 3), cached.?.len);
    try testing.expectEqual(@as(FactId, 1), cached.?[0]);

    // Check stats
    const stats = cache.getStats();
    try testing.expectEqual(@as(usize, 1), stats.hits);
    try testing.expectEqual(@as(usize, 1), stats.misses);
    try testing.expectEqual(@as(f64, 0.5), stats.hitRate());
}

test "QueryCache generation invalidation" {
    var cache = QueryCache.init(testing.allocator, 100, 3600);
    defer cache.deinit();

    const query = Query{ .by_generation = 0 };
    var result = [_]FactId{ 1, 2 };

    try cache.put(query, result[0..]);

    // Should hit with current generation
    try testing.expect(cache.get(query) != null);

    // Advance generation
    _ = cache.nextGeneration();

    // Should miss after generation advance
    try testing.expectEqual(@as(?[]const FactId, null), cache.get(query));
}

test "QueryCache span invalidation" {
    var cache = QueryCache.init(testing.allocator, 100, 3600);
    defer cache.deinit();

    const span = Span.init(10, 20);
    const query = Query{ .overlapping_span = span };
    var result = [_]FactId{ 1, 2 };

    try cache.put(query, result[0..]);

    // Should hit initially
    try testing.expect(cache.get(query) != null);

    // Invalidate overlapping span
    const changed_span = Span.init(15, 25);
    cache.invalidateSpan(changed_span);

    // Should miss after span invalidation
    try testing.expectEqual(@as(?[]const FactId, null), cache.get(query));
}

test "QueryCache LRU eviction" {
    var cache = QueryCache.init(testing.allocator, 2, 3600); // Small cache
    defer cache.deinit();

    const query1 = Query{ .by_category = .lexical };
    const query2 = Query{ .by_category = .structural };
    const query3 = Query{ .by_category = .syntactic };
    var result = [_]FactId{1};

    // Fill cache to capacity
    try cache.put(query1, result[0..]);
    try cache.put(query2, result[0..]);

    // Access first query to make it more recent
    _ = cache.get(query1);

    // Add third query, should evict query2 (LRU)
    try cache.put(query3, result[0..]);

    // query1 and query3 should be in cache, query2 should be evicted
    try testing.expect(cache.get(query1) != null);
    try testing.expect(cache.get(query2) == null);
    try testing.expect(cache.get(query3) != null);
}

test "QueryCache complex queries" {
    var cache = QueryCache.init(testing.allocator, 100, 3600);
    defer cache.deinit();

    const complex = ComplexQuery{
        .span = Span.init(10, 20),
        .category = .lexical,
        .min_confidence = 0.8,
        .include_speculative = false,
    };

    const query = Query{ .complex = complex };
    var result = [_]FactId{ 1, 2, 3 };

    try cache.put(query, result[0..]);

    const cached = cache.get(query);
    try testing.expect(cached != null);
    try testing.expectEqual(@as(usize, 3), cached.?.len);
}
