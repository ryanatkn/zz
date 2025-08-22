const std = @import("std");
const benchmark_lib = @import("../../lib/benchmark/mod.zig");
const BenchmarkResult = benchmark_lib.BenchmarkResult;
const BenchmarkOptions = benchmark_lib.BenchmarkOptions;
const BenchmarkError = benchmark_lib.BenchmarkError;

// Import stream-first modules
const stream_mod = @import("../../lib/stream/mod.zig");
const fact_mod = @import("../../lib/fact/mod.zig");
const span_mod = @import("../../lib/span/mod.zig");
const memory_mod = @import("../../lib/memory/mod.zig");
const query_mod = @import("../../lib/query/mod.zig");

// Stream module benchmarks
pub fn runStreamBenchmarks(allocator: std.mem.Allocator, options: BenchmarkOptions) BenchmarkError![]BenchmarkResult {
    var results = std.ArrayList(BenchmarkResult).init(allocator);
    errdefer {
        for (results.items) |result| {
            result.deinit(allocator);
        }
        results.deinit();
    }

    const effective_duration = @as(u64, @intFromFloat(@as(f64, @floatFromInt(options.duration_ns)) * 1.0 * options.duration_multiplier));

    // Stream.next() throughput benchmark
    {
        const context = struct {
            allocator: std.mem.Allocator,

            pub fn run(_: @This()) anyerror!void {
                const data = [_]u32{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
                var source = stream_mod.MemorySource(u32).init(&data);
                var stream = source.stream();

                // Process all items
                while (try stream.next()) |_| {}
            }
        }{ .allocator = allocator };

        const result = try benchmark_lib.measureOperationNamedWithSuite(
            allocator,
            "stream_first",
            "Stream.next() throughput",
            effective_duration,
            options.warmup,
            context,
            @TypeOf(context).run,
        );
        try results.append(result);
    }

    // RingBuffer push/pop operations
    {
        const context = struct {
            pub fn run(_: @This()) anyerror!void {
                var buffer = stream_mod.RingBuffer(u32, 256){};

                // Push and pop cycle
                for (0..10) |i| {
                    try buffer.push(@intCast(i));
                }
                for (0..10) |_| {
                    _ = buffer.pop();
                }
            }
        }{};

        const result = try benchmark_lib.measureOperationNamedWithSuite(
            allocator,
            "stream_first",
            "RingBuffer push/pop",
            effective_duration,
            options.warmup,
            context,
            @TypeOf(context).run,
        );
        try results.append(result);
    }

    // Map operator performance
    {
        const context = struct {
            allocator: std.mem.Allocator,

            pub fn run(_: @This()) anyerror!void {
                const data = [_]u32{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
                var source = stream_mod.MemorySource(u32).init(&data);
                const stream = source.stream();

                const doubler = struct {
                    fn double(x: u32) u32 {
                        return x * 2;
                    }
                }.double;

                var mapped = stream_mod.operators.map(u32, u32, stream, doubler);
                defer mapped.close();

                while (try mapped.next()) |_| {}
            }
        }{ .allocator = allocator };

        const result = try benchmark_lib.measureOperationNamedWithSuite(
            allocator,
            "stream_first",
            "Map operator",
            effective_duration,
            options.warmup,
            context,
            @TypeOf(context).run,
        );
        try results.append(result);
    }

    // Filter operator performance
    {
        const context = struct {
            allocator: std.mem.Allocator,

            pub fn run(_: @This()) anyerror!void {
                const data = [_]u32{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
                var source = stream_mod.MemorySource(u32).init(&data);
                const stream = source.stream();

                const isEven = struct {
                    fn pred(x: u32) bool {
                        return x % 2 == 0;
                    }
                }.pred;

                var filtered = stream_mod.operators.filter(u32, stream, isEven);
                defer filtered.close();

                while (try filtered.next()) |_| {}
            }
        }{ .allocator = allocator };

        const result = try benchmark_lib.measureOperationNamedWithSuite(
            allocator,
            "stream_first",
            "Filter operator",
            effective_duration,
            options.warmup,
            context,
            @TypeOf(context).run,
        );
        try results.append(result);
    }

    // FusedMap vs sequential maps comparison
    {
        const context = struct {
            allocator: std.mem.Allocator,

            pub fn run(_: @This()) anyerror!void {
                const data = [_]u32{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
                var source = stream_mod.MemorySource(u32).init(&data);
                const stream = source.stream();

                const double = struct {
                    fn f(x: u32) u32 {
                        return x * 2;
                    }
                }.f;

                const triple = struct {
                    fn f(x: u32) u32 {
                        return x * 3;
                    }
                }.f;

                // Test fused map (single pass)
                var fused = stream_mod.fusion.fusedMap(u32, u32, u32, stream, double, triple);
                defer fused.close();

                while (try fused.next()) |_| {}
            }
        }{ .allocator = allocator };

        const result = try benchmark_lib.measureOperationNamedWithSuite(
            allocator,
            "stream_first",
            "FusedMap operator",
            effective_duration,
            options.warmup,
            context,
            @TypeOf(context).run,
        );
        try results.append(result);
    }

    return results.toOwnedSlice();
}

// Fact module benchmarks
pub fn runFactBenchmarks(allocator: std.mem.Allocator, options: BenchmarkOptions) BenchmarkError![]BenchmarkResult {
    var results = std.ArrayList(BenchmarkResult).init(allocator);
    errdefer {
        for (results.items) |result| {
            result.deinit(allocator);
        }
        results.deinit();
    }

    const effective_duration = @as(u64, @intFromFloat(@as(f64, @floatFromInt(options.duration_ns)) * 1.5 * options.duration_multiplier));

    // Single fact creation
    {
        const context = struct {
            pub fn run(_: @This()) anyerror!void {
                const fact = fact_mod.Fact{
                    .id = 1,
                    .subject = span_mod.packSpan(span_mod.Span{ .start = 0, .end = 10 }),
                    .predicate = .is_token,
                    .confidence = 1.0,
                    .object = fact_mod.Value{ .number = 42 },
                };
                _ = fact;
            }
        }{};

        const result = try benchmark_lib.measureOperationNamedWithSuite(
            allocator,
            "stream_first",
            "Fact creation",
            effective_duration,
            options.warmup,
            context,
            @TypeOf(context).run,
        );
        try results.append(result);
    }

    // FactStore append operations
    {
        const context = struct {
            allocator: std.mem.Allocator,

            pub fn run(ctx: @This()) anyerror!void {
                var store = fact_mod.FactStore.init(ctx.allocator);
                defer store.deinit();

                const fact = fact_mod.Fact{
                    .id = 0, // Will be assigned by store
                    .subject = span_mod.packSpan(span_mod.Span{ .start = 0, .end = 10 }),
                    .predicate = .is_token,
                    .confidence = 1.0,
                    .object = fact_mod.Value{ .number = 42 },
                };

                _ = try store.append(fact);
            }
        }{ .allocator = allocator };

        const result = try benchmark_lib.measureOperationNamedWithSuite(
            allocator,
            "stream_first",
            "FactStore append",
            effective_duration,
            options.warmup,
            context,
            @TypeOf(context).run,
        );
        try results.append(result);
    }

    // Batch fact creation (100 facts)
    {
        const context = struct {
            allocator: std.mem.Allocator,

            pub fn run(ctx: @This()) anyerror!void {
                var store = fact_mod.FactStore.init(ctx.allocator);
                defer store.deinit();

                var facts: [100]fact_mod.Fact = undefined;
                for (0..100) |i| {
                    facts[i] = fact_mod.Fact{
                        .id = 0,
                        .subject = span_mod.packSpan(span_mod.Span{ .start = @intCast(i * 10), .end = @intCast((i + 1) * 10) }),
                        .predicate = .is_token,
                        .confidence = 1.0,
                        .object = fact_mod.Value{ .number = @intCast(i) },
                    };
                }

                const ids = try store.appendBatch(&facts);
                defer ctx.allocator.free(ids);
            }
        }{ .allocator = allocator };

        const result = try benchmark_lib.measureOperationNamedWithSuite(
            allocator,
            "stream_first",
            "Fact batch append (100)",
            effective_duration,
            options.warmup,
            context,
            @TypeOf(context).run,
        );
        try results.append(result);
    }

    // Builder DSL performance
    {
        const context = struct {
            allocator: std.mem.Allocator,

            pub fn run(_: @This()) anyerror!void {
                const builder = fact_mod.Builder.new()
                    .withSpan(span_mod.Span{ .start = 0, .end = 10 })
                    .withPredicate(.is_token)
                    .withConfidence(1.0);

                _ = try builder.build();
            }
        }{ .allocator = allocator };

        const result = try benchmark_lib.measureOperationNamedWithSuite(
            allocator,
            "stream_first",
            "Fact Builder DSL",
            effective_duration,
            options.warmup,
            context,
            @TypeOf(context).run,
        );
        try results.append(result);
    }

    // Value type creation overhead
    {
        const context = struct {
            pub fn run(_: @This()) anyerror!void {
                // Test different value types
                const v1 = fact_mod.Value{ .none = 0 };
                const v2 = fact_mod.Value{ .number = 42 };
                const v3 = fact_mod.Value{ .span = span_mod.packSpan(span_mod.Span{ .start = 0, .end = 10 }) };
                const v4 = fact_mod.Value{ .pair = .{ .a = 123, .b = 0 } }; // atom via pair.a
                const v5 = fact_mod.Value{ .pair = .{ .a = 0, .b = 456 } }; // fact ref via pair.b
                const v6 = fact_mod.Value{ .float = 3.14 };
                const v7 = fact_mod.Value{ .uint = 1 }; // boolean as uint

                _ = v1;
                _ = v2;
                _ = v3;
                _ = v4;
                _ = v5;
                _ = v6;
                _ = v7;
            }
        }{};

        const result = try benchmark_lib.measureOperationNamedWithSuite(
            allocator,
            "stream_first",
            "Value type creation",
            effective_duration,
            options.warmup,
            context,
            @TypeOf(context).run,
        );
        try results.append(result);
    }

    return results.toOwnedSlice();
}

// Span module benchmarks
pub fn runSpanBenchmarks(allocator: std.mem.Allocator, options: BenchmarkOptions) BenchmarkError![]BenchmarkResult {
    var results = std.ArrayList(BenchmarkResult).init(allocator);
    errdefer {
        for (results.items) |result| {
            result.deinit(allocator);
        }
        results.deinit();
    }

    const effective_duration = @as(u64, @intFromFloat(@as(f64, @floatFromInt(options.duration_ns)) * 1.0 * options.duration_multiplier));

    // PackedSpan pack/unpack operations
    {
        const context = struct {
            pub fn run(_: @This()) anyerror!void {
                const span = span_mod.Span{ .start = 100, .end = 200 };
                const packed_span = span_mod.packSpan(span);
                const unpacked = span_mod.unpackSpan(packed_span);
                _ = unpacked;
            }
        }{};

        const result = try benchmark_lib.measureOperationNamedWithSuite(
            allocator,
            "stream_first",
            "PackedSpan pack/unpack",
            effective_duration,
            options.warmup,
            context,
            @TypeOf(context).run,
        );
        try results.append(result);
    }

    // Span merge operations
    {
        const context = struct {
            pub fn run(_: @This()) anyerror!void {
                const span1 = span_mod.Span{ .start = 0, .end = 50 };
                const span2 = span_mod.Span{ .start = 30, .end = 80 };
                const merged = span1.merge(span2);
                _ = merged;
            }
        }{};

        const result = try benchmark_lib.measureOperationNamedWithSuite(
            allocator,
            "stream_first",
            "Span merge",
            effective_duration,
            options.warmup,
            context,
            @TypeOf(context).run,
        );
        try results.append(result);
    }

    // Span intersect operations
    {
        const context = struct {
            pub fn run(_: @This()) anyerror!void {
                const span1 = span_mod.Span{ .start = 10, .end = 60 };
                const span2 = span_mod.Span{ .start = 40, .end = 90 };
                const intersection = span1.intersect(span2);
                _ = intersection;
            }
        }{};

        const result = try benchmark_lib.measureOperationNamedWithSuite(
            allocator,
            "stream_first",
            "Span intersect",
            effective_duration,
            options.warmup,
            context,
            @TypeOf(context).run,
        );
        try results.append(result);
    }

    // SpanSet normalization with overlapping spans
    {
        const context = struct {
            allocator: std.mem.Allocator,

            pub fn run(ctx: @This()) anyerror!void {
                var set = span_mod.SpanSet.init(ctx.allocator);
                defer set.deinit();

                // Add overlapping spans
                try set.add(span_mod.Span{ .start = 0, .end = 30 });
                try set.add(span_mod.Span{ .start = 20, .end = 50 });
                try set.add(span_mod.Span{ .start = 45, .end = 70 });
                try set.add(span_mod.Span{ .start = 65, .end = 90 });

                // Normalize merges overlapping spans
                set.normalize();
            }
        }{ .allocator = allocator };

        const result = try benchmark_lib.measureOperationNamedWithSuite(
            allocator,
            "stream_first",
            "SpanSet normalization",
            effective_duration,
            options.warmup,
            context,
            @TypeOf(context).run,
        );
        try results.append(result);
    }

    // Span distance calculations
    {
        const context = struct {
            pub fn run(_: @This()) anyerror!void {
                const span1 = span_mod.Span{ .start = 10, .end = 20 };
                const span2 = span_mod.Span{ .start = 50, .end = 60 };
                const distance = span_mod.ops.distance(span1, span2);
                _ = distance;
            }
        }{};

        const result = try benchmark_lib.measureOperationNamedWithSuite(
            allocator,
            "stream_first",
            "Span distance",
            effective_duration,
            options.warmup,
            context,
            @TypeOf(context).run,
        );
        try results.append(result);
    }

    // SpanSet union operations
    {
        const context = struct {
            allocator: std.mem.Allocator,

            pub fn run(ctx: @This()) anyerror!void {
                var set1 = span_mod.SpanSet.init(ctx.allocator);
                defer set1.deinit();
                var set2 = span_mod.SpanSet.init(ctx.allocator);
                defer set2.deinit();

                try set1.add(span_mod.Span{ .start = 0, .end = 30 });
                try set1.add(span_mod.Span{ .start = 50, .end = 80 });

                try set2.add(span_mod.Span{ .start = 20, .end = 40 });
                try set2.add(span_mod.Span{ .start = 70, .end = 100 });

                // TODO: SpanSet.unionWith not implemented yet
                // For now, manually combine sets
                for (set2.spans.items) |span| {
                    try set1.add(span);
                }
                set1.normalize();
            }
        }{ .allocator = allocator };

        const result = try benchmark_lib.measureOperationNamedWithSuite(
            allocator,
            "stream_first",
            "SpanSet union",
            effective_duration,
            options.warmup,
            context,
            @TypeOf(context).run,
        );
        try results.append(result);
    }

    return results.toOwnedSlice();
}

// Memory module benchmarks
pub fn runMemoryBenchmarks(allocator: std.mem.Allocator, options: BenchmarkOptions) BenchmarkError![]BenchmarkResult {
    var results = std.ArrayList(BenchmarkResult).init(allocator);
    errdefer {
        for (results.items) |result| {
            result.deinit(allocator);
        }
        results.deinit();
    }

    const effective_duration = @as(u64, @intFromFloat(@as(f64, @floatFromInt(options.duration_ns)) * 2.0 * options.duration_multiplier));

    // ArenaPool acquire/rotate cycles
    {
        const context = struct {
            allocator: std.mem.Allocator,

            pub fn run(ctx: @This()) anyerror!void {
                var pool = memory_mod.ArenaPool.init(ctx.allocator);
                defer pool.deinit();

                // Acquire arena and allocate
                const arena = pool.acquire();
                _ = try arena.allocator().alloc(u8, 1024);

                // Rotate to next generation
                pool.rotate();
            }
        }{ .allocator = allocator };

        const result = try benchmark_lib.measureOperationNamedWithSuite(
            allocator,
            "stream_first",
            "ArenaPool acquire/rotate",
            effective_duration,
            options.warmup,
            context,
            @TypeOf(context).run,
        );
        try results.append(result);
    }

    // AtomTable string interning
    {
        const context = struct {
            allocator: std.mem.Allocator,

            pub fn run(ctx: @This()) anyerror!void {
                var table = memory_mod.AtomTable.init(ctx.allocator);
                defer table.deinit();

                // Intern some strings
                _ = try table.intern("identifier");
                _ = try table.intern("keyword");
                _ = try table.intern("string_literal");
                _ = try table.intern("number");
            }
        }{ .allocator = allocator };

        const result = try benchmark_lib.measureOperationNamedWithSuite(
            allocator,
            "stream_first",
            "AtomTable interning",
            effective_duration,
            options.warmup,
            context,
            @TypeOf(context).run,
        );
        try results.append(result);
    }

    // AtomTable lookup performance
    {
        const context = struct {
            allocator: std.mem.Allocator,
            table: memory_mod.AtomTable,
            atoms: [4]memory_mod.AtomId,

            pub fn init(alloc: std.mem.Allocator) !@This() {
                var table = memory_mod.AtomTable.init(alloc);
                const atoms = [_]memory_mod.AtomId{
                    try table.intern("identifier"),
                    try table.intern("keyword"),
                    try table.intern("string_literal"),
                    try table.intern("number"),
                };
                return .{
                    .allocator = alloc,
                    .table = table,
                    .atoms = atoms,
                };
            }

            pub fn deinit(self: *@This()) void {
                self.table.deinit();
            }

            pub fn run(ctx: @This()) anyerror!void {
                // Lookup interned strings
                for (ctx.atoms) |atom| {
                    _ = ctx.table.getString(atom);
                }
            }
        };

        var ctx = try context.init(allocator);
        defer ctx.deinit();

        const result = try benchmark_lib.measureOperationNamedWithSuite(
            allocator,
            "stream_first",
            "AtomTable lookup",
            effective_duration,
            options.warmup,
            ctx,
            context.run,
        );
        try results.append(result);
    }

    return results.toOwnedSlice();
}

// Query module benchmarks
pub fn runQueryBenchmarks(allocator: std.mem.Allocator, options: BenchmarkOptions) BenchmarkError![]BenchmarkResult {
    var results = std.ArrayList(BenchmarkResult).init(allocator);
    errdefer {
        for (results.items) |result| {
            result.deinit(allocator);
        }
        results.deinit();
    }

    const effective_duration = @as(u64, @intFromFloat(@as(f64, @floatFromInt(options.duration_ns)) * 1.5 * options.duration_multiplier));

    // Simple query execution
    {
        const context = struct {
            allocator: std.mem.Allocator,

            pub fn run(ctx: @This()) anyerror!void {
                var store = fact_mod.FactStore.init(ctx.allocator);
                defer store.deinit();

                // Add test facts
                for (0..100) |i| {
                    const fact = fact_mod.Fact{
                        .id = 0,
                        .subject = span_mod.packSpan(span_mod.Span{ .start = @intCast(i * 10), .end = @intCast((i + 1) * 10) }),
                        .predicate = if (i % 2 == 0) fact_mod.Predicate.is_function else fact_mod.Predicate.is_class,
                        .confidence = @floatCast(@as(f64, @floatFromInt(i)) / 100.0),
                        .object = fact_mod.Value{ .number = @intCast(i) },
                    };
                    _ = try store.append(fact);
                }

                // Simple query
                var builder = query_mod.QueryBuilder.init(ctx.allocator);
                defer builder.deinit();

                _ = builder.select(&.{fact_mod.Predicate.is_function}).from(&store);
                var result = try builder.execute();
                defer result.deinit();
            }
        }{ .allocator = allocator };

        const result = try benchmark_lib.measureOperationNamedWithSuite(
            allocator,
            "stream_first",
            "Simple query (SELECT predicate)",
            effective_duration,
            options.warmup,
            context,
            @TypeOf(context).run,
        );
        try results.append(result);
    }

    // Complex query with WHERE clause
    {
        const context = struct {
            allocator: std.mem.Allocator,

            pub fn run(ctx: @This()) anyerror!void {
                var store = fact_mod.FactStore.init(ctx.allocator);
                defer store.deinit();

                // Add test facts
                for (0..100) |i| {
                    const fact = fact_mod.Fact{
                        .id = 0,
                        .subject = span_mod.packSpan(span_mod.Span{ .start = @intCast(i * 10), .end = @intCast((i + 1) * 10) }),
                        .predicate = if (i % 2 == 0) fact_mod.Predicate.is_function else fact_mod.Predicate.is_class,
                        .confidence = @floatCast(@as(f64, @floatFromInt(i)) / 100.0),
                        .object = fact_mod.Value{ .number = @intCast(i) },
                    };
                    _ = try store.append(fact);
                }

                // Complex query
                var builder = query_mod.QueryBuilder.init(ctx.allocator);
                defer builder.deinit();

                _ = builder.selectAll().from(&store);
                _ = try builder.where(.confidence, .gte, 0.5);
                _ = try builder.andWhere(.predicate, .eq, fact_mod.Predicate.is_function);
                _ = try builder.orderBy(.confidence, .descending);
                _ = builder.limit(10);

                var result = try builder.execute();
                defer result.deinit();
            }
        }{ .allocator = allocator };

        const result = try benchmark_lib.measureOperationNamedWithSuite(
            allocator,
            "stream_first",
            "Complex query (WHERE + ORDER BY + LIMIT)",
            effective_duration,
            options.warmup,
            context,
            @TypeOf(context).run,
        );
        try results.append(result);
    }

    // Query optimization overhead
    {
        const context = struct {
            allocator: std.mem.Allocator,

            pub fn run(ctx: @This()) anyerror!void {
                var store = fact_mod.FactStore.init(ctx.allocator);
                defer store.deinit();

                // Add test facts
                for (0..10) |i| {
                    const fact = fact_mod.Fact{
                        .id = 0,
                        .subject = span_mod.packSpan(span_mod.Span{ .start = @intCast(i * 10), .end = @intCast((i + 1) * 10) }),
                        .predicate = fact_mod.Predicate.is_function,
                        .confidence = 0.9,
                        .object = fact_mod.Value{ .number = @intCast(i) },
                    };
                    _ = try store.append(fact);
                }

                // Build query
                var builder = query_mod.QueryBuilder.init(ctx.allocator);
                defer builder.deinit();

                _ = builder.select(&.{fact_mod.Predicate.is_function}).from(&store);
                _ = try builder.where(.confidence, .gte, 0.8);

                var query = try builder.build();
                defer query.deinit();

                // Optimize
                var optimizer = query_mod.QueryOptimizer.init(ctx.allocator);
                defer optimizer.deinit();

                var optimized = try optimizer.optimize(&query);
                defer optimized.deinit();
            }
        }{ .allocator = allocator };

        const result = try benchmark_lib.measureOperationNamedWithSuite(
            allocator,
            "stream_first",
            "Query optimization overhead",
            effective_duration,
            options.warmup,
            context,
            @TypeOf(context).run,
        );
        try results.append(result);
    }

    // Query planning overhead
    {
        const context = struct {
            allocator: std.mem.Allocator,

            pub fn run(ctx: @This()) anyerror!void {
                var store = fact_mod.FactStore.init(ctx.allocator);
                defer store.deinit();

                // Build query
                var builder = query_mod.QueryBuilder.init(ctx.allocator);
                defer builder.deinit();

                _ = builder.selectAll().from(&store);
                _ = try builder.where(.confidence, .gte, 0.5);
                _ = try builder.orderBy(.span_start, .ascending);
                _ = builder.limit(10);

                var query = try builder.build();
                defer query.deinit();

                // Create plan
                var optimizer = query_mod.QueryOptimizer.init(ctx.allocator);
                defer optimizer.deinit();

                var planner = query_mod.QueryPlanner.init(ctx.allocator, &optimizer);
                defer planner.deinit();

                var plan = try planner.createPlan(&query);
                defer plan.deinit();
            }
        }{ .allocator = allocator };

        const result = try benchmark_lib.measureOperationNamedWithSuite(
            allocator,
            "stream_first",
            "Query planning overhead",
            effective_duration,
            options.warmup,
            context,
            @TypeOf(context).run,
        );
        try results.append(result);
    }

    return results.toOwnedSlice();
}

// Main benchmark runner function
pub fn runStreamFirstBenchmarks(allocator: std.mem.Allocator, options: BenchmarkOptions) BenchmarkError![]BenchmarkResult {
    var all_results = std.ArrayList(BenchmarkResult).init(allocator);
    errdefer {
        for (all_results.items) |result| {
            result.deinit(allocator);
        }
        all_results.deinit();
    }

    // Run all sub-benchmarks
    const stream_results = try runStreamBenchmarks(allocator, options);
    defer allocator.free(stream_results);
    try all_results.appendSlice(stream_results);

    const fact_results = try runFactBenchmarks(allocator, options);
    defer allocator.free(fact_results);
    try all_results.appendSlice(fact_results);

    const span_results = try runSpanBenchmarks(allocator, options);
    defer allocator.free(span_results);
    try all_results.appendSlice(span_results);

    const memory_results = try runMemoryBenchmarks(allocator, options);
    defer allocator.free(memory_results);
    try all_results.appendSlice(memory_results);

    const query_results = try runQueryBenchmarks(allocator, options);
    defer allocator.free(query_results);
    try all_results.appendSlice(query_results);

    return all_results.toOwnedSlice();
}
