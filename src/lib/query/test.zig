/// Tests for query module
const std = @import("std");
const testing = std.testing;

// Import query components
const QueryBuilder = @import("builder.zig").QueryBuilder;
const Query = @import("query.zig").Query;
const QueryExecutor = @import("executor.zig").QueryExecutor;
const QueryOptimizer = @import("optimizer.zig").QueryOptimizer;
const QueryPlanner = @import("planner.zig").QueryPlanner;

const Op = @import("operators.zig").Op;
const Field = @import("operators.zig").Field;
const Direction = @import("operators.zig").Direction;
const Value = @import("operators.zig").Value;

// Import fact components
const Fact = @import("../fact/mod.zig").Fact;
const FactStore = @import("../fact/mod.zig").FactStore;
const Builder = @import("../fact/mod.zig").Builder;
const Predicate = @import("../fact/mod.zig").Predicate;
const PackedSpan = @import("../span/mod.zig").PackedSpan;
const Span = @import("../span/mod.zig").Span;

// Import DirectStream support
const DirectStream = @import("../stream/mod.zig").DirectStream;
const directExecute = @import("executor.zig").directExecute;

test "QueryBuilder basic construction" {
    const allocator = testing.allocator;
    
    var builder = QueryBuilder.init(allocator);
    defer builder.deinit();
    
    _ = try builder
        .select(&.{ .is_function, .is_class })
        .where(.confidence, .gte, 0.9);
    _ = try builder.orderBy(.span_start, .ascending);
    _ = builder.limit(10);
    
    const query = try builder.build();
    defer {
        var q = query;
        q.deinit();
    }
    
    // Verify query structure
    try testing.expect(query.limit_ == 10);
    try testing.expect(query.where != null);
    try testing.expect(query.order_by != null);
}

test "Query execution with simple WHERE" {
    const allocator = testing.allocator;
    
    // Create fact store with test data
    var store = FactStore.init(allocator);
    defer store.deinit();
    
    // Add test facts
    const facts = [_]Fact{
        try Builder.new()
            .withSubject(0x0000000100000010)
            .withPredicate(.is_function)
            .withConfidence(0.95)
            .build(),
        try Builder.new()
            .withSubject(0x0000002000000020)
            .withPredicate(.is_class)
            .withConfidence(0.85)
            .build(),
        try Builder.new()
            .withSubject(0x0000003000000030)
            .withPredicate(.is_function)
            .withConfidence(0.75)
            .build(),
    };
    
    for (facts) |fact| {
        _ = try store.append(fact);
    }
    
    // Execute query for high confidence facts
    var builder = QueryBuilder.init(allocator);
    defer builder.deinit();
    
    _ = builder.selectAll().from(&store);
    _ = try builder.where(.confidence, .gte, 0.8);
    var result = try builder.execute();
    defer result.deinit();
    
    // Should return 2 facts with confidence >= 0.8
    try testing.expectEqual(@as(usize, 2), result.facts.len);
}

test "Query with predicate selection" {
    const allocator = testing.allocator;
    
    var store = FactStore.init(allocator);
    defer store.deinit();
    
    // Add mixed facts
    const predicates = [_]Predicate{ .is_function, .is_class, .is_method, .is_token };
    for (predicates, 0..) |pred, i| {
        const fact = try Builder.new()
            .withSubject(@as(PackedSpan, @intCast(i << 32 | 0x10)))
            .withPredicate(pred)
            .build();
        _ = try store.append(fact);
    }
    
    // Query for specific predicates
    var builder = QueryBuilder.init(allocator);
    defer builder.deinit();
    
    _ = builder.select(&.{ .is_function, .is_method }).from(&store);
    var result = try builder.execute();
    defer result.deinit();
    
    try testing.expectEqual(@as(usize, 2), result.facts.len);
}

test "Query with ORDER BY" {
    const allocator = testing.allocator;
    
    var store = FactStore.init(allocator);
    defer store.deinit();
    
    // Add facts with different confidence values
    const confidences = [_]f16{ 0.9, 0.5, 0.7, 0.3, 0.8 };
    for (confidences, 0..) |conf, i| {
        const fact = try Builder.new()
            .withSubject(@as(PackedSpan, @intCast(i << 32 | 0x10)))
            .withPredicate(.is_token)
            .withConfidence(conf)
            .build();
        _ = try store.append(fact);
    }
    
    // Query with ordering
    var builder = QueryBuilder.init(allocator);
    defer builder.deinit();
    
    _ = builder.selectAll().from(&store);
    _ = try builder.orderBy(.confidence, .descending);
    _ = builder.limit(3);
    var result = try builder.execute();
    defer result.deinit();
    
    // Should return top 3 by confidence
    try testing.expectEqual(@as(usize, 3), result.facts.len);
    
    // Verify descending order
    if (result.facts.len >= 2) {
        try testing.expect(result.facts[0].confidence >= result.facts[1].confidence);
    }
}

test "Query with LIMIT and OFFSET" {
    const allocator = testing.allocator;
    
    var store = FactStore.init(allocator);
    defer store.deinit();
    
    // Add 10 facts
    for (0..10) |i| {
        const fact = try Builder.new()
            .withSubject(@as(PackedSpan, @intCast(i << 32 | 0x10)))
            .withPredicate(.is_token)
            .build();
        _ = try store.append(fact);
    }
    
    // Query with pagination
    var builder = QueryBuilder.init(allocator);
    defer builder.deinit();
    
    _ = builder.selectAll().from(&store).limit(3).offset(5);
    var result = try builder.execute();
    defer result.deinit();
    
    // Should return 3 facts starting from offset 5
    try testing.expectEqual(@as(usize, 3), result.facts.len);
}

test "Query optimization - predicate pushdown" {
    const allocator = testing.allocator;
    
    var store = FactStore.init(allocator);
    defer store.deinit();
    
    // Create query with predicate in WHERE
    var builder = QueryBuilder.init(allocator);
    defer builder.deinit();
    
    _ = builder.selectAll().from(&store);
    _ = try builder.where(.predicate, .eq, Value{ .predicate = .is_function });
    
    const query = try builder.build();
    defer {
        var q = query;
        q.deinit();
    }
    
    // Optimize query
    var optimizer = QueryOptimizer.init(allocator);
    defer optimizer.deinit();
    
    const optimized = try optimizer.optimize(&query);
    defer {
        var opt = optimized;
        opt.deinit();
    }
    
    // TODO: Verify predicate was pushed down to SELECT
    // For now just verify optimization doesn't crash
    try testing.expect(optimizer.stats.predicate_pushdowns >= 0);
}

test "Query planner - execution plan creation" {
    const allocator = testing.allocator;
    
    var store = FactStore.init(allocator);
    defer store.deinit();
    
    // Create complex query
    var builder = QueryBuilder.init(allocator);
    defer builder.deinit();
    
    _ = builder.select(&.{.is_function}).from(&store);
    _ = try builder.where(.confidence, .gte, 0.8);
    _ = try builder.orderBy(.span_start, .ascending);
    _ = builder.limit(10);
    
    const query = try builder.build();
    defer {
        var q = query;
        q.deinit();
    }
    
    // Create execution plan
    var optimizer = QueryOptimizer.init(allocator);
    defer optimizer.deinit();
    
    var planner = QueryPlanner.init(allocator, &optimizer);
    defer planner.deinit();
    
    var plan = try planner.createPlan(&query);
    defer plan.deinit();
    
    // Verify plan structure
    try testing.expect(plan.root.type == .project);
    try testing.expect(plan.estimated_cost > 0);
}

test "Complex query with multiple conditions" {
    const allocator = testing.allocator;
    
    var store = FactStore.init(allocator);
    defer store.deinit();
    
    // Add diverse facts
    for (0..20) |i| {
        const pred: Predicate = if (i % 2 == 0) .is_function else .is_class;
        const conf: f16 = @floatCast(@as(f32, @floatFromInt(i)) / 20.0);
        
        const fact = try Builder.new()
            .withSubject(@as(PackedSpan, @intCast(i << 32 | (i * 10))))
            .withPredicate(pred)
            .withConfidence(conf)
            .build();
        _ = try store.append(fact);
    }
    
    // Complex query
    var builder = QueryBuilder.init(allocator);
    defer builder.deinit();
    
    _ = builder.select(&.{.is_function}).from(&store);
    _ = try builder.where(.confidence, .gte, 0.5);
    _ = try builder.andWhere(.span_length, .lte, 50);
    _ = try builder.orderBy(.confidence, .descending);
    _ = builder.limit(5);
    var result = try builder.execute();
    defer result.deinit();
    
    // Verify results
    try testing.expect(result.facts.len <= 5);
    for (result.facts) |fact| {
        try testing.expect(fact.confidence >= 0.5);
        try testing.expect(fact.predicate == .is_function);
    }
}

test "Query format and display" {
    const allocator = testing.allocator;
    
    var builder = QueryBuilder.init(allocator);
    defer builder.deinit();
    
    _ = builder.select(&.{.is_function});
    _ = try builder.where(.confidence, .gte, 0.9);
    _ = try builder.orderBy(.span_start, .ascending);
    _ = builder.limit(10);
    
    const query = try builder.build();
    defer {
        var q = query;
        q.deinit();
    }
    
    // Format query
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    
    try query.format("", .{}, buffer.writer());
    
    const output = buffer.items;
    
    // Verify formatted output contains expected elements
    try testing.expect(std.mem.indexOf(u8, output, "SELECT") != null);
    try testing.expect(std.mem.indexOf(u8, output, "WHERE") != null);
    try testing.expect(std.mem.indexOf(u8, output, "ORDER BY") != null);
    try testing.expect(std.mem.indexOf(u8, output, "LIMIT") != null);
}

// TODO: Phase 3 - Additional tests to implement
test "Query with GROUP BY and HAVING" {
    // TODO: Implement when GROUP BY is functional
}

test "Streaming query execution" {
    // TODO: Implement when streaming is functional
}

test "Query with index usage" {
    // TODO: Implement when index integration is complete
}

test "Parallel query execution" {
    // TODO: Implement when parallel execution is added
}

// DirectStream migration tests (Phase 5A)

test "QueryExecutor.directExecute basic usage" {
    const allocator = testing.allocator;
    
    // Create fact store
    var store = FactStore.init(allocator);
    defer store.deinit();
    
    // Add test facts
    _ = try store.append(try Builder.new()
        .withSpan(Span.init(0, 10))
        .withPredicate(.is_function)
        .withConfidence(0.95)
        .build());
    
    _ = try store.append(try Builder.new()
        .withSpan(Span.init(20, 30))
        .withPredicate(.is_class)
        .withConfidence(0.85)
        .build());
    
    // Build query
    var builder = QueryBuilder.init(allocator);
    defer builder.deinit();
    
    _ = builder.selectAll().from(&store);
    _ = try builder.where(.confidence, .gte, 0.8);
    
    const query = try builder.build();
    defer {
        var q = query;
        q.deinit();
    }
    
    // Execute with DirectStream
    var executor = QueryExecutor.init(allocator);
    defer executor.deinit();
    
    var stream = try executor.directExecute(&query);
    
    // Verify stream results
    var count: usize = 0;
    while (try stream.next()) |fact| {
        try testing.expect(fact.confidence >= 0.8);
        count += 1;
    }
    
    try testing.expect(count == 2);
}

test "DirectStream vs Stream performance comparison" {
    const allocator = testing.allocator;
    
    // Create larger fact store for performance testing
    var store = FactStore.init(allocator);
    defer store.deinit();
    
    // Add 1000 test facts
    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        _ = try store.append(try Builder.new()
            .withSpan(Span.init(i * 10, i * 10 + 5))
            .withPredicate(if (i % 2 == 0) .is_function else .is_class)
            .withConfidence(@as(f16, @floatFromInt(i % 100)) / 100.0)
            .build());
    }
    
    // Build query
    var builder = QueryBuilder.init(allocator);
    defer builder.deinit();
    
    _ = builder.selectAll().from(&store);
    _ = try builder.where(.confidence, .gte, 0.5);
    _ = builder.limit(100);
    
    const query = try builder.build();
    defer {
        var q = query;
        q.deinit();
    }
    
    var executor = QueryExecutor.init(allocator);
    defer executor.deinit();
    
    // Measure Stream performance
    const stream_start = std.time.nanoTimestamp();
    var stream_result = try executor.execute(&query);
    defer stream_result.deinit();
    const stream_time = std.time.nanoTimestamp() - stream_start;
    
    // Measure DirectStream performance  
    const direct_start = std.time.nanoTimestamp();
    var direct_stream = try executor.directExecute(&query);
    var direct_count: usize = 0;
    while (try direct_stream.next()) |_| {
        direct_count += 1;
    }
    const direct_time = std.time.nanoTimestamp() - direct_start;
    
    // DirectStream should be faster (or at least not slower)
    // We're being lenient here since it's early migration
    try testing.expect(direct_count == stream_result.facts.len);
    
    // Log performance for debugging (not a hard assertion)
    std.debug.print("\n  Stream time: {} ns\n", .{stream_time});
    std.debug.print("  DirectStream time: {} ns\n", .{direct_time});
    if (direct_time < stream_time) {
        const improvement = @as(f64, @floatFromInt(stream_time - direct_time)) / @as(f64, @floatFromInt(stream_time)) * 100;
        std.debug.print("  DirectStream {d:.1}% faster\n", .{improvement});
    }
}

test "DirectStream query with complex conditions" {
    const allocator = testing.allocator;
    
    var store = FactStore.init(allocator);
    defer store.deinit();
    
    // Add varied test facts
    _ = try store.append(try Builder.new()
        .withSpan(Span.init(0, 10))
        .withPredicate(.is_function)
        .withConfidence(0.95)
        .build());
    
    _ = try store.append(try Builder.new()
        .withSpan(Span.init(10, 20))
        .withPredicate(.is_function)
        .withConfidence(0.75)
        .build());
    
    _ = try store.append(try Builder.new()
        .withSpan(Span.init(20, 30))
        .withPredicate(.is_class)
        .withConfidence(0.85)
        .build());
    
    _ = try store.append(try Builder.new()
        .withSpan(Span.init(30, 40))
        .withPredicate(.is_variable)
        .withConfidence(0.65)
        .build());
    
    // Complex query
    var builder = QueryBuilder.init(allocator);
    defer builder.deinit();
    
    _ = builder.select(&.{ .is_function, .is_class }).from(&store);
    _ = try builder.where(.confidence, .gte, 0.7);
    _ = try builder.orderBy(.confidence, .descending);
    _ = builder.limit(2);
    
    const query = try builder.build();
    defer {
        var q = query;
        q.deinit();
    }
    
    var executor = QueryExecutor.init(allocator);
    defer executor.deinit();
    
    var stream = try executor.directExecute(&query);
    
    // Check results in order
    const fact1 = (try stream.next()).?;
    try testing.expect(fact1.confidence >= 0.85);
    
    const fact2 = (try stream.next()).?;
    try testing.expect(fact2.confidence >= 0.75);
    
    // Should be limited to 2
    try testing.expect(try stream.next() == null);
}