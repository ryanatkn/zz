const std = @import("std");
const benchmark_lib = @import("../../lib/benchmark/mod.zig");
const BenchmarkResult = benchmark_lib.BenchmarkResult;
const BenchmarkOptions = benchmark_lib.BenchmarkOptions;
const BenchmarkError = benchmark_lib.BenchmarkError;

const json_mod = @import("../../lib/languages/json/mod.zig");
const zon_mod = @import("../../lib/languages/zon/mod.zig");
// Removed old parser imports - using new language modules

pub fn runJsonBenchmarks(allocator: std.mem.Allocator, options: BenchmarkOptions) BenchmarkError![]BenchmarkResult {
    var results = std.ArrayList(BenchmarkResult).init(allocator);
    errdefer {
        for (results.items) |result| {
            result.deinit(allocator);
        }
        results.deinit();
    }

    const effective_duration = @as(u64, @intFromFloat(@as(f64, @floatFromInt(options.duration_ns)) * 1.5 * options.duration_multiplier));

    // JSON text processing benchmark
    {
        const json_text =
            \\{
            \\  "users": [
            \\    {"id": 1, "name": "Alice", "active": true},
            \\    {"id": 2, "name": "Bob", "active": false}
            \\  ]
            \\}
        ;

        const context = struct {
            allocator: std.mem.Allocator,
            text: []const u8,

            pub fn run(ctx: @This()) anyerror!void {
                // Simple JSON text analysis
                var brace_count: u32 = 0;
                var quote_count: u32 = 0;
                for (ctx.text) |ch| {
                    if (ch == '{' or ch == '}') brace_count += 1;
                    if (ch == '"') quote_count += 1;
                }
                std.mem.doNotOptimizeAway(brace_count);
                std.mem.doNotOptimizeAway(quote_count);

                // String operations
                _ = std.mem.count(u8, ctx.text, "\"");
                _ = std.mem.indexOf(u8, ctx.text, "users");
            }
        }{ .allocator = allocator, .text = json_text };

        const result = try benchmark_lib.measureOperationNamedWithSuite(allocator, "json", "JSON Text Analysis", effective_duration, options.warmup, context, @TypeOf(context).run);
        try results.append(result);
    }

    return results.toOwnedSlice();
}

pub fn runZonBenchmarks(allocator: std.mem.Allocator, options: BenchmarkOptions) BenchmarkError![]BenchmarkResult {
    var results = std.ArrayList(BenchmarkResult).init(allocator);
    errdefer {
        for (results.items) |result| {
            result.deinit(allocator);
        }
        results.deinit();
    }

    const effective_duration = @as(u64, @intFromFloat(@as(f64, @floatFromInt(options.duration_ns)) * 1.5 * options.duration_multiplier));

    // ZON text analysis benchmark
    {
        const zon_text =
            \\.{
            \\    .name = "zz",
            \\    .version = "0.1.0"
            \\}
        ;

        const context = struct {
            text: []const u8,

            pub fn run(ctx: @This()) anyerror!void {
                // Simple ZON text analysis
                var dot_count: u32 = 0;
                var brace_count: u32 = 0;
                for (ctx.text) |ch| {
                    if (ch == '.') dot_count += 1;
                    if (ch == '{' or ch == '}') brace_count += 1;
                }
                std.mem.doNotOptimizeAway(dot_count);
                std.mem.doNotOptimizeAway(brace_count);

                // String operations
                _ = std.mem.indexOf(u8, ctx.text, "name");
                _ = std.mem.indexOf(u8, ctx.text, "version");
            }
        }{ .text = zon_text };

        const result = try benchmark_lib.measureOperationNamedWithSuite(allocator, "zon", "ZON Text Analysis", effective_duration, options.warmup, context, @TypeOf(context).run);
        try results.append(result);
    }

    return results.toOwnedSlice();
}

pub fn runParserBenchmarks(allocator: std.mem.Allocator, options: BenchmarkOptions) BenchmarkError![]BenchmarkResult {
    var results = std.ArrayList(BenchmarkResult).init(allocator);
    errdefer {
        for (results.items) |result| {
            result.deinit(allocator);
        }
        results.deinit();
    }

    const effective_duration = @as(u64, @intFromFloat(@as(f64, @floatFromInt(options.duration_ns)) * 1.5 * options.duration_multiplier));

    // Code text analysis benchmark
    {
        const code_text =
            \\fn main() !void {
            \\    const x = 42;
            \\    std.debug.print("Hello, World!\n", .{});
            \\}
        ;

        const context = struct {
            text: []const u8,

            pub fn run(ctx: @This()) anyerror!void {
                // Simple code analysis
                var keyword_count: u32 = 0;
                var paren_count: u32 = 0;
                for (ctx.text) |ch| {
                    if (ch == '(' or ch == ')') paren_count += 1;
                }
                std.mem.doNotOptimizeAway(paren_count);

                // Count keywords
                keyword_count += @intCast(std.mem.count(u8, ctx.text, "fn"));
                keyword_count += @intCast(std.mem.count(u8, ctx.text, "const"));
                std.mem.doNotOptimizeAway(keyword_count);

                // String operations
                _ = std.mem.indexOf(u8, ctx.text, "main");
                _ = std.mem.indexOf(u8, ctx.text, "void");
            }
        }{ .text = code_text };

        const result = try benchmark_lib.measureOperationNamedWithSuite(allocator, "parser", "Code Text Analysis", effective_duration, options.warmup, context, @TypeOf(context).run);
        try results.append(result);
    }

    return results.toOwnedSlice();
}
