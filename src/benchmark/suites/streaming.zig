const std = @import("std");
const benchmark_lib = @import("../../lib/benchmark/mod.zig");
const BenchmarkResult = benchmark_lib.BenchmarkResult;
const BenchmarkOptions = benchmark_lib.BenchmarkOptions;
const BenchmarkError = benchmark_lib.BenchmarkError;

// Import streaming lexers for benchmarking
const JsonLexer = @import("../../lib/languages/json/lexer/mod.zig").Lexer;
const ZonLexer = @import("../../lib/languages/zon/stream_lexer.zig").ZonLexer;

// Import fact system for DirectStream benchmark
const Fact = @import("../../lib/fact/fact.zig").Fact;
const span_mod = @import("../../lib/span/packed.zig");
const PackedSpan = span_mod.PackedSpan;
const packSpan = span_mod.packSpan;
const Span = span_mod.Span;

pub fn runStreamingBenchmarks(allocator: std.mem.Allocator, options: BenchmarkOptions) BenchmarkError![]BenchmarkResult {
    var results = std.ArrayList(BenchmarkResult).init(allocator);
    defer results.deinit();

    // JSON lexer streaming benchmark
    try results.append(try benchmarkJsonLexerStreaming(allocator, options));

    // ZON lexer streaming benchmark
    try results.append(try benchmarkZonLexerStreaming(allocator, options));

    // DirectStream fact processing benchmark
    try results.append(try benchmarkDirectStreamProcessing(allocator, options));

    return results.toOwnedSlice();
}

/// Benchmark JSON lexer streaming performance
fn benchmarkJsonLexerStreaming(allocator: std.mem.Allocator, options: BenchmarkOptions) !BenchmarkResult {
    // Generate test JSON with 10KB of nested structures
    const test_json = generateTestJson(allocator, 10 * 1024) catch |err| switch (err) {
        error.OutOfMemory => return BenchmarkError.OutOfMemory,
    };
    defer allocator.free(test_json);

    const start_time = std.time.nanoTimestamp();
    var operations: usize = 0;
    const end_time = start_time + @as(i64, @intCast(options.duration_ns));

    while (std.time.nanoTimestamp() < end_time) {
        // Create new lexer for each iteration (simulates fresh parsing)
        var lexer = JsonLexer.init(test_json);
        var token_count: usize = 0;

        while (lexer.next()) |token| {
            _ = token;
            token_count += 1;
        }

        operations += 1;
    }

    const elapsed_ns: u64 = @intCast(std.time.nanoTimestamp() - start_time);
    const ns_per_op = if (operations > 0) @divTrunc(elapsed_ns, operations) else elapsed_ns;

    return BenchmarkResult{
        .name = "JSON lexer streaming",
        .total_operations = operations,
        .elapsed_ns = elapsed_ns,
        .ns_per_op = ns_per_op,
        .confidence = if (operations >= 1000) .high else if (operations >= 100) .medium else if (operations >= 10) .low else .insufficient,
        .extra_info = try std.fmt.allocPrint(allocator, "{d} KB input, ~3000 tokens", .{test_json.len / 1024}),
    };
}

/// Benchmark ZON lexer streaming performance
fn benchmarkZonLexerStreaming(allocator: std.mem.Allocator, options: BenchmarkOptions) !BenchmarkResult {
    // Generate test ZON with 10KB of struct literals
    const test_zon = generateTestZon(allocator, 10 * 1024) catch |err| switch (err) {
        error.OutOfMemory => return BenchmarkError.OutOfMemory,
    };
    defer allocator.free(test_zon);

    const start_time = std.time.nanoTimestamp();
    var operations: usize = 0;
    const end_time = start_time + @as(i64, @intCast(options.duration_ns));

    while (std.time.nanoTimestamp() < end_time) {
        // Create new lexer for each iteration
        var lexer = ZonLexer.init(test_zon);
        var token_count: usize = 0;

        while (lexer.next()) |token| {
            _ = token;
            token_count += 1;
        }

        operations += 1;
    }

    const elapsed_ns: u64 = @intCast(std.time.nanoTimestamp() - start_time);
    const ns_per_op = if (operations > 0) @divTrunc(elapsed_ns, operations) else elapsed_ns;

    return BenchmarkResult{
        .name = "ZON lexer streaming",
        .total_operations = operations,
        .elapsed_ns = elapsed_ns,
        .ns_per_op = ns_per_op,
        .confidence = if (operations >= 1000) .high else if (operations >= 100) .medium else if (operations >= 10) .low else .insufficient,
        .extra_info = try std.fmt.allocPrint(allocator, "{d} KB input, ~2800 tokens", .{test_zon.len / 1024}),
    };
}

/// Benchmark DirectStream fact processing
fn benchmarkDirectStreamProcessing(allocator: std.mem.Allocator, options: BenchmarkOptions) !BenchmarkResult {
    const direct_stream = @import("../../lib/stream/direct_stream.zig");

    // Create test facts
    var facts = std.ArrayList(Fact).init(allocator);
    defer facts.deinit();

    for (0..1000) |i| {
        try facts.append(Fact{
            .id = @intCast(i + 1), // Fact IDs start from 1
            .subject = packSpan(Span.init(@intCast(i * 10), @intCast(i * 10 + 5))),
            .predicate = .is_token,
            .object = .{ .uint = @intCast(i % 10) },
            .confidence = 0.9,
        });
    }

    const start_time = std.time.nanoTimestamp();
    var operations: usize = 0;
    const end_time = start_time + @as(i64, @intCast(options.duration_ns));

    while (std.time.nanoTimestamp() < end_time) {
        var stream = direct_stream.fromSlice(Fact, facts.items);
        var fact_count: usize = 0;

        while (stream.next() catch null) |fact| {
            _ = fact;
            fact_count += 1;
        }

        operations += 1;
    }

    const elapsed_ns: u64 = @intCast(std.time.nanoTimestamp() - start_time);
    const ns_per_op = if (operations > 0) @divTrunc(elapsed_ns, operations) else elapsed_ns;

    return BenchmarkResult{
        .name = "DirectStream processing",
        .total_operations = operations,
        .elapsed_ns = elapsed_ns,
        .ns_per_op = ns_per_op,
        .confidence = if (operations >= 1000) .high else if (operations >= 100) .medium else if (operations >= 10) .low else .insufficient,
        .extra_info = try std.fmt.allocPrint(allocator, "1000 facts, {d:.1}M ops/sec", .{@as(f64, @floatFromInt(operations * 1000)) / @as(f64, @floatFromInt(elapsed_ns)) * 1000.0}),
    };
}

/// Generate test JSON data of approximately target_size bytes
fn generateTestJson(allocator: std.mem.Allocator, target_size: usize) ![]u8 {
    var json = std.ArrayList(u8).init(allocator);
    defer json.deinit();

    try json.appendSlice("{\n  \"users\": [\n");

    var size: usize = 0;
    var i: usize = 0;
    while (size < target_size and i < 1000) {
        if (i > 0) try json.appendSlice(",\n");

        const user_entry = try std.fmt.allocPrint(allocator,
            \\    {{
            \\      "id": {d},
            \\      "name": "User{d}",
            \\      "email": "user{d}@example.com",
            \\      "active": {},
            \\      "score": {d}.{d},
            \\      "tags": ["tag1", "tag2", "tag3"]
            \\    }}
        , .{ i, i, i, i % 2 == 0, i * 100, i % 100 });
        defer allocator.free(user_entry);

        try json.appendSlice(user_entry);
        size = json.items.len;
        i += 1;
    }

    try json.appendSlice("\n  ]\n}");
    return json.toOwnedSlice();
}

/// Generate test ZON data of approximately target_size bytes
fn generateTestZon(allocator: std.mem.Allocator, target_size: usize) ![]u8 {
    var zon = std.ArrayList(u8).init(allocator);
    defer zon.deinit();

    try zon.appendSlice(".{\n  .dependencies = .{\n");

    var size: usize = 0;
    var i: usize = 0;
    while (size < target_size and i < 1000) {
        if (i > 0) try zon.appendSlice(",\n");

        const dep_entry = try std.fmt.allocPrint(allocator,
            \\    .dep{d} = .{{
            \\      .url = "https://github.com/user/dep{d}",
            \\      .hash = "hash{d}",
            \\      .lazy = {}
            \\    }}
        , .{ i, i, i, i % 2 == 0 });
        defer allocator.free(dep_entry);

        try zon.appendSlice(dep_entry);
        size = zon.items.len;
        i += 1;
    }

    try zon.appendSlice("\n  }\n}");
    return zon.toOwnedSlice();
}
