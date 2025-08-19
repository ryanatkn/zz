const std = @import("std");
const benchmark_lib = @import("../../lib/benchmark/mod.zig");
const BenchmarkResult = benchmark_lib.BenchmarkResult;
const BenchmarkOptions = benchmark_lib.BenchmarkOptions;
const BenchmarkError = benchmark_lib.BenchmarkError;

// Import core modules to benchmark
const path_mod = @import("../../lib/core/path.zig");
const memory_mod = @import("../../lib/memory/pools.zig");
const patterns_mod = @import("../../lib/patterns/glob.zig");
const text_mod = @import("../../lib/text/processing.zig");
const char_mod = @import("../../lib/char/mod.zig");

pub fn runPathBenchmarks(allocator: std.mem.Allocator, options: BenchmarkOptions) BenchmarkError![]BenchmarkResult {
    var results = std.ArrayList(BenchmarkResult).init(allocator);
    errdefer {
        for (results.items) |result| {
            result.deinit(allocator);
        }
        results.deinit();
    }

    const effective_duration = @as(u64, @intFromFloat(@as(f64, @floatFromInt(options.duration_ns)) * 2.0 * options.duration_multiplier));

    // Path joining benchmark
    {
        const context = struct {
            allocator: std.mem.Allocator,

            pub fn run(ctx: @This()) anyerror!void {
                const result = try path_mod.joinPaths(ctx.allocator, &.{ "src", "lib", "core", "path.zig" });
                ctx.allocator.free(result);
            }
        }{ .allocator = allocator };

        const result = try benchmark_lib.measureOperationNamedWithSuite(allocator, "path", "Path Joining", effective_duration, options.warmup, context, @TypeOf(context).run);
        try results.append(result);
    }

    // Simple path operation benchmark
    {
        const context = struct {
            pub fn run(_: @This()) anyerror!void {
                _ = path_mod.isHiddenFile(".gitignore");
                _ = path_mod.isHiddenFile("README.md");
                _ = path_mod.patternMatchesHidden(".*");
                _ = path_mod.patternMatchesHidden("*.txt");
            }
        }{};

        const result = try benchmark_lib.measureOperationNamedWithSuite(allocator, "path", "Path Utilities", effective_duration, options.warmup, context, @TypeOf(context).run);
        try results.append(result);
    }

    return results.toOwnedSlice();
}

pub fn runMemoryBenchmarks(allocator: std.mem.Allocator, options: BenchmarkOptions) BenchmarkError![]BenchmarkResult {
    var results = std.ArrayList(BenchmarkResult).init(allocator);
    errdefer {
        for (results.items) |result| {
            result.deinit(allocator);
        }
        results.deinit();
    }

    const effective_duration = @as(u64, @intFromFloat(@as(f64, @floatFromInt(options.duration_ns)) * 3.0 * options.duration_multiplier));

    // ArrayList allocation benchmark
    {
        const context = struct {
            allocator: std.mem.Allocator,

            pub fn run(ctx: @This()) anyerror!void {
                var list = std.ArrayList(u8).init(ctx.allocator);
                defer list.deinit();

                try list.appendSlice("hello world test data");
                try list.append('!');
                _ = list.pop();
            }
        }{ .allocator = allocator };

        const result = try benchmark_lib.measureOperationNamedWithSuite(allocator, "memory", "ArrayList Operations", effective_duration, options.warmup, context, @TypeOf(context).run);
        try results.append(result);
    }

    // String operations benchmark
    {
        const context = struct {
            allocator: std.mem.Allocator,

            pub fn run(ctx: @This()) anyerror!void {
                var string_map = std.HashMap([]const u8, void, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(ctx.allocator);
                defer string_map.deinit();

                const key = try ctx.allocator.dupe(u8, "test_string_key");
                defer ctx.allocator.free(key);

                try string_map.put(key, {});
                _ = string_map.get(key);
            }
        }{ .allocator = allocator };

        const result = try benchmark_lib.measureOperationNamedWithSuite(allocator, "memory", "HashMap Operations", effective_duration, options.warmup, context, @TypeOf(context).run);
        try results.append(result);
    }

    return results.toOwnedSlice();
}

pub fn runPatternBenchmarks(allocator: std.mem.Allocator, options: BenchmarkOptions) BenchmarkError![]BenchmarkResult {
    var results = std.ArrayList(BenchmarkResult).init(allocator);
    errdefer {
        for (results.items) |result| {
            result.deinit(allocator);
        }
        results.deinit();
    }

    const effective_duration = @as(u64, @intFromFloat(@as(f64, @floatFromInt(options.duration_ns)) * 2.0 * options.duration_multiplier));

    // String pattern matching benchmark
    {
        const context = struct {
            pub fn run(_: @This()) anyerror!void {
                const patterns = [_][]const u8{ "*.zig", "src/**", "*.json" };
                const files = [_][]const u8{ "main.zig", "src/lib/test.zig", "config.json", "README.md" };

                for (patterns) |pattern| {
                    for (files) |file| {
                        _ = std.mem.endsWith(u8, file, pattern[1..]);
                    }
                }
            }
        }{};

        const result = try benchmark_lib.measureOperationNamedWithSuite(allocator, "patterns", "Pattern Matching", effective_duration, options.warmup, context, @TypeOf(context).run);
        try results.append(result);
    }

    return results.toOwnedSlice();
}

pub fn runTextBenchmarks(allocator: std.mem.Allocator, options: BenchmarkOptions) BenchmarkError![]BenchmarkResult {
    var results = std.ArrayList(BenchmarkResult).init(allocator);
    errdefer {
        for (results.items) |result| {
            result.deinit(allocator);
        }
        results.deinit();
    }

    const effective_duration = @as(u64, @intFromFloat(@as(f64, @floatFromInt(options.duration_ns)) * 1.0 * options.duration_multiplier));

    // Text processing benchmark
    {
        const context = struct {
            allocator: std.mem.Allocator,

            pub fn run(ctx: @This()) anyerror!void {
                const test_text = "line1\nline2\r\nline3\n";
                var lines = std.mem.splitScalar(u8, test_text, '\n');
                var line_list = std.ArrayList([]const u8).init(ctx.allocator);
                defer line_list.deinit();

                while (lines.next()) |line| {
                    const trimmed = std.mem.trim(u8, line, "\r");
                    try line_list.append(trimmed);
                }
            }
        }{ .allocator = allocator };

        const result = try benchmark_lib.measureOperationNamedWithSuite(allocator, "text", "Text Line Processing", effective_duration, options.warmup, context, @TypeOf(context).run);
        try results.append(result);
    }

    // String operations benchmark
    {
        const context = struct {
            pub fn run(_: @This()) anyerror!void {
                const text = "  hello world  ";
                _ = std.mem.trim(u8, text, " ");
                _ = std.mem.indexOf(u8, text, "world");
                _ = std.mem.startsWith(u8, text, " ");
                _ = std.mem.endsWith(u8, text, " ");
            }
        }{};

        const result = try benchmark_lib.measureOperationNamedWithSuite(allocator, "text", "String Operations", effective_duration, options.warmup, context, @TypeOf(context).run);
        try results.append(result);
    }

    return results.toOwnedSlice();
}

pub fn runCharBenchmarks(allocator: std.mem.Allocator, options: BenchmarkOptions) BenchmarkError![]BenchmarkResult {
    var results = std.ArrayList(BenchmarkResult).init(allocator);
    errdefer {
        for (results.items) |result| {
            result.deinit(allocator);
        }
        results.deinit();
    }

    const effective_duration = @as(u64, @intFromFloat(@as(f64, @floatFromInt(options.duration_ns)) * 1.0 * options.duration_multiplier));

    // Character predicate benchmark
    {
        const context = struct {
            pub fn run(_: @This()) anyerror!void {
                _ = char_mod.isAlpha('a');
                _ = char_mod.isDigit('5');
                _ = char_mod.isAlphaNumeric('z');
                _ = char_mod.isWhitespace(' ');
                _ = char_mod.isIdentifierStart('_');
                _ = char_mod.isIdentifierChar('2');
            }
        }{};

        const result = try benchmark_lib.measureOperationNamedWithSuite(allocator, "char", "Character Predicates", effective_duration, options.warmup, context, @TypeOf(context).run);
        try results.append(result);
    }

    // Basic character operations benchmark
    {
        const context = struct {
            pub fn run(_: @This()) anyerror!void {
                const text = "hello123world";
                for (text) |ch| {
                    _ = char_mod.isAlpha(ch);
                    _ = char_mod.isDigit(ch);
                    _ = char_mod.isAlphaNumeric(ch);
                }
            }
        }{};

        const result = try benchmark_lib.measureOperationNamedWithSuite(allocator, "char", "Character Classification", effective_duration, options.warmup, context, @TypeOf(context).run);
        try results.append(result);
    }

    return results.toOwnedSlice();
}
