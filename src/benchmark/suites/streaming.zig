const std = @import("std");
const benchmark_lib = @import("../../lib/benchmark/mod.zig");
const BenchmarkResult = benchmark_lib.BenchmarkResult;
const BenchmarkOptions = benchmark_lib.BenchmarkOptions;
const BenchmarkError = benchmark_lib.BenchmarkError;

// Import streaming lexers for benchmarking
const JsonLexer = @import("../../lib/languages/json/lexer.zig").JsonLexer;
const ZonLexer = @import("../../lib/languages/zon/lexer.zig").ZonLexer;

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
    var lexer = JsonLexer.init(allocator);
    defer lexer.deinit();

    // Generate test JSON with 10KB of nested structures
    const test_json = generateTestJson(allocator, 10 * 1024) catch |err| switch (err) {
        error.OutOfMemory => return BenchmarkError.OutOfMemory,
        else => return BenchmarkError.BenchmarkFailed,
    };
    defer allocator.free(test_json);

    const start_time = std.time.nanoTimestamp();
    var operations: usize = 0;
    const end_time = start_time + @as(i64, @intCast(options.duration_ns));

    while (std.time.nanoTimestamp() < end_time) {
        var stream = lexer.streamTokens(test_json);
        var token_count: usize = 0;

        while (stream.next()) |token| {
            _ = token;
            token_count += 1;
        }

        operations += 1;

        // Reset for next iteration
        lexer.reset();
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
    var lexer = ZonLexer.init(allocator);
    defer lexer.deinit();

    // Generate test ZON with 10KB of struct literals
    const test_zon = generateTestZon(allocator, 10 * 1024) catch |err| switch (err) {
        error.OutOfMemory => return BenchmarkError.OutOfMemory,
        else => return BenchmarkError.BenchmarkFailed,
    };
    defer allocator.free(test_zon);

    const start_time = std.time.nanoTimestamp();
    var operations: usize = 0;
    const end_time = start_time + @as(i64, @intCast(options.duration_ns));

    while (std.time.nanoTimestamp() < end_time) {
        var stream = lexer.streamTokens(test_zon);
        var token_count: usize = 0;

        while (stream.next()) |token| {
            _ = token;
            token_count += 1;
        }

        operations += 1;
        lexer.reset();
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
    const DirectStream = @import("../../lib/stream/direct_stream.zig").DirectStream;
    const Fact = @import("../../lib/fact/fact.zig").Fact;
    const Span = @import("../../lib/span/span.zig").Span;
    _ = @import("../../lib/fact/mod.zig").Predicate; // Import for API reference

    // Create test facts
    var facts = std.ArrayList(Fact).init(allocator);
    defer facts.deinit();

    for (0..1000) |i| {
        try facts.append(Fact{
            .subject = @intCast(i),
            .predicate = .is_token,
            .object = .{ .atom = @intCast(i % 10) },
            .confidence = 0.9,
            .span = Span.init(@intCast(i * 10), @intCast(i * 10 + 5)),
        });
    }

    const start_time = std.time.nanoTimestamp();
    var operations: usize = 0;
    const end_time = start_time + @as(i64, @intCast(options.duration_ns));

    while (std.time.nanoTimestamp() < end_time) {
        var stream = DirectStream.init(facts.items);
        var fact_count: usize = 0;

        while (stream.next()) |fact| {
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
        .extra_info = try std.fmt.allocPrint(allocator, "1000 facts, {d:.1f}M ops/sec", .{@as(f64, @floatFromInt(operations * 1000)) / @as(f64, @floatFromInt(elapsed_ns)) * 1000.0}),
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
