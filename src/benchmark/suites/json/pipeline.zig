const std = @import("std");
const benchmark_lib = @import("../../../lib/benchmark/mod.zig");
const BenchmarkResult = benchmark_lib.BenchmarkResult;
const BenchmarkOptions = benchmark_lib.BenchmarkOptions;
const BenchmarkError = benchmark_lib.BenchmarkError;

// Import JSON components
const json_mod = @import("../../../lib/languages/json/mod.zig");

pub fn runJsonPipelineBenchmarks(allocator: std.mem.Allocator, options: BenchmarkOptions) BenchmarkError![]BenchmarkResult {
    var results = std.ArrayList(BenchmarkResult).init(allocator);
    errdefer {
        for (results.items) |result| {
            result.deinit(allocator);
        }
        results.deinit();
    }

    const effective_duration = @as(u64, @intFromFloat(@as(f64, @floatFromInt(options.duration_ns)) * 2.0 * options.duration_multiplier));

    // Generate test data
    const test_json = try generateJsonData(allocator, 500); // ~10KB
    defer allocator.free(test_json);

    // Complete pipeline: parse → format → validate
    {
        const context = struct {
            allocator: std.mem.Allocator,
            content: []const u8,

            pub fn run(ctx: @This()) anyerror!void {
                // Parse JSON
                var ast = try json_mod.parseJson(ctx.allocator, ctx.content);
                defer ast.deinit();

                // Format JSON
                const formatted = try json_mod.formatJsonString(ctx.allocator, ctx.content);
                defer ctx.allocator.free(formatted);

                // Validate JSON
                const diagnostics = try json_mod.validateJson(ctx.allocator, ctx.content);
                defer {
                    for (diagnostics) |diag| {
                        ctx.allocator.free(diag.message);
                    }
                    ctx.allocator.free(diagnostics);
                }

                std.mem.doNotOptimizeAway(formatted.len);
                std.mem.doNotOptimizeAway(diagnostics.len);
            }
        }{ .allocator = allocator, .content = test_json };

        var result = try benchmark_lib.measureOperation(allocator, effective_duration, options.warmup, context, @TypeOf(context).run);
        allocator.free(result.name);
        result.name = try allocator.dupe(u8, "JSON Complete Pipeline (10KB)");
        try results.append(result);

        // Performance target check: <2ms (2,000,000ns) for 10KB complete pipeline
        if (result.ns_per_op > 2_000_000) {
            std.log.warn("JSON Complete pipeline performance target missed: {}ns > 2,000,000ns for 10KB", .{result.ns_per_op});
        }
    }

    // Parse → Format cycle (round-trip)
    {
        const context = struct {
            allocator: std.mem.Allocator,
            content: []const u8,

            pub fn run(ctx: @This()) anyerror!void {
                // Parse
                var ast = try json_mod.parseJson(ctx.allocator, ctx.content);
                defer ast.deinit();

                // Format back to string
                const formatted = try json_mod.formatJsonString(ctx.allocator, ctx.content);
                defer ctx.allocator.free(formatted);

                // Parse the formatted result (round-trip test)
                var ast2 = try json_mod.parseJson(ctx.allocator, formatted);
                defer ast2.deinit();

                std.mem.doNotOptimizeAway(ast2.root.children.len);
            }
        }{ .allocator = allocator, .content = test_json };

        var result = try benchmark_lib.measureOperation(allocator, effective_duration, options.warmup, context, @TypeOf(context).run);
        allocator.free(result.name);
        result.name = try allocator.dupe(u8, "JSON Round-Trip (10KB)");
        try results.append(result);
    }

    // Schema extraction pipeline
    {
        const context = struct {
            allocator: std.mem.Allocator,
            content: []const u8,

            pub fn run(ctx: @This()) anyerror!void {
                // Extract schema
                var schema = try json_mod.extractJsonSchema(ctx.allocator, ctx.content);
                defer schema.deinit(ctx.allocator);

                // Get statistics
                const stats = try json_mod.getJsonStatistics(ctx.allocator, ctx.content);
                _ = stats;

                std.mem.doNotOptimizeAway(schema.statistics.total_nodes);
            }
        }{ .allocator = allocator, .content = test_json };

        var result = try benchmark_lib.measureOperation(allocator, effective_duration, options.warmup, context, @TypeOf(context).run);
        allocator.free(result.name);
        result.name = try allocator.dupe(u8, "JSON Schema Extraction (10KB)");
        try results.append(result);
    }

    // Minification benchmark
    {
        const pretty_json =
            \\{
            \\  "users": [
            \\    {
            \\      "id": 1,
            \\      "name": "Alice Johnson",
            \\      "email": "alice@example.com",
            \\      "active": true,
            \\      "metadata": {
            \\        "created": "2023-01-15T10:30:00Z",
            \\        "tags": [
            \\          "admin",
            \\          "verified"
            \\        ],
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
            \\        "tags": [
            \\          "user"
            \\        ],
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
                // Parse and reformat as minified
                var ast = try json_mod.parseJson(ctx.allocator, ctx.content);
                defer ast.deinit();

                const minified = try json_mod.formatJsonString(ctx.allocator, ctx.content);
                defer ctx.allocator.free(minified);

                std.mem.doNotOptimizeAway(minified.len);
            }
        }{ .allocator = allocator, .content = pretty_json };

        var result = try benchmark_lib.measureOperation(allocator, effective_duration, options.warmup, context, @TypeOf(context).run);
        allocator.free(result.name);
        result.name = try allocator.dupe(u8, "JSON Minification");
        try results.append(result);
    }

    // Error recovery benchmark
    {
        const invalid_json =
            \\{
            \\  "users": [
            \\    {
            \\      "id": 1,
            \\      "name": "Alice",
            \\      "email": "alice@example.com"
            \\      // Missing comma here
            \\      "active": true
            \\    },
            \\    {
            \\      "id": 2,
            \\      "name": "Bob",
            \\      "email": "bob@example.com",
            \\      "active": false,
            \\      "extra": // trailing comma
            \\    }
            \\  ],
            \\  "total": 2
            \\  // Missing closing brace
        ;

        const context = struct {
            allocator: std.mem.Allocator,
            content: []const u8,

            pub fn run(ctx: @This()) anyerror!void {
                // Try to parse invalid JSON and collect diagnostics
                const diagnostics = try json_mod.validateJson(ctx.allocator, ctx.content);
                defer {
                    for (diagnostics) |diag| {
                        ctx.allocator.free(diag.message);
                    }
                    ctx.allocator.free(diagnostics);
                }

                std.mem.doNotOptimizeAway(diagnostics.len);
            }
        }{ .allocator = allocator, .content = invalid_json };

        var result = try benchmark_lib.measureOperation(allocator, effective_duration, options.warmup, context, @TypeOf(context).run);
        allocator.free(result.name);
        result.name = try allocator.dupe(u8, "JSON Error Recovery");
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
