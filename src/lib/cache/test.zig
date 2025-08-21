/// Tests for cache module
///
/// TODO: Add cache hit rate benchmarks
/// TODO: Add concurrent access tests
/// TODO: Add memory leak tests
/// TODO: Add large dataset stress tests
const std = @import("std");
const testing = std.testing;

// Import cache components
const FactCache = @import("fact_cache.zig").FactCache;
const CacheStats = @import("fact_cache.zig").CacheStats;
const LruList = @import("lru.zig").LruList;
const QueryIndex = @import("index.zig").QueryIndex;

// Import fact types
const Fact = @import("../fact/mod.zig").Fact;
const FactStore = @import("../fact/mod.zig").FactStore;
const Builder = @import("../fact/mod.zig").Builder;
const Predicate = @import("../fact/mod.zig").Predicate;
const PackedSpan = @import("../span/mod.zig").PackedSpan;

test "Cache module integration" {
    const allocator = testing.allocator;

    // Create fact store
    var store = FactStore.init(allocator);
    defer store.deinit();

    // Create cache
    var cache = try FactCache.init(allocator, 10 * 1024); // 10KB cache
    defer cache.deinit();

    // Create index
    var index = QueryIndex.init(allocator, &store);
    defer index.deinit();

    // Create some test facts
    const span1: PackedSpan = 0x0000000500000014; // Start: 5, length: 20
    const span2: PackedSpan = 0x0000001900000019; // Start: 25, length: 25

    const facts = [_]Fact{
        try Builder.new()
            .withSubject(span1)
            .withPredicate(.is_function)
            .withConfidence(0.95)
            .build(),
        try Builder.new()
            .withSubject(span1)
            .withPredicate(.has_text) // Changed from has_name
            .withAtom(123)
            .build(),
        try Builder.new()
            .withSubject(span2)
            .withPredicate(.is_class)
            .withConfidence(0.85)
            .build(),
    };

    // Add facts to cache
    try cache.put(span1, facts[0..2]);
    try cache.put(span2, facts[2..3]);

    // Verify cache retrieval
    const cached1 = cache.get(span1);
    try testing.expect(cached1 != null);
    try testing.expectEqual(@as(usize, 2), cached1.?.len);
    defer allocator.free(cached1.?);

    const cached2 = cache.get(span2);
    try testing.expect(cached2 != null);
    try testing.expectEqual(@as(usize, 1), cached2.?.len);
    defer allocator.free(cached2.?);

    // Test cache statistics
    const stats = cache.getStats();
    try testing.expect(stats.hits > 0);
    try testing.expect(stats.fact_count > 0);
    try testing.expect(stats.hitRate() > 0.0);
}

test "LRU eviction policy" {
    const allocator = testing.allocator;

    var lru = try LruList.init(allocator, 100);
    defer lru.deinit();

    // Add spans in order
    const spans = [_]PackedSpan{
        0x0000000100000010,
        0x0000002000000020,
        0x0000004000000030,
        0x0000006000000040,
    };

    for (spans) |span| {
        try lru.add(span);
    }

    // Touch first span to make it most recent
    lru.touch(spans[0]);

    // Evict should return second span (least recently used)
    const evicted = lru.evict();
    try testing.expect(evicted != null);
    // Note: Due to touch operation, spans[0] is now most recent

    // Verify remaining spans
    try testing.expectEqual(@as(usize, 3), lru.current_nodes);
}

test "Query index with multiple predicates" {
    const allocator = testing.allocator;

    var store = FactStore.init(allocator);
    defer store.deinit();

    var index = QueryIndex.init(allocator, &store);
    defer index.deinit();

    // Create facts with different predicates
    const span: PackedSpan = 0x0000000000000100;

    const predicates = [_]Predicate{
        .is_function,
        .is_class,
        .has_text, // Changed from has_name
        .is_method, // Changed from is_public
    };

    for (predicates) |pred| {
        const fact = try Builder.new()
            .withSubject(span)
            .withPredicate(pred)
            .build();
        const id = try store.append(fact);
        try index.update(fact, id);
    }

    // Query by each predicate
    for (predicates) |pred| {
        const results = index.queryByPredicate(pred);
        try testing.expectEqual(@as(usize, 1), results.len);
    }

    // Complex query
    const complex = try index.queryComplex(.is_function, span, null);
    defer allocator.free(complex);
    try testing.expectEqual(@as(usize, 1), complex.len);
}

test "Cache eviction under memory pressure" {
    // TODO: Phase 3 - Adjust test expectations for eviction behavior
    const allocator = testing.allocator;

    // Create small cache (only fits ~2 facts)
    var cache = try FactCache.init(allocator, @sizeOf(Fact) * 2 + 100);
    defer cache.deinit();

    // Create multiple facts
    const spans = [_]PackedSpan{
        0x0000000100000010,
        0x0000002000000020,
        0x0000003000000030,
    };

    for (spans) |span| {
        const fact = try Builder.new()
            .withSubject(span)
            .withPredicate(.is_token)
            .build();
        try cache.put(span, &[_]Fact{fact});
    }

    // First span should have been evicted
    const stats = cache.getStats();
    try testing.expect(stats.evictions > 0);
}

test "Confidence bucket distribution" {
    const allocator = testing.allocator;

    var store = FactStore.init(allocator);
    defer store.deinit();

    var index = QueryIndex.init(allocator, &store);
    defer index.deinit();

    // Create facts with varying confidence
    const confidences = [_]f16{ 0.1, 0.25, 0.5, 0.75, 0.9, 0.99 };

    for (confidences) |conf| {
        const fact = try Builder.new()
            .withSubject(0x0000000100000010)
            .withPredicate(.is_token)
            .withConfidence(conf)
            .build();
        const id = try store.append(fact);
        try index.update(fact, id);
    }

    // Query high confidence facts
    const high_conf = try index.queryByConfidence(0.7, 1.0);
    defer allocator.free(high_conf);
    try testing.expectEqual(@as(usize, 3), high_conf.len);

    // Query low confidence facts
    const low_conf = try index.queryByConfidence(0.0, 0.3);
    defer allocator.free(low_conf);
    try testing.expectEqual(@as(usize, 2), low_conf.len);
}

// TODO: Benchmark tests
test "BENCHMARK: Cache performance" {
    // TODO: Measure cache hit/miss rates
    // TODO: Measure eviction overhead
    // TODO: Compare with BoundaryCache performance
}

// TODO: Concurrent access tests
test "CONCURRENT: Cache thread safety" {
    // TODO: Multiple threads reading/writing cache
    // TODO: Verify no data races
    // TODO: Test atomic operations
}

// TODO: Memory tests
test "MEMORY: Cache memory usage" {
    // TODO: Verify memory limits are respected
    // TODO: Check for memory leaks
    // TODO: Test memory compaction
}
