const std = @import("std");
const benchmark_lib = @import("../../../lib/benchmark/mod.zig");
const BenchmarkResult = benchmark_lib.BenchmarkResult;
const BenchmarkOptions = benchmark_lib.BenchmarkOptions;
const BenchmarkError = benchmark_lib.BenchmarkError;

// Import JSON components
const JsonLexer = @import("../../../lib/languages/json/lexer.zig").JsonLexer;
const JsonParser = @import("../../../lib/languages/json/parser.zig").JsonParser;
const Token = @import("../../../lib/parser/foundation/types/token.zig").Token;

pub fn runJsonParserBenchmarks(allocator: std.mem.Allocator, options: BenchmarkOptions) BenchmarkError![]BenchmarkResult {
    var results = std.ArrayList(BenchmarkResult).init(allocator);
    errdefer {
        for (results.items) |result| {
            result.deinit(allocator);
        }
        results.deinit();
    }

    const effective_duration = @as(u64, @intFromFloat(@as(f64, @floatFromInt(options.duration_ns)) * 1.5 * options.duration_multiplier));

    // Generate test data (similar to lexer benchmarks but focus on parsing)
    const small_json = try generateJsonData(allocator, 50); // ~1KB
    defer allocator.free(small_json);

    const medium_json = try generateJsonData(allocator, 500); // ~10KB
    defer allocator.free(medium_json);

    const large_json = try generateJsonData(allocator, 2000); // ~40KB (reasonable for parsing)
    defer allocator.free(large_json);

    // Parser benchmark for small JSON (1KB)
    {
        const context = struct {
            allocator: std.mem.Allocator,
            content: []const u8,

            pub fn run(ctx: @This()) anyerror!void {
                // Pre-tokenize
                var lexer = JsonLexer.init(ctx.allocator, ctx.content, .{});
                defer lexer.deinit();
                const tokens = try lexer.tokenize();
                defer ctx.allocator.free(tokens);

                // Parse tokens
                var parser = JsonParser.init(ctx.allocator, tokens, .{});
                defer parser.deinit();

                var ast = try parser.parse();
                defer ast.deinit();

                std.mem.doNotOptimizeAway(ast.root.children.len);
            }
        }{ .allocator = allocator, .content = small_json };

        var result = try benchmark_lib.measureOperation(allocator, effective_duration, options.warmup, context, @TypeOf(context).run);
        allocator.free(result.name);
        result.name = try allocator.dupe(u8, "JSON Parser Small (1KB)");
        try results.append(result);
    }

    // Parser benchmark for medium JSON (10KB) - Performance target
    {
        const context = struct {
            allocator: std.mem.Allocator,
            content: []const u8,

            pub fn run(ctx: @This()) anyerror!void {
                // Pre-tokenize
                var lexer = JsonLexer.init(ctx.allocator, ctx.content, .{});
                defer lexer.deinit();
                const tokens = try lexer.tokenize();
                defer ctx.allocator.free(tokens);

                // Parse tokens
                var parser = JsonParser.init(ctx.allocator, tokens, .{});
                defer parser.deinit();

                var ast = try parser.parse();
                defer ast.deinit();

                std.mem.doNotOptimizeAway(ast.root.children.len);
            }
        }{ .allocator = allocator, .content = medium_json };

        var result = try benchmark_lib.measureOperation(allocator, effective_duration, options.warmup, context, @TypeOf(context).run);
        allocator.free(result.name);
        result.name = try allocator.dupe(u8, "JSON Parser Medium (10KB)");
        try results.append(result);

        // Performance target check: <1ms (1,000,000ns) for 10KB
        if (result.ns_per_op > 1_000_000) {
            std.log.warn("JSON Parser performance target missed: {}ns > 1,000,000ns for 10KB", .{result.ns_per_op});
        }
    }

    // Parser benchmark for large JSON (40KB)
    {
        const context = struct {
            allocator: std.mem.Allocator,
            content: []const u8,

            pub fn run(ctx: @This()) anyerror!void {
                // Pre-tokenize
                var lexer = JsonLexer.init(ctx.allocator, ctx.content, .{});
                defer lexer.deinit();
                const tokens = try lexer.tokenize();
                defer ctx.allocator.free(tokens);

                // Parse tokens
                var parser = JsonParser.init(ctx.allocator, tokens, .{});
                defer parser.deinit();

                var ast = try parser.parse();
                defer ast.deinit();

                std.mem.doNotOptimizeAway(ast.root.children.len);
            }
        }{ .allocator = allocator, .content = large_json };

        var result = try benchmark_lib.measureOperation(allocator, effective_duration, options.warmup, context, @TypeOf(context).run);
        allocator.free(result.name);
        result.name = try allocator.dupe(u8, "JSON Parser Large (40KB)");
        try results.append(result);
    }

    // Parse-only benchmark (tokens pre-provided)
    {
        // Pre-tokenize the medium JSON once
        var lexer = JsonLexer.init(allocator, medium_json, .{});
        defer lexer.deinit();
        const tokens = try lexer.tokenize();
        defer allocator.free(tokens);

        const context = struct {
            allocator: std.mem.Allocator,
            tokens: []const Token,

            pub fn run(ctx: @This()) anyerror!void {
                var parser = JsonParser.init(ctx.allocator, ctx.tokens, .{});
                defer parser.deinit();

                var ast = try parser.parse();
                defer ast.deinit();

                std.mem.doNotOptimizeAway(ast.root.children.len);
            }
        }{ .allocator = allocator, .tokens = tokens };

        var result = try benchmark_lib.measureOperation(allocator, effective_duration, options.warmup, context, @TypeOf(context).run);
        allocator.free(result.name);
        result.name = try allocator.dupe(u8, "JSON Parser Only (10KB)");
        try results.append(result);
    }

    // Nested structure parsing
    {
        const nested_json =
            \\{
            \\  "level1": {
            \\    "level2": {
            \\      "level3": {
            \\        "level4": {
            \\          "deep_array": [
            \\            {"item": 1, "nested": {"value": true}},
            \\            {"item": 2, "nested": {"value": false}},
            \\            {"item": 3, "nested": {"value": null}}
            \\          ],
            \\          "deep_object": {
            \\            "a": {"b": {"c": {"d": "deep_value"}}},
            \\            "x": {"y": {"z": [1, 2, 3, 4, 5]}}
            \\          }
            \\        }
            \\      }
            \\    }
            \\  }
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

                var parser = JsonParser.init(ctx.allocator, tokens, .{});
                defer parser.deinit();

                var ast = try parser.parse();
                defer ast.deinit();

                std.mem.doNotOptimizeAway(ast.root.children.len);
            }
        }{ .allocator = allocator, .content = nested_json };

        var result = try benchmark_lib.measureOperation(allocator, effective_duration, options.warmup, context, @TypeOf(context).run);
        allocator.free(result.name);
        result.name = try allocator.dupe(u8, "JSON Parser Nested");
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
