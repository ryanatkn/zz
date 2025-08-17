const std = @import("std");

/// Collections module for efficient fact storage and querying
/// 
/// This module provides high-performance data structures optimized for the
/// stratified parser's fact-based intermediate representation, including
/// spatial indexing, caching, and memory pool management.

// ============================================================================
// Core Collections - Primary data structures for fact management
// ============================================================================

/// High-performance fact index with multiple access patterns
pub const FactIndex = @import("fact_index.zig").FactIndex;
pub const IndexStats = @import("fact_index.zig").IndexStats;

/// Query cache with generation-based invalidation
pub const QueryCache = @import("query_cache.zig").QueryCache;
pub const Query = @import("query_cache.zig").Query;
pub const QueryId = @import("query_cache.zig").QueryId;
pub const CacheEntry = @import("query_cache.zig").CacheEntry;
pub const CacheStats = @import("query_cache.zig").CacheStats;
pub const ComplexQuery = @import("query_cache.zig").ComplexQuery;

/// Memory pools for efficient fact allocation
pub const FactPool = @import("pools.zig").FactPool;
pub const FactIdArrayPool = @import("pools.zig").FactIdArrayPool;
pub const FactArena = @import("pools.zig").FactArena;
pub const FactPoolManager = @import("pools.zig").FactPoolManager;

// Pool statistics
pub const PoolStats = @import("pools.zig").PoolStats;
pub const ArrayPoolStats = @import("pools.zig").ArrayPoolStats;
pub const ArenaStats = @import("pools.zig").ArenaStats;
pub const ManagerStats = @import("pools.zig").ManagerStats;

// ============================================================================
// Convenience Functions - Common operations and factory methods
// ============================================================================

/// Create a new fact index with default settings
pub fn createFactIndex(allocator: std.mem.Allocator) FactIndex {
    return FactIndex.init(allocator);
}

/// Create a new query cache with reasonable defaults
pub fn createQueryCache(allocator: std.mem.Allocator) QueryCache {
    return QueryCache.init(allocator, 1000, 3600); // 1000 entries, 1 hour TTL
}

/// Create a new pool manager with default settings
pub fn createPoolManager(allocator: std.mem.Allocator) FactPoolManager {
    return FactPoolManager.init(allocator);
}

/// Create a query for finding facts overlapping a span
pub fn queryOverlappingSpan(span: @import("../types/span.zig").Span) Query {
    return Query{ .overlapping_span = span };
}

/// Create a query for finding facts by category
pub fn queryByCategory(category: @import("../types/predicate.zig").PredicateCategory) Query {
    return Query{ .by_category = category };
}

/// Create a query for finding facts by generation
pub fn queryByGeneration(generation: @import("../types/fact.zig").Generation) Query {
    return Query{ .by_generation = generation };
}

/// Create a query for finding facts containing a position
pub fn queryContainingPosition(position: usize) Query {
    return Query{ .containing_position = position };
}

/// Create a complex query with multiple criteria
pub fn queryComplex(complex: ComplexQuery) Query {
    return Query{ .complex = complex };
}

// ============================================================================
// Collection Management - High-level coordination between components
// ============================================================================

/// Coordinated fact storage system combining index, cache, and pools
pub const FactStorageSystem = struct {
    /// Primary fact index
    index: FactIndex,
    
    /// Query result cache
    cache: QueryCache,
    
    /// Memory pool manager
    pools: FactPoolManager,
    
    /// System allocator
    allocator: std.mem.Allocator,
    
    /// Combined statistics
    stats: SystemStats,

    pub fn init(allocator: std.mem.Allocator) FactStorageSystem {
        return .{
            .index = createFactIndex(allocator),
            .cache = createQueryCache(allocator),
            .pools = createPoolManager(allocator),
            .allocator = allocator,
            .stats = SystemStats{},
        };
    }

    pub fn deinit(self: *FactStorageSystem) void {
        self.index.deinit();
        self.cache.deinit();
        self.pools.deinit();
    }

    /// Insert a fact into the system
    pub fn insertFact(self: *FactStorageSystem, fact: @import("../types/fact.zig").Fact) !void {
        try self.index.insert(fact);
        
        // Invalidate cache entries that might be affected
        self.cache.invalidateSpan(fact.subject);
        
        self.stats.facts_inserted += 1;
    }

    /// Remove a fact from the system
    pub fn removeFact(self: *FactStorageSystem, fact_id: @import("../types/fact.zig").FactId) bool {
        if (self.index.get(fact_id)) |fact| {
            const result = self.index.remove(fact_id);
            if (result) {
                // Invalidate cache entries
                self.cache.invalidateSpan(fact.subject);
                self.stats.facts_removed += 1;
            }
            return result;
        }
        return false;
    }

    /// Query facts with caching
    pub fn queryFacts(self: *FactStorageSystem, query: Query, allocator: std.mem.Allocator) ![]@import("../types/fact.zig").FactId {
        // Check cache first
        if (self.cache.get(query)) |cached_result| {
            self.stats.cache_hits += 1;
            return allocator.dupe(@import("../types/fact.zig").FactId, cached_result);
        }

        // Cache miss - query the index
        self.stats.cache_misses += 1;
        const result = try self.executeQuery(query, allocator);
        
        // Cache the result
        try self.cache.put(query, result);
        
        return result;
    }

    /// Execute a query against the index
    fn executeQuery(self: *FactStorageSystem, query: Query, allocator: std.mem.Allocator) ![]@import("../types/fact.zig").FactId {
        switch (query) {
            .overlapping_span => |span| {
                return self.index.findOverlapping(span, allocator);
            },
            .by_category => |category| {
                const result = self.index.findByCategory(category) orelse return allocator.alloc(@import("../types/fact.zig").FactId, 0);
                return allocator.dupe(@import("../types/fact.zig").FactId, result);
            },
            .by_generation => |generation| {
                const result = self.index.findByGeneration(generation) orelse return allocator.alloc(@import("../types/fact.zig").FactId, 0);
                return allocator.dupe(@import("../types/fact.zig").FactId, result);
            },
            .containing_position => |position| {
                const span = @import("../types/span.zig").Span.point(position);
                return self.index.findOverlapping(span, allocator);
            },
            .by_predicate => |predicate| {
                // Filter by exact predicate
                var result = std.ArrayList(@import("../types/fact.zig").FactId).init(allocator);
                defer result.deinit();
                
                const category = predicate.category();
                const category_facts = self.index.findByCategory(category) orelse return allocator.alloc(@import("../types/fact.zig").FactId, 0);
                
                for (category_facts) |fact_id| {
                    if (self.index.get(fact_id)) |fact| {
                        if (fact.predicate.eql(predicate)) {
                            try result.append(fact_id);
                        }
                    }
                }
                
                return result.toOwnedSlice();
            },
            .complex => |complex| {
                return self.executeComplexQuery(complex, allocator);
            },
        }
    }

    /// Execute a complex query with multiple criteria
    fn executeComplexQuery(self: *FactStorageSystem, complex: ComplexQuery, allocator: std.mem.Allocator) ![]@import("../types/fact.zig").FactId {
        var candidates = std.ArrayList(@import("../types/fact.zig").FactId).init(allocator);
        defer candidates.deinit();
        
        // Start with most restrictive constraint
        if (complex.span) |span| {
            const span_facts = try self.index.findOverlapping(span, allocator);
            defer allocator.free(span_facts);
            try candidates.appendSlice(span_facts);
        } else if (complex.category) |category| {
            const category_facts = self.index.findByCategory(category) orelse return allocator.alloc(@import("../types/fact.zig").FactId, 0);
            try candidates.appendSlice(category_facts);
        } else if (complex.generation) |generation| {
            const generation_facts = self.index.findByGeneration(generation) orelse return allocator.alloc(@import("../types/fact.zig").FactId, 0);
            try candidates.appendSlice(generation_facts);
        } else {
            // No constraints - this would be expensive, return empty
            return allocator.alloc(@import("../types/fact.zig").FactId, 0);
        }
        
        // Apply additional filters
        var result = std.ArrayList(@import("../types/fact.zig").FactId).init(allocator);
        defer result.deinit();
        
        for (candidates.items) |fact_id| {
            const fact = self.index.get(fact_id) orelse continue;
            
            // Check confidence filter
            if (fact.confidence < complex.min_confidence) continue;
            
            // Check speculative filter
            if (!complex.include_speculative and fact.isSpeculative()) continue;
            
            // Check additional constraints
            var matches = true;
            
            if (complex.category) |category| {
                if (fact.category() != category) matches = false;
            }
            
            if (complex.generation) |generation| {
                if (fact.generation != generation) matches = false;
            }
            
            if (complex.span) |span| {
                if (!fact.overlapsSpan(span)) matches = false;
            }
            
            if (matches) {
                try result.append(fact_id);
            }
        }
        
        return result.toOwnedSlice();
    }

    /// Get a fact by ID
    pub fn getFact(self: *FactStorageSystem, fact_id: @import("../types/fact.zig").FactId) ?@import("../types/fact.zig").Fact {
        return self.index.get(fact_id);
    }

    /// Advance to next generation
    pub fn nextGeneration(self: *FactStorageSystem) @import("../types/fact.zig").Generation {
        const generation = self.index.nextGeneration();
        _ = self.cache.nextGeneration();
        _ = self.pools.nextGeneration();
        self.stats.generation_advances += 1;
        return generation;
    }

    /// Get comprehensive system statistics
    pub fn getStats(self: *FactStorageSystem) SystemStats {
        var stats = self.stats;
        
        const index_stats = self.index.getStats();
        const cache_stats = self.cache.getStats();
        const pool_stats = self.pools.getStats();
        
        stats.index_stats = index_stats;
        stats.cache_stats = cache_stats;
        stats.pool_stats = pool_stats;
        
        return stats;
    }

    /// Clear all data structures
    pub fn clear(self: *FactStorageSystem) void {
        self.index.clear();
        self.cache.clear();
        self.pools.clear();
        self.stats = SystemStats{};
    }
};

/// Combined statistics for the entire storage system
pub const SystemStats = struct {
    facts_inserted: usize = 0,
    facts_removed: usize = 0,
    cache_hits: usize = 0,
    cache_misses: usize = 0,
    generation_advances: usize = 0,
    
    // Detailed component statistics
    index_stats: IndexStats = IndexStats{},
    cache_stats: CacheStats = CacheStats{},
    pool_stats: ManagerStats = ManagerStats{},
    
    pub fn cacheHitRate(self: SystemStats) f64 {
        const total = self.cache_hits + self.cache_misses;
        if (total == 0) return 0.0;
        return @as(f64, @floatFromInt(self.cache_hits)) / @as(f64, @floatFromInt(total));
    }
    
    pub fn format(
        self: SystemStats,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("SystemStats(facts={}, cache_hit_rate={d:.2}, gens={})", .{
            self.index_stats.fact_count,
            self.cacheHitRate(),
            self.generation_advances,
        });
    }
};

// ============================================================================
// Utility Functions - Helper functions for common operations
// ============================================================================

/// Create a fact storage system with custom settings
pub fn createStorageSystem(
    allocator: std.mem.Allocator,
    cache_size: usize,
    cache_ttl: i64,
) FactStorageSystem {
    return FactStorageSystem{
        .index = createFactIndex(allocator),
        .cache = QueryCache.init(allocator, cache_size, cache_ttl),
        .pools = createPoolManager(allocator),
        .allocator = allocator,
        .stats = SystemStats{},
    };
}

/// Batch insert facts into a storage system
pub fn batchInsertFacts(
    system: *FactStorageSystem,
    facts: []const @import("../types/fact.zig").Fact,
) !void {
    try system.index.insertBatch(facts);
    
    // Invalidate cache for all affected spans
    for (facts) |fact| {
        system.cache.invalidateSpan(fact.subject);
    }
    
    system.stats.facts_inserted += facts.len;
}

/// Find facts that contain a specific position
pub fn findFactsContaining(
    system: *FactStorageSystem,
    position: usize,
    allocator: std.mem.Allocator,
) ![]@import("../types/fact.zig").FactId {
    const query = queryContainingPosition(position);
    return system.queryFacts(query, allocator);
}

/// Find facts in a span with specific category
pub fn findFactsInSpanByCategory(
    system: *FactStorageSystem,
    span: @import("../types/span.zig").Span,
    category: @import("../types/predicate.zig").PredicateCategory,
    allocator: std.mem.Allocator,
) ![]@import("../types/fact.zig").FactId {
    const complex = ComplexQuery{
        .span = span,
        .category = category,
    };
    const query = queryComplex(complex);
    return system.queryFacts(query, allocator);
}

// ============================================================================
// Module Tests - Integration testing across all collections
// ============================================================================

test "collections module integration" {
    const testing = std.testing;
    
    var system = FactStorageSystem.init(testing.allocator);
    defer system.deinit();
    
    const span = @import("../types/span.zig").Span.init(10, 20);
    const predicate = @import("../types/predicate.zig").Predicate{ .is_token = .identifier };
    const fact = @import("../types/fact.zig").Fact.simple(1, span, predicate, 0);
    
    // Test insertion
    try system.insertFact(fact);
    
    // Test retrieval
    const retrieved = system.getFact(1);
    try testing.expect(retrieved != null);
    try testing.expect(retrieved.?.eql(fact));
    
    // Test querying
    const query = queryOverlappingSpan(span);
    const results = try system.queryFacts(query, testing.allocator);
    defer testing.allocator.free(results);
    
    try testing.expectEqual(@as(usize, 1), results.len);
    try testing.expectEqual(@as(@import("../types/fact.zig").FactId, 1), results[0]);
    
    // Test cache hit on second query
    const results2 = try system.queryFacts(query, testing.allocator);
    defer testing.allocator.free(results2);
    
    const stats = system.getStats();
    try testing.expectEqual(@as(usize, 1), stats.cache_hits);
}

test "complex query execution" {
    const testing = std.testing;
    
    var system = FactStorageSystem.init(testing.allocator);
    defer system.deinit();
    
    const span1 = @import("../types/span.zig").Span.init(10, 20);
    const span2 = @import("../types/span.zig").Span.init(30, 40);
    const predicate = @import("../types/predicate.zig").Predicate{ .is_token = .identifier };
    
    const fact1 = @import("../types/fact.zig").Fact.simple(1, span1, predicate, 0);
    const fact2 = @import("../types/fact.zig").Fact.simple(2, span2, predicate, 1);
    const fact3 = @import("../types/fact.zig").Fact.speculative(3, span1, predicate, 0.5, 0);
    
    try system.insertFact(fact1);
    try system.insertFact(fact2);
    try system.insertFact(fact3);
    
    // Test complex query: facts in span1 with confidence >= 0.8
    const complex = ComplexQuery{
        .span = span1,
        .min_confidence = 0.8,
        .include_speculative = false,
    };
    const query = queryComplex(complex);
    const results = try system.queryFacts(query, testing.allocator);
    defer testing.allocator.free(results);
    
    // Should only find fact1 (high confidence in span1)
    try testing.expectEqual(@as(usize, 1), results.len);
    try testing.expectEqual(@as(@import("../types/fact.zig").FactId, 1), results[0]);
}

test "generation management" {
    const testing = std.testing;
    
    var system = FactStorageSystem.init(testing.allocator);
    defer system.deinit();
    
    const span = @import("../types/span.zig").Span.init(10, 20);
    const predicate = @import("../types/predicate.zig").Predicate{ .is_token = .identifier };
    
    // Insert fact in generation 0
    const fact1 = @import("../types/fact.zig").Fact.simple(1, span, predicate, 0);
    try system.insertFact(fact1);
    
    // Advance to generation 1
    const gen1 = system.nextGeneration();
    try testing.expectEqual(@as(@import("../types/fact.zig").Generation, 1), gen1);
    
    // Insert fact in generation 1
    const fact2 = @import("../types/fact.zig").Fact.simple(2, span, predicate, 1);
    try system.insertFact(fact2);
    
    // Query by generation
    const gen0_query = queryByGeneration(0);
    const gen0_results = try system.queryFacts(gen0_query, testing.allocator);
    defer testing.allocator.free(gen0_results);
    
    const gen1_query = queryByGeneration(1);
    const gen1_results = try system.queryFacts(gen1_query, testing.allocator);
    defer testing.allocator.free(gen1_results);
    
    try testing.expectEqual(@as(usize, 1), gen0_results.len);
    try testing.expectEqual(@as(usize, 1), gen1_results.len);
    try testing.expectEqual(@as(@import("../types/fact.zig").FactId, 1), gen0_results[0]);
    try testing.expectEqual(@as(@import("../types/fact.zig").FactId, 2), gen1_results[0]);
}

test "batch operations" {
    const testing = std.testing;
    
    var system = FactStorageSystem.init(testing.allocator);
    defer system.deinit();
    
    const span = @import("../types/span.zig").Span.init(10, 20);
    const predicate = @import("../types/predicate.zig").Predicate{ .is_token = .identifier };
    
    // Create batch of facts
    var facts: [5]@import("../types/fact.zig").Fact = undefined;
    for (&facts, 0..) |*fact, i| {
        fact.* = @import("../types/fact.zig").Fact.simple(@intCast(i + 1), span, predicate, 0);
    }
    
    // Batch insert
    try batchInsertFacts(&system, &facts);
    
    // Verify all facts inserted
    for (1..6) |i| {
        try testing.expect(system.getFact(@intCast(i)) != null);
    }
    
    const stats = system.getStats();
    try testing.expectEqual(@as(usize, 5), stats.facts_inserted);
}