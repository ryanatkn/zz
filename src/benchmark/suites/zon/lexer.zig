const std = @import("std");
const benchmark_lib = @import("../../../lib/benchmark/mod.zig");
const BenchmarkResult = benchmark_lib.BenchmarkResult;
const BenchmarkOptions = benchmark_lib.BenchmarkOptions;
const BenchmarkError = benchmark_lib.BenchmarkError;

// Import streaming ZON components
const ZonStreamLexer = @import("../../../lib/languages/zon/stream_lexer.zig").ZonStreamLexer;
const StreamToken = @import("../../../lib/token/stream_token.zig").StreamToken;
const TokenIterator = @import("../../../lib/token/iterator.zig").TokenIterator;
const Language = @import("../../../lib/core/language.zig").Language;

pub fn runZonLexerBenchmarks(allocator: std.mem.Allocator, options: BenchmarkOptions) BenchmarkError![]BenchmarkResult {
    var results = std.ArrayList(BenchmarkResult).init(allocator);
    errdefer {
        for (results.items) |result| {
            result.deinit(allocator);
        }
        results.deinit();
    }

    const effective_duration = @as(u64, @intFromFloat(@as(f64, @floatFromInt(options.duration_ns)) * 1.5 * options.duration_multiplier));

    // Generate test data
    const small_zon = try generateZonData(allocator, 10); // ~1KB
    defer allocator.free(small_zon);

    const medium_zon = try generateZonData(allocator, 100); // ~10KB
    defer allocator.free(medium_zon);

    const large_zon = try generateZonData(allocator, 1000); // ~100KB
    defer allocator.free(large_zon);

    // Streaming lexer benchmark for small ZON (1KB)
    {
        const context = struct {
            content: []const u8,

            pub fn run(ctx: @This()) anyerror!void {
                // Use streaming lexer directly
                var lexer = ZonStreamLexer.init(ctx.content);

                // Iterate through all tokens
                var token_count: usize = 0;
                while (lexer.next()) |token| {
                    token_count += 1;
                    // Access token to prevent optimization
                    switch (token) {
                        .zon => |t| std.mem.doNotOptimizeAway(t.kind),
                        else => {},
                    }
                }

                // Prevent optimization
                std.mem.doNotOptimizeAway(token_count);
            }
        }{ .content = small_zon };

        const result = try benchmark_lib.measureOperationNamedWithSuite(allocator, "zon-lexer", "ZON Streaming Lexer Small (1KB)", effective_duration, options.warmup, context, @TypeOf(context).run);
        try results.append(result);
    }

    // Streaming lexer benchmark for medium ZON (10KB) - Performance target
    {
        const context = struct {
            content: []const u8,

            pub fn run(ctx: @This()) anyerror!void {
                // Use streaming lexer directly
                var lexer = ZonStreamLexer.init(ctx.content);

                // Iterate through all tokens
                var token_count: usize = 0;
                while (lexer.next()) |token| {
                    token_count += 1;
                    // Access token to prevent optimization
                    switch (token) {
                        .zon => |t| std.mem.doNotOptimizeAway(t.kind),
                        else => {},
                    }
                }

                std.mem.doNotOptimizeAway(token_count);
            }
        }{ .content = medium_zon };

        const result = try benchmark_lib.measureOperationNamedWithSuite(allocator, "zon-lexer", "ZON Streaming Lexer Medium (10KB)", effective_duration, options.warmup, context, @TypeOf(context).run);
        try results.append(result);

        // Performance target check: <0.1ms (100,000ns) for 10KB
        // Streaming should be faster than batch
        if (result.ns_per_op > 100_000) {
            std.log.warn("ZON Streaming Lexer performance target missed: {}ns > 100,000ns for 10KB", .{result.ns_per_op});
        }
    }

    // Streaming lexer benchmark for large ZON (100KB)
    {
        const context = struct {
            content: []const u8,

            pub fn run(ctx: @This()) anyerror!void {
                // Use streaming lexer directly
                var lexer = ZonStreamLexer.init(ctx.content);

                // Iterate through all tokens
                var token_count: usize = 0;
                while (lexer.next()) |token| {
                    token_count += 1;
                    // Access token to prevent optimization
                    switch (token) {
                        .zon => |t| std.mem.doNotOptimizeAway(t.kind),
                        else => {},
                    }
                }

                std.mem.doNotOptimizeAway(token_count);
            }
        }{ .content = large_zon };

        const result = try benchmark_lib.measureOperationNamedWithSuite(allocator, "zon-lexer", "ZON Streaming Lexer Large (100KB)", effective_duration, options.warmup, context, @TypeOf(context).run);
        try results.append(result);
    }

    // Real-world ZON patterns with TokenIterator
    {
        const real_world_zon =
            \\.{
            \\    .name = "example",
            \\    .version = "0.1.0",
            \\    .dependencies = .{
            \\        .@"tree-sitter" = .{
            \\            .url = "https://github.com/tree-sitter/tree-sitter",
            \\            .hash = "1234567890abcdef",
            \\        },
            \\        .ziglyph = .{
            \\            .path = "../ziglyph",
            \\        },
            \\    },
            \\    .paths = .{ "src", "test", "examples" },
            \\    .minimum_zig_version = "0.11.0",
            \\}
        ;

        const context = struct {
            content: []const u8,

            pub fn run(ctx: @This()) anyerror!void {
                // Use TokenIterator for generic interface
                var iterator = try TokenIterator.init(ctx.content, .zon);

                // Iterate through all tokens
                var token_count: usize = 0;
                while (iterator.next()) |token| {
                    token_count += 1;
                    // Access token to prevent optimization
                    switch (token) {
                        .zon => |t| std.mem.doNotOptimizeAway(t.kind),
                        else => {},
                    }
                }

                std.mem.doNotOptimizeAway(token_count);
            }
        }{ .content = real_world_zon };

        const result = try benchmark_lib.measureOperationNamedWithSuite(allocator, "zon-lexer", "ZON Streaming Lexer Real-World", effective_duration, options.warmup, context, @TypeOf(context).run);
        try results.append(result);
    }

    return results.toOwnedSlice();
}

fn generateZonData(allocator: std.mem.Allocator, num_fields: u32) ![]u8 {
    var zon = std.ArrayList(u8).init(allocator);
    errdefer zon.deinit();

    try zon.appendSlice(".{\n");

    for (0..num_fields) |i| {
        if (i > 0) try zon.appendSlice(",\n");

        // Generate various ZON field types
        const field_type = i % 5;
        switch (field_type) {
            0 => {
                // String field
                try zon.writer().print("    .field_{} = \"value_{}\"", .{ i, i });
            },
            1 => {
                // Number field
                try zon.writer().print("    .number_{} = {}", .{ i, i * 42 });
            },
            2 => {
                // Boolean field
                try zon.writer().print("    .flag_{} = {}", .{ i, i % 2 == 0 });
            },
            3 => {
                // Array field
                try zon.writer().print("    .array_{} = .{{ {}, {}, {} }}", .{ i, i, i + 1, i + 2 });
            },
            4 => {
                // Nested object
                try zon.writer().print(
                    \\    .nested_{} = .{{
                    \\        .inner = "value",
                    \\        .count = {},
                    \\        .enabled = true,
                    \\    }}
                , .{ i, i });
            },
            else => unreachable,
        }
    }

    try zon.appendSlice("\n}");

    return zon.toOwnedSlice();
}
