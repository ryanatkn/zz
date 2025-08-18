const std = @import("std");
const print = std.debug.print;

// Import ZON modules
const ZonLexer = @import("lexer.zig").ZonLexer;
const ZonParser = @import("parser.zig").ZonParser;
const ZonFormatter = @import("formatter.zig").ZonFormatter;
const ZonLinter = @import("linter.zig").ZonLinter;
const ZonAnalyzer = @import("analyzer.zig").ZonAnalyzer;
const zon_mod = @import("mod.zig");

/// ZON Language Implementation Benchmarks
///
/// Performance validation for ZON lexing, parsing, formatting, linting, and analysis.
/// These benchmarks validate that the ZON implementation meets performance targets:
///
/// - Lexing: <0.1ms for 1KB ZON
/// - Parsing: <1ms for typical config files
/// - Formatting: <0.5ms for config files
/// - Complete Pipeline: <2ms for typical use cases
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    print("ZON Language Implementation Benchmarks\n");
    print("========================================\n\n");

    // Create test data of various sizes
    const small_zon = try generateTestZon(allocator, 10); // ~1KB
    defer allocator.free(small_zon);

    const medium_zon = try generateTestZon(allocator, 100); // ~10KB
    defer allocator.free(medium_zon);

    const large_zon = try generateTestZon(allocator, 1000); // ~100KB
    defer allocator.free(large_zon);

    // Real-world examples
    const build_zon =
        \\.{
        \\    .name = "example",
        \\    .version = "0.1.0",
        \\    .minimum_zig_version = "0.14.0",
        \\    .dependencies = .{
        \\        .std = .{
        \\            .url = "https://github.com/ziglang/zig",
        \\            .hash = "1220abcd1234567890abcdef1234567890abcdef1234567890abcdef1234567890ab",
        \\        },
        \\        .utils = .{
        \\            .url = "https://github.com/example/utils",
        \\            .hash = "1220efgh5678901234567890efgh5678901234567890efgh5678901234567890efgh",
        \\        },
        \\    },
        \\    .paths = .{
        \\        "build.zig",
        \\        "build.zig.zon",
        \\        "src",
        \\        "README.md",
        \\        "LICENSE",
        \\    },
        \\}
    ;

    const config_zon =
        \\.{
        \\    .base_patterns = "extend",
        \\    .ignored_patterns = .{
        \\        "node_modules",
        \\        "*.tmp",
        \\        "cache",
        \\        "dist",
        \\        "build",
        \\    },
        \\    .hidden_files = .{
        \\        ".DS_Store",
        \\        "Thumbs.db",
        \\        "*.swp",
        \\    },
        \\    .respect_gitignore = true,
        \\    .symlink_behavior = "skip",
        \\    .format = .{
        \\        .indent_size = 4,
        \\        .indent_style = "space",
        \\        .line_width = 100,
        \\        .preserve_newlines = true,
        \\        .trailing_comma = false,
        \\    },
        \\}
    ;

    print("Benchmark Name            |   Avg Time |   Min Time |   Max Time | Operations/sec\n");
    print("--------------------------|------------|------------|------------|---------------\n");

    // Lexer benchmarks
    try runBenchmark(allocator, "lexer_small_1kb", benchmarkLexer, small_zon);
    try runBenchmark(allocator, "lexer_medium_10kb", benchmarkLexer, medium_zon);
    try runBenchmark(allocator, "lexer_large_100kb", benchmarkLexer, large_zon);
    try runBenchmark(allocator, "lexer_build_zon", benchmarkLexer, build_zon);
    try runBenchmark(allocator, "lexer_config_zon", benchmarkLexer, config_zon);

    // Parser benchmarks
    try runBenchmark(allocator, "parser_small_1kb", benchmarkParser, small_zon);
    try runBenchmark(allocator, "parser_medium_10kb", benchmarkParser, medium_zon);
    try runBenchmark(allocator, "parser_large_100kb", benchmarkParser, large_zon);
    try runBenchmark(allocator, "parser_build_zon", benchmarkParser, build_zon);
    try runBenchmark(allocator, "parser_config_zon", benchmarkParser, config_zon);

    // Formatter benchmarks
    try runBenchmark(allocator, "formatter_small_1kb", benchmarkFormatter, small_zon);
    try runBenchmark(allocator, "formatter_medium_10kb", benchmarkFormatter, medium_zon);
    try runBenchmark(allocator, "formatter_build_zon", benchmarkFormatter, build_zon);
    try runBenchmark(allocator, "formatter_config_zon", benchmarkFormatter, config_zon);

    // Linter benchmarks
    try runBenchmark(allocator, "linter_small_1kb", benchmarkLinter, small_zon);
    try runBenchmark(allocator, "linter_medium_10kb", benchmarkLinter, medium_zon);
    try runBenchmark(allocator, "linter_build_zon", benchmarkLinter, build_zon);
    try runBenchmark(allocator, "linter_config_zon", benchmarkLinter, config_zon);

    // Analyzer benchmarks
    try runBenchmark(allocator, "analyzer_small_1kb", benchmarkAnalyzer, small_zon);
    try runBenchmark(allocator, "analyzer_medium_10kb", benchmarkAnalyzer, medium_zon);
    try runBenchmark(allocator, "analyzer_build_zon", benchmarkAnalyzer, build_zon);
    try runBenchmark(allocator, "analyzer_config_zon", benchmarkAnalyzer, config_zon);

    // Complete pipeline benchmarks
    try runBenchmark(allocator, "pipeline_small_1kb", benchmarkPipeline, small_zon);
    try runBenchmark(allocator, "pipeline_medium_10kb", benchmarkPipeline, medium_zon);
    try runBenchmark(allocator, "pipeline_build_zon", benchmarkPipeline, build_zon);
    try runBenchmark(allocator, "pipeline_config_zon", benchmarkPipeline, config_zon);

    // Memory usage benchmarks
    print("\nMemory Usage Analysis:\n");
    print("----------------------\n");

    try runMemoryBenchmark(allocator, "memory_small_1kb", small_zon);
    try runMemoryBenchmark(allocator, "memory_medium_10kb", medium_zon);
    try runMemoryBenchmark(allocator, "memory_build_zon", build_zon);

    // Performance target validation
    print("\nPerformance Targets:\n");
    print("--------------------\n");

    const lexer_time = try measureOperation(allocator, benchmarkLexer, medium_zon);
    const parser_time = try measureOperation(allocator, benchmarkParser, medium_zon);
    const formatter_time = try measureOperation(allocator, benchmarkFormatter, medium_zon);
    const pipeline_time = try measureOperation(allocator, benchmarkPipeline, medium_zon);

    print("- Lexer (10KB):     {} ({d:.1f}ms)  {s}\n", .{
        formatTime(lexer_time),
        @as(f64, @floatFromInt(lexer_time)) / 1_000_000.0,
        if (lexer_time < 100_000) "✅" else "❌", // <0.1ms target
    });
    print("- Parser (10KB):    {} ({d:.1f}ms)  {s}\n", .{
        formatTime(parser_time),
        @as(f64, @floatFromInt(parser_time)) / 1_000_000.0,
        if (parser_time < 1_000_000) "✅" else "❌", // <1.0ms target
    });
    print("- Formatter (10KB): {} ({d:.1f}ms)  {s}\n", .{
        formatTime(formatter_time),
        @as(f64, @floatFromInt(formatter_time)) / 1_000_000.0,
        if (formatter_time < 500_000) "✅" else "❌", // <0.5ms target
    });
    print("- Pipeline (10KB):  {} ({d:.1f}ms)  {s}\n", .{
        formatTime(pipeline_time),
        @as(f64, @floatFromInt(pipeline_time)) / 1_000_000.0,
        if (pipeline_time < 2_000_000) "✅" else "❌", // <2.0ms target
    });
}

fn runBenchmark(allocator: std.mem.Allocator, name: []const u8, benchmarkFn: anytype, input: []const u8) !void {
    const iterations = 100;
    var times = try allocator.alloc(u64, iterations);
    defer allocator.free(times);

    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        const start_time = std.time.nanoTimestamp();
        _ = try benchmarkFn(allocator, input);
        const end_time = std.time.nanoTimestamp();
        times[i] = @intCast(end_time - start_time);
    }

    // Calculate statistics
    std.mem.sort(u64, times, {}, comptime std.sort.asc(u64));
    const min_time = times[0];
    const max_time = times[iterations - 1];

    var total: u64 = 0;
    for (times) |time| {
        total += time;
    }
    const avg_time = total / iterations;

    const ops_per_sec = 1_000_000_000 / avg_time;

    print("{s:<25} | {s:>10} | {s:>10} | {s:>10} | {d:>9} ops/s\n", .{
        name,
        formatTime(avg_time),
        formatTime(min_time),
        formatTime(max_time),
        ops_per_sec,
    });
}

fn runMemoryBenchmark(allocator: std.mem.Allocator, name: []const u8, input: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    const initial_bytes = arena.queryCapacity();

    // Run complete pipeline to measure total memory usage
    _ = try benchmarkPipeline(arena_allocator, input);

    const final_bytes = arena.queryCapacity();
    const memory_used = final_bytes - initial_bytes;
    const input_size = input.len;
    const ratio = @as(f64, @floatFromInt(memory_used)) / @as(f64, @floatFromInt(input_size));

    print("{s:<25} | Input: {d:>6} bytes | Used: {d:>8} bytes | Ratio: {d:.1f}x\n", .{
        name,
        input_size,
        memory_used,
        ratio,
    });
}

fn measureOperation(allocator: std.mem.Allocator, benchmarkFn: anytype, input: []const u8) !u64 {
    const iterations = 10;
    var total_time: u64 = 0;

    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        const start_time = std.time.nanoTimestamp();
        _ = try benchmarkFn(allocator, input);
        const end_time = std.time.nanoTimestamp();
        total_time += @intCast(end_time - start_time);
    }

    return total_time / iterations;
}

fn benchmarkLexer(allocator: std.mem.Allocator, input: []const u8) !u64 {
    var lexer = ZonLexer.init(allocator, input, .{});
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);

    return tokens.len; // Return token count as a simple metric
}

fn benchmarkParser(allocator: std.mem.Allocator, input: []const u8) !u64 {
    var lexer = ZonLexer.init(allocator, input, .{});
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);

    var parser = ZonParser.init(allocator, tokens, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    return countNodes(ast.root); // Return node count as a metric
}

fn benchmarkFormatter(allocator: std.mem.Allocator, input: []const u8) !u64 {
    const formatted = try zon_mod.formatZonString(allocator, input);
    defer allocator.free(formatted);

    return formatted.len; // Return formatted length as a metric
}

fn benchmarkLinter(allocator: std.mem.Allocator, input: []const u8) !u64 {
    const diagnostics = try zon_mod.validateZonString(allocator, input);
    defer {
        for (diagnostics) |diag| {
            allocator.free(diag.message);
        }
        allocator.free(diagnostics);
    }

    return diagnostics.len; // Return diagnostic count as a metric
}

fn benchmarkAnalyzer(allocator: std.mem.Allocator, input: []const u8) !u64 {
    var schema = try zon_mod.extractZonSchema(allocator, input);
    defer schema.deinit();

    return schema.statistics.total_nodes; // Return total nodes as a metric
}

fn benchmarkPipeline(allocator: std.mem.Allocator, input: []const u8) !u64 {
    // Complete pipeline: lex -> parse -> format -> lint -> analyze
    var lexer = ZonLexer.init(allocator, input, .{});
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);

    var parser = ZonParser.init(allocator, tokens, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    const formatted = try zon_mod.formatZonString(allocator, input);
    defer allocator.free(formatted);

    const diagnostics = try zon_mod.validateZonString(allocator, input);
    defer {
        for (diagnostics) |diag| {
            allocator.free(diag.message);
        }
        allocator.free(diagnostics);
    }

    var schema = try zon_mod.extractZonSchema(allocator, input);
    defer schema.deinit();

    return tokens.len + countNodes(ast.root) + formatted.len + diagnostics.len + schema.statistics.total_nodes;
}

fn countNodes(node: @import("../../ast/mod.zig").Node) u64 {
    var count: u64 = 1; // Count this node
    for (node.children) |child| {
        count += countNodes(child);
    }
    return count;
}

fn generateTestZon(allocator: std.mem.Allocator, field_count: u32) ![]u8 {
    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();

    try output.appendSlice(".{\n");
    try output.writer().print("    .name = \"test_package\",\n");
    try output.writer().print("    .version = \"1.0.0\",\n");
    try output.writer().print("    .description = \"Generated test ZON with {} fields\",\n", .{field_count});

    try output.appendSlice("    .metadata = .{\n");

    var i: u32 = 0;
    while (i < field_count) : (i += 1) {
        const field_type = i % 6;
        switch (field_type) {
            0 => try output.writer().print("        .string_field_{} = \"value_{}\",\n", .{ i, i }),
            1 => try output.writer().print("        .number_field_{} = {},\n", .{ i, i }),
            2 => try output.writer().print("        .bool_field_{} = {},\n", .{ i, i % 2 == 0 }),
            3 => try output.writer().print("        .hex_field_{} = 0x{x},\n", .{ i, i }),
            4 => try output.writer().print("        .array_field_{} = .{{ {}, {}, {} }},\n", .{ i, i * 2, i * 3, i * 4 }),
            5 => try output.writer().print("        .nested_field_{} = .{{ .inner = \"value_{}\" }},\n", .{ i, i }),
            else => unreachable,
        }
    }

    try output.appendSlice("    },\n");

    try output.appendSlice("    .dependencies = .{\n");
    var dep_count = @min(field_count / 10, 20); // Up to 20 dependencies
    i = 0;
    while (i < dep_count) : (i += 1) {
        try output.writer().print("        .dep_{} = .{{\n", .{i});
        try output.writer().print("            .url = \"https://github.com/example/dep_{}\",\n", .{i});
        try output.writer().print("            .hash = \"1220abcd{}efgh{}ijkl{}mnop{}\",\n", .{ i, i * 2, i * 3, i * 4 });
        try output.appendSlice("        },\n");
    }
    try output.appendSlice("    },\n");

    try output.appendSlice("    .paths = .{\n");
    try output.appendSlice("        \"build.zig\",\n");
    try output.appendSlice("        \"build.zig.zon\",\n");
    try output.appendSlice("        \"src\",\n");
    try output.appendSlice("        \"README.md\",\n");
    try output.appendSlice("    },\n");

    try output.appendSlice("}");

    return output.toOwnedSlice();
}

fn formatTime(nanoseconds: u64) [32]u8 {
    var buffer: [32]u8 = undefined;

    if (nanoseconds < 1_000) {
        _ = std.fmt.bufPrint(&buffer, "{d}ns", .{nanoseconds}) catch unreachable;
    } else if (nanoseconds < 1_000_000) {
        const microseconds = @as(f64, @floatFromInt(nanoseconds)) / 1_000.0;
        _ = std.fmt.bufPrint(&buffer, "{d:.2f}μs", .{microseconds}) catch unreachable;
    } else if (nanoseconds < 1_000_000_000) {
        const milliseconds = @as(f64, @floatFromInt(nanoseconds)) / 1_000_000.0;
        _ = std.fmt.bufPrint(&buffer, "{d:.2f}ms", .{milliseconds}) catch unreachable;
    } else {
        const seconds = @as(f64, @floatFromInt(nanoseconds)) / 1_000_000_000.0;
        _ = std.fmt.bufPrint(&buffer, "{d:.2f}s", .{seconds}) catch unreachable;
    }

    return buffer;
}
