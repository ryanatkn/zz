const std = @import("std");
const benchmark_lib = @import("../../../lib/benchmark/mod.zig");
const BenchmarkResult = benchmark_lib.BenchmarkResult;
const BenchmarkOptions = benchmark_lib.BenchmarkOptions;
const BenchmarkError = benchmark_lib.BenchmarkError;

// Import JSON components
const JsonLexer = @import("../../../lib/languages/json/lexer.zig").JsonLexer;

pub fn runJsonLexerBenchmarks(allocator: std.mem.Allocator, options: BenchmarkOptions) BenchmarkError![]BenchmarkResult {
    var results = std.ArrayList(BenchmarkResult).init(allocator);
    errdefer {
        for (results.items) |result| {
            result.deinit(allocator);
        }
        results.deinit();
    }

    const effective_duration = @as(u64, @intFromFloat(@as(f64, @floatFromInt(options.duration_ns)) * 1.5 * options.duration_multiplier));

    // Generate test data
    const small_json = try generateJsonData(allocator, 50); // ~1KB
    defer allocator.free(small_json);

    const medium_json = try generateJsonData(allocator, 500); // ~10KB
    defer allocator.free(medium_json);

    const large_json = try generateJsonData(allocator, 5000); // ~100KB
    defer allocator.free(large_json);

    // Lexer benchmark for small JSON (1KB)
    {
        const context = struct {
            allocator: std.mem.Allocator,
            content: []const u8,

            pub fn run(ctx: @This()) anyerror!void {
                var lexer = JsonLexer.init(ctx.allocator, ctx.content, .{});
                defer lexer.deinit();

                const tokens = try lexer.tokenize();
                defer ctx.allocator.free(tokens);

                // Prevent optimization
                std.mem.doNotOptimizeAway(tokens.len);
            }
        }{ .allocator = allocator, .content = small_json };

        var result = try benchmark_lib.measureOperation(allocator, effective_duration, options.warmup, context, @TypeOf(context).run);
        allocator.free(result.name);
        result.name = try allocator.dupe(u8, "JSON Lexer Small (1KB)");
        try results.append(result);
    }

    // Lexer benchmark for medium JSON (10KB) - Performance target
    {
        const context = struct {
            allocator: std.mem.Allocator,
            content: []const u8,

            pub fn run(ctx: @This()) anyerror!void {
                var lexer = JsonLexer.init(ctx.allocator, ctx.content, .{});
                defer lexer.deinit();

                const tokens = try lexer.tokenize();
                defer ctx.allocator.free(tokens);

                std.mem.doNotOptimizeAway(tokens.len);
            }
        }{ .allocator = allocator, .content = medium_json };

        var result = try benchmark_lib.measureOperation(allocator, effective_duration, options.warmup, context, @TypeOf(context).run);
        allocator.free(result.name);
        result.name = try allocator.dupe(u8, "JSON Lexer Medium (10KB)");
        try results.append(result);

        // Performance target check: <0.1ms (100,000ns) for 10KB
        if (result.ns_per_op > 100_000) {
            std.log.warn("JSON Lexer performance target missed: {}ns > 100,000ns for 10KB", .{result.ns_per_op});
        }
    }

    // Lexer benchmark for large JSON (100KB)
    {
        const context = struct {
            allocator: std.mem.Allocator,
            content: []const u8,

            pub fn run(ctx: @This()) anyerror!void {
                var lexer = JsonLexer.init(ctx.allocator, ctx.content, .{});
                defer lexer.deinit();

                const tokens = try lexer.tokenize();
                defer ctx.allocator.free(tokens);

                std.mem.doNotOptimizeAway(tokens.len);
            }
        }{ .allocator = allocator, .content = large_json };

        var result = try benchmark_lib.measureOperation(allocator, effective_duration, options.warmup, context, @TypeOf(context).run);
        allocator.free(result.name);
        result.name = try allocator.dupe(u8, "JSON Lexer Large (100KB)");
        try results.append(result);
    }

    // Real-world JSON patterns
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
            allocator: std.mem.Allocator,
            content: []const u8,

            pub fn run(ctx: @This()) anyerror!void {
                var lexer = JsonLexer.init(ctx.allocator, ctx.content, .{});
                defer lexer.deinit();

                const tokens = try lexer.tokenize();
                defer ctx.allocator.free(tokens);

                std.mem.doNotOptimizeAway(tokens.len);
            }
        }{ .allocator = allocator, .content = real_world_json };

        var result = try benchmark_lib.measureOperation(allocator, effective_duration, options.warmup, context, @TypeOf(context).run);
        allocator.free(result.name);
        result.name = try allocator.dupe(u8, "JSON Lexer Real-World");
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
