const std = @import("std");

// Comprehensive integration tests for the collections module
// Tests the interaction between FactIndex, QueryCache, and memory pools

// Import all foundation modules for testing
test "collections integration" {
    _ = @import("fact_index.zig");
    _ = @import("query_cache.zig");
    _ = @import("pools.zig");
    _ = @import("mod.zig");
}

test "fact storage system complete workflow" {
    const testing = std.testing;

    // Import types
    const Span = @import("../types/span.zig").Span;
    const Fact = @import("../types/fact.zig").Fact;
    const FactId = @import("../types/fact.zig").FactId;
    const Predicate = @import("../types/predicate.zig").Predicate;
    // const PredicateCategory = @import("../types/predicate.zig").PredicateCategory;
    const collections = @import("mod.zig");

    var system = collections.FactStorageSystem.init(testing.allocator);
    defer system.deinit();

    // Test data setup
    const spans = [_]Span{
        Span.init(0, 10), // "function"
        Span.init(11, 20), // "myFunc"
        Span.init(20, 21), // "("
        Span.init(21, 25), // "arg1"
        Span.init(25, 26), // ":"
        Span.init(27, 30), // "i32"
        Span.init(30, 31), // ")"
        Span.init(32, 50), // "{ ... }"
    };

    const predicates = [_]Predicate{
        Predicate{ .is_token = .keyword }, // "function"
        Predicate{ .is_token = .identifier }, // "myFunc"
        Predicate{ .is_token = .delimiter }, // "("
        Predicate{ .is_token = .identifier }, // "arg1"
        Predicate{ .is_token = .operator }, // ":"
        Predicate{ .is_token = .identifier }, // "i32"
        Predicate{ .is_token = .delimiter }, // ")"
        Predicate{ .is_boundary = .function }, // "{ ... }"
    };

    // Insert facts for a function declaration
    var facts: [8]Fact = undefined;
    for (&facts, 0..) |*fact, i| {
        fact.* = Fact.simple(@intCast(i + 1), spans[i], predicates[i], 0);
    }

    try collections.batchInsertFacts(&system, &facts);

    // Test 1: Basic fact retrieval
    const retrieved_fact = system.getFact(2);
    try testing.expect(retrieved_fact != null);
    try testing.expect(retrieved_fact.?.subject.eql(spans[1])); // "myFunc"

    // Test 2: Span-based queries
    const function_span = Span.init(0, 50); // Entire function
    const overlapping_query = collections.queryOverlappingSpan(function_span);
    const overlapping_facts = try system.queryFacts(overlapping_query, testing.allocator);
    defer testing.allocator.free(overlapping_facts);

    try testing.expectEqual(@as(usize, 8), overlapping_facts.len); // All facts overlap

    // Test 3: Category-based queries
    const lexical_query = collections.queryByCategory(.lexical);
    const lexical_facts = try system.queryFacts(lexical_query, testing.allocator);
    defer testing.allocator.free(lexical_facts);

    // Should find 6 lexical facts (all tokens)
    try testing.expectEqual(@as(usize, 6), lexical_facts.len);

    // Test 4: Cache hit on repeated query
    const lexical_facts_2 = try system.queryFacts(lexical_query, testing.allocator);
    defer testing.allocator.free(lexical_facts_2);

    const stats = system.getStats();
    try testing.expectEqual(@as(usize, 1), stats.cache_hits);

    // Test 5: Complex queries
    const identifier_in_params = collections.ComplexQuery{
        .span = Span.init(20, 31), // Parameter list area
        .category = .lexical,
        .min_confidence = 1.0,
    };
    const complex_query = collections.queryComplex(identifier_in_params);
    const param_facts = try system.queryFacts(complex_query, testing.allocator);
    defer testing.allocator.free(param_facts);

    // Should find identifiers and operators in parameter list
    try testing.expect(param_facts.len >= 2);

    // Test 6: Position-based queries
    const position_query = collections.queryContainingPosition(15); // Inside "myFunc"
    const position_facts = try system.queryFacts(position_query, testing.allocator);
    defer testing.allocator.free(position_facts);

    try testing.expectEqual(@as(usize, 1), position_facts.len);
    try testing.expectEqual(@as(FactId, 2), position_facts[0]); // "myFunc" fact

    // Test 7: Generation management
    const original_gen = system.index.getCurrentGeneration();
    const next_gen = system.nextGeneration();
    try testing.expectEqual(original_gen + 1, next_gen);

    // Test 8: Cache invalidation by span changes
    const cache_stats_before = system.cache.getStats();
    system.cache.invalidateSpan(spans[1]); // Invalidate "myFunc" span

    // Query again - should be cache miss
    const lexical_facts_3 = try system.queryFacts(lexical_query, testing.allocator);
    defer testing.allocator.free(lexical_facts_3);

    const cache_stats_after = system.cache.getStats();
    try testing.expect(cache_stats_after.span_invalidations > cache_stats_before.span_invalidations);
}

test "performance characteristics" {
    const testing = std.testing;

    // Import types
    const Span = @import("../types/span.zig").Span;
    const Fact = @import("../types/fact.zig").Fact;
    const Predicate = @import("../types/predicate.zig").Predicate;
    const collections = @import("mod.zig");
    const PerfTimer = @import("../mod.zig").PerfTimer;

    var system = collections.FactStorageSystem.init(testing.allocator);
    defer system.deinit();

    // Create a large number of facts for performance testing
    const num_facts = 1000;
    var facts = std.ArrayList(Fact).init(testing.allocator);
    defer facts.deinit();

    // Generate diverse facts
    for (0..num_facts) |i| {
        const start = i * 10;
        const end = start + 5 + (i % 10); // Variable lengths
        const span = Span.init(start, end);

        const predicate = switch (i % 4) {
            0 => Predicate{ .is_token = .identifier },
            1 => Predicate{ .is_token = .keyword },
            2 => Predicate{ .is_boundary = .function },
            3 => Predicate{ .is_node = .declaration },
            else => unreachable,
        };

        const fact = Fact.simple(@intCast(i + 1), span, predicate, @intCast(i % 10));
        try facts.append(fact);
    }

    // Test batch insertion performance
    const insert_timer = PerfTimer.start();
    try collections.batchInsertFacts(&system, facts.items);
    const insert_time = insert_timer.elapsed();

    // Should be fast: <1ms for 1000 facts
    try testing.expect(insert_time < 1_000_000); // 1ms in nanoseconds

    // Test lookup performance
    const lookup_timer = PerfTimer.start();
    for (1..101) |i| { // Look up first 100 facts
        _ = system.getFact(@intCast(i));
    }
    const lookup_time = lookup_timer.elapsed();

    // Should be very fast: <100μs for 100 lookups
    try testing.expect(lookup_time < 100_000); // 100μs in nanoseconds

    // Test span query performance
    const query_span = Span.init(0, 5000); // Large span covering many facts
    const query_timer = PerfTimer.start();

    const overlapping_query = collections.queryOverlappingSpan(query_span);
    const results = try system.queryFacts(overlapping_query, testing.allocator);
    defer testing.allocator.free(results);

    const query_time = query_timer.elapsed();

    // Should be reasonably fast: <10ms for large span query
    try testing.expect(query_time < 10_000_000); // 10ms in nanoseconds
    try testing.expect(results.len > 100); // Should find many facts

    // Test cache performance
    const cache_timer = PerfTimer.start();
    for (0..10) |_| {
        const cached_results = try system.queryFacts(overlapping_query, testing.allocator);
        testing.allocator.free(cached_results);
    }
    const cache_time = cache_timer.elapsed();

    // Cache hits should be much faster than original query
    try testing.expect(cache_time < query_time / 2);

    // Verify cache hit rate
    const final_stats = system.getStats();
    try testing.expect(final_stats.cacheHitRate() > 0.5);
}

test "memory pool efficiency" {
    const testing = std.testing;

    const Fact = @import("../types/fact.zig").Fact;
    const pools = @import("pools.zig");

    // Test fact pool efficiency
    var fact_pool = pools.FactPool.init(testing.allocator, 100);
    defer fact_pool.deinit();

    // Acquire and release facts
    var acquired_facts: [50]*Fact = undefined;

    // First acquisition should be pool misses
    for (&acquired_facts) |*fact_ptr| {
        fact_ptr.* = try fact_pool.acquire();
    }

    var stats = fact_pool.getStats();
    try testing.expectEqual(@as(usize, 50), stats.pool_misses);
    try testing.expectEqual(@as(usize, 0), stats.pool_hits);

    // Release all facts
    for (acquired_facts) |fact_ptr| {
        fact_pool.release(fact_ptr);
    }

    stats = fact_pool.getStats();
    try testing.expectEqual(@as(usize, 50), stats.pool_releases);

    // Second acquisition should be pool hits
    for (&acquired_facts) |*fact_ptr| {
        fact_ptr.* = try fact_pool.acquire();
    }

    stats = fact_pool.getStats();
    try testing.expectEqual(@as(usize, 50), stats.pool_hits);
    try testing.expect(stats.hitRate() > 0.5);

    // Clean up
    for (acquired_facts) |fact_ptr| {
        testing.allocator.destroy(fact_ptr);
    }
}

test "array pool sizing" {
    const testing = std.testing;

    const pools = @import("pools.zig");
    const FactId = @import("../types/fact.zig").FactId;

    var array_pool = pools.FactIdArrayPool.init(testing.allocator, 20);
    defer array_pool.deinit();

    // Test various sizes to verify bucket allocation
    const test_sizes = [_]usize{ 1, 3, 8, 16, 32, 100 };
    var arrays: [6][]FactId = undefined;

    for (test_sizes, 0..) |size, i| {
        arrays[i] = try array_pool.acquire(size);
        try testing.expect(arrays[i].len >= size);
    }

    // Release arrays
    for (arrays) |array| {
        array_pool.release(array);
    }

    const stats = array_pool.getStats();
    try testing.expectEqual(@as(usize, 6), stats.total_allocated);
    try testing.expectEqual(@as(usize, 6), stats.releases);

    // Second acquisition should reuse from pools
    for (test_sizes, 0..) |size, i| {
        arrays[i] = try array_pool.acquire(size);
    }

    const stats2 = array_pool.getStats();
    try testing.expect(stats2.hits > 0);

    // Clean up
    for (arrays) |array| {
        array_pool.release(array);
    }
}

test "generation-based cache invalidation" {
    const testing = std.testing;

    const Span = @import("../types/span.zig").Span;
    const Fact = @import("../types/fact.zig").Fact;
    const Predicate = @import("../types/predicate.zig").Predicate;
    const collections = @import("mod.zig");

    var system = collections.FactStorageSystem.init(testing.allocator);
    defer system.deinit();

    // Insert facts in generation 0
    const span = Span.init(10, 20);
    const predicate = Predicate{ .is_token = .identifier };
    const fact1 = Fact.simple(1, span, predicate, 0);
    const fact2 = Fact.simple(2, span, predicate, 0);

    try system.insertFact(fact1);
    try system.insertFact(fact2);

    // Query and cache result
    const gen0_query = collections.queryByGeneration(0);
    const gen0_results = try system.queryFacts(gen0_query, testing.allocator);
    defer testing.allocator.free(gen0_results);

    try testing.expectEqual(@as(usize, 2), gen0_results.len);

    // Advance generation
    const gen1 = system.nextGeneration();
    try testing.expectEqual(@as(@import("../types/fact.zig").Generation, 1), gen1);

    // Insert new fact in generation 1
    const fact3 = Fact.simple(3, span, predicate, 1);
    try system.insertFact(fact3);

    // Old generation query should still work but may miss cache
    const gen0_results_2 = try system.queryFacts(gen0_query, testing.allocator);
    defer testing.allocator.free(gen0_results_2);

    try testing.expectEqual(@as(usize, 2), gen0_results_2.len);

    // New generation query
    const gen1_query = collections.queryByGeneration(1);
    const gen1_results = try system.queryFacts(gen1_query, testing.allocator);
    defer testing.allocator.free(gen1_results);

    try testing.expectEqual(@as(usize, 1), gen1_results.len);
    try testing.expectEqual(@as(@import("../types/fact.zig").FactId, 3), gen1_results[0]);

    // Verify cache behavior
    const cache_stats = system.getStats().cache_stats;
    try testing.expect(cache_stats.generation_invalidations > 0);
}

test "complex query edge cases" {
    const testing = std.testing;

    const Span = @import("../types/span.zig").Span;
    const Fact = @import("../types/fact.zig").Fact;
    const Predicate = @import("../types/predicate.zig").Predicate;
    const collections = @import("mod.zig");

    var system = collections.FactStorageSystem.init(testing.allocator);
    defer system.deinit();

    // Create facts with different confidence levels
    const span = Span.init(10, 20);
    const predicate = Predicate{ .is_token = .identifier };

    const high_confidence_fact = Fact.init(1, span, predicate, null, 1.0, 0);
    const medium_confidence_fact = Fact.init(2, span, predicate, null, 0.7, 0);
    const low_confidence_fact = Fact.init(3, span, predicate, null, 0.3, 0);

    try system.insertFact(high_confidence_fact);
    try system.insertFact(medium_confidence_fact);
    try system.insertFact(low_confidence_fact);

    // Test confidence filtering
    const high_confidence_complex = collections.ComplexQuery{
        .min_confidence = 0.9,
        .category = .lexical,
    };
    const high_conf_query = collections.queryComplex(high_confidence_complex);
    const high_conf_results = try system.queryFacts(high_conf_query, testing.allocator);
    defer testing.allocator.free(high_conf_results);

    try testing.expectEqual(@as(usize, 1), high_conf_results.len);
    try testing.expectEqual(@as(@import("../types/fact.zig").FactId, 1), high_conf_results[0]);

    // Test speculative filtering
    const no_speculative_complex = collections.ComplexQuery{
        .include_speculative = false,
        .category = .lexical,
    };
    const no_spec_query = collections.queryComplex(no_speculative_complex);
    const no_spec_results = try system.queryFacts(no_spec_query, testing.allocator);
    defer testing.allocator.free(no_spec_results);

    try testing.expectEqual(@as(usize, 1), no_spec_results.len); // Only high confidence fact

    // Test empty result handling
    const impossible_complex = collections.ComplexQuery{
        .min_confidence = 2.0, // Impossible confidence level
    };
    const impossible_query = collections.queryComplex(impossible_complex);
    const empty_results = try system.queryFacts(impossible_query, testing.allocator);
    defer testing.allocator.free(empty_results);

    try testing.expectEqual(@as(usize, 0), empty_results.len);
}
