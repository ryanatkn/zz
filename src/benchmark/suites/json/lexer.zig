const std = @import("std");
const benchmark_lib = @import("../../../lib/benchmark/mod.zig");
const BenchmarkResult = benchmark_lib.BenchmarkResult;
const BenchmarkOptions = benchmark_lib.BenchmarkOptions;
const BenchmarkError = benchmark_lib.BenchmarkError;

// Import streaming JSON components
const JsonStreamLexer = @import("../../../lib/languages/json/lexer/mod.zig").StreamLexer;
const StreamToken = @import("../../../lib/token/stream_token.zig").StreamToken;
const TokenIterator = @import("../../../lib/token/iterator.zig").TokenIterator;
const Language = @import("../../../lib/core/language.zig").Language;

pub fn runJsonLexerBenchmarks(allocator: std.mem.Allocator, options: BenchmarkOptions) BenchmarkError![]BenchmarkResult {
    var results = std.ArrayList(BenchmarkResult).init(allocator);
    errdefer {
        for (results.items) |result| {
            result.deinit(allocator);
        }
        results.deinit();
    }

    const effective_duration = @as(u64, @intFromFloat(@as(f64, @floatFromInt(options.duration_ns)) * 1.5 * options.duration_multiplier));

    // Generate test data (each item is ~200 bytes)
    const small_json = try generateJsonData(allocator, 5); // ~1KB
    defer allocator.free(small_json);

    const medium_json = try generateJsonData(allocator, 50); // ~10KB
    defer allocator.free(medium_json);

    const large_json = try generateJsonData(allocator, 500); // ~100KB
    defer allocator.free(large_json);

    // Streaming lexer benchmark for small JSON (1KB)
    {
        const context = struct {
            content: []const u8,

            pub fn run(ctx: @This()) anyerror!void {
                // Use streaming lexer directly
                var lexer = JsonStreamLexer.init(ctx.content);

                // Iterate through all tokens
                var token_count: usize = 0;
                while (lexer.next()) |token| {
                    token_count += 1;
                    // Access token to prevent optimization
                    switch (token) {
                        .json => |t| std.mem.doNotOptimizeAway(t.kind),
                        else => {},
                    }
                }

                // Prevent optimization
                std.mem.doNotOptimizeAway(token_count);
            }
        }{ .content = small_json };

        var result = try benchmark_lib.measureOperation(allocator, effective_duration, options.warmup, context, @TypeOf(context).run);
        allocator.free(result.name);
        result.name = try allocator.dupe(u8, "JSON Streaming Lexer Small (1KB)");
        try results.append(result);
    }

    // Streaming lexer benchmark for medium JSON (10KB) - Performance target
    {
        const context = struct {
            content: []const u8,

            pub fn run(ctx: @This()) anyerror!void {
                // Use streaming lexer directly
                var lexer = JsonStreamLexer.init(ctx.content);

                // Iterate through all tokens
                var token_count: usize = 0;
                while (lexer.next()) |token| {
                    token_count += 1;
                    // Access token to prevent optimization
                    switch (token) {
                        .json => |t| std.mem.doNotOptimizeAway(t.kind),
                        else => {},
                    }
                }

                std.mem.doNotOptimizeAway(token_count);
            }
        }{ .content = medium_json };

        var result = try benchmark_lib.measureOperation(allocator, effective_duration, options.warmup, context, @TypeOf(context).run);
        allocator.free(result.name);
        result.name = try allocator.dupe(u8, "JSON Streaming Lexer Medium (10KB)");
        try results.append(result);

        // Performance target check: <0.1ms (100,000ns) for 10KB
        // Streaming should be faster than batch
        if (result.ns_per_op > 100_000) {
            std.log.warn("JSON Streaming Lexer performance target missed: {}ns > 100,000ns for 10KB", .{result.ns_per_op});
        }
    }

    // Streaming lexer benchmark for large JSON (100KB)
    {
        const context = struct {
            content: []const u8,

            pub fn run(ctx: @This()) anyerror!void {
                // Use streaming lexer directly
                var lexer = JsonStreamLexer.init(ctx.content);

                // Iterate through all tokens
                var token_count: usize = 0;
                while (lexer.next()) |token| {
                    token_count += 1;
                    // Access token to prevent optimization
                    switch (token) {
                        .json => |t| std.mem.doNotOptimizeAway(t.kind),
                        else => {},
                    }
                }

                std.mem.doNotOptimizeAway(token_count);
            }
        }{ .content = large_json };

        var result = try benchmark_lib.measureOperation(allocator, effective_duration, options.warmup, context, @TypeOf(context).run);
        allocator.free(result.name);
        result.name = try allocator.dupe(u8, "JSON Streaming Lexer Large (100KB)");
        try results.append(result);
    }

    // Real-world JSON patterns with TokenIterator
    {
        const real_world_json =
            \\{
            \\  "users": [
            \\    {
            \\      "id": 1,
            \\      "name": "Alice Johnson",
            \\      "email": "alice@example.com",
            \\      "active": true,
            \\      "metadata": {
            \\        "created": "2023-01-15T10:30:00Z",
            \\        "tags": ["admin", "verified"],
            \\        "score": 95.7
            \\      }
            \\    },
            \\    {
            \\      "id": 2,
            \\      "name": "Bob Smith",
            \\      "email": "bob@example.com", 
            \\      "active": false,
            \\      "metadata": {
            \\        "created": "2023-01-20T14:45:30Z",
            \\        "tags": ["user"],
            \\        "score": 72.3
            \\      }
            \\    }
            \\  ],
            \\  "total": 2,
            \\  "timestamp": "2023-08-18T12:00:00Z"
            \\}
        ;

        const context = struct {
            content: []const u8,

            pub fn run(ctx: @This()) anyerror!void {
                // Use TokenIterator for generic interface
                var iterator = try TokenIterator.init(ctx.content, .json);

                // Iterate through all tokens
                var token_count: usize = 0;
                while (iterator.next()) |token| {
                    token_count += 1;
                    // Access token to prevent optimization
                    switch (token) {
                        .json => |t| std.mem.doNotOptimizeAway(t.kind),
                        else => {},
                    }
                }

                std.mem.doNotOptimizeAway(token_count);
            }
        }{ .content = real_world_json };

        var result = try benchmark_lib.measureOperation(allocator, effective_duration, options.warmup, context, @TypeOf(context).run);
        allocator.free(result.name);
        result.name = try allocator.dupe(u8, "JSON Streaming Lexer Real-World");
        try results.append(result);
    }

    return results.toOwnedSlice();
}

fn generateJsonData(allocator: std.mem.Allocator, num_items: u32) ![]u8 {
    var json = std.ArrayList(u8).init(allocator);
    errdefer json.deinit();

    try json.appendSlice("{\n  \"users\": [\n");

    for (0..num_items) |i| {
        if (i > 0) try json.appendSlice(",\n");

        try json.writer().print(
            \\    {{
            \\      "id": {},
            \\      "name": "User {}",
            \\      "email": "user{}@example.com",
            \\      "age": {},
            \\      "active": {},
            \\      "metadata": {{
            \\        "created": "2023-01-{}",
            \\        "tags": ["tag{}", "tag{}"],
            \\        "score": {}.{}
            \\      }}
            \\    }}
        , .{
            i,
            i,
            i,
            20 + (i % 50),
            i % 2 == 0,
            1 + (i % 28),
            i % 10,
            (i + 1) % 10,
            i % 100,
            i % 100,
        });
    }

    try json.appendSlice("\n  ],\n");
    try json.writer().print("  \"count\": {},\n", .{num_items});
    try json.appendSlice("  \"timestamp\": \"2023-01-01T00:00:00Z\"\n}");

    return json.toOwnedSlice();
}
