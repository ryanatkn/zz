const std = @import("std");
const json_mod = @import("mod.zig");
const JsonLexer = @import("lexer.zig").JsonLexer;
const JsonParser = @import("parser.zig").JsonParser;
const JsonFormatter = @import("formatter.zig").JsonFormatter;
const JsonLinter = @import("linter.zig").JsonLinter;
const JsonAnalyzer = @import("analyzer.zig").JsonAnalyzer;

/// Performance benchmarks for JSON language implementation
///
/// This file contains comprehensive benchmarks to ensure the JSON implementation
/// meets the performance targets specified in the design:
/// - Lexing: <0.1ms for 10KB JSON
/// - Parsing: <1ms for 10KB JSON
/// - Formatting: <0.5ms for 10KB JSON
/// - Complete pipeline: <2ms for 10KB JSON
pub const BenchmarkOptions = struct {
    iterations: u32 = 1000,
    warmup_iterations: u32 = 100,
    report_format: ReportFormat = .table,

    pub const ReportFormat = enum { table, json, csv };
};

pub const BenchmarkResult = struct {
    name: []const u8,
    iterations: u32,
    total_time_ns: u64,
    avg_time_ns: u64,
    min_time_ns: u64,
    max_time_ns: u64,
    operations_per_second: f64,

    pub fn format(self: BenchmarkResult, writer: anytype) !void {
        const avg_time_us = @as(f64, @floatFromInt(self.avg_time_ns)) / 1000.0;
        const min_time_us = @as(f64, @floatFromInt(self.min_time_ns)) / 1000.0;
        const max_time_us = @as(f64, @floatFromInt(self.max_time_ns)) / 1000.0;

        try writer.print("{s:<25} | {:>8.2}μs | {:>8.2}μs | {:>8.2}μs | {:>8.0} ops/s\n", .{
            self.name,
            avg_time_us,
            min_time_us,
            max_time_us,
            self.operations_per_second,
        });
    }
};

pub const JsonBenchmark = struct {
    allocator: std.mem.Allocator,
    options: BenchmarkOptions,
    results: std.ArrayList(BenchmarkResult),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, options: BenchmarkOptions) JsonBenchmark {
        return JsonBenchmark{
            .allocator = allocator,
            .options = options,
            .results = std.ArrayList(BenchmarkResult).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.results.deinit();
    }

    /// Run all JSON benchmarks
    pub fn runAll(self: *Self) !void {
        const test_data = try self.generateTestData();
        defer {
            for (test_data) |data| {
                self.allocator.free(data.content);
            }
            self.allocator.free(test_data);
        }

        // Benchmark each component
        try self.benchmarkLexer(test_data);
        try self.benchmarkParser(test_data);
        try self.benchmarkFormatter(test_data);
        try self.benchmarkLinter(test_data);
        try self.benchmarkAnalyzer(test_data);
        try self.benchmarkCompletePipeline(test_data);
    }

    /// Generate test data of various sizes
    fn generateTestData(self: *Self) ![]TestData {
        const TestData = struct {
            name: []const u8,
            content: []u8,
            size_kb: f64,
        };

        var test_data = std.ArrayList(TestData).init(self.allocator);
        defer test_data.deinit();

        // Small JSON (1KB)
        try test_data.append(TestData{
            .name = "small_1kb",
            .content = try self.generateJsonData(50), // ~1KB
            .size_kb = 1.0,
        });

        // Medium JSON (10KB) - main target
        try test_data.append(TestData{
            .name = "medium_10kb",
            .content = try self.generateJsonData(500), // ~10KB
            .size_kb = 10.0,
        });

        // Large JSON (100KB)
        try test_data.append(TestData{
            .name = "large_100kb",
            .content = try self.generateJsonData(5000), // ~100KB
            .size_kb = 100.0,
        });

        return test_data.toOwnedSlice();
    }

    fn generateJsonData(self: *Self, num_items: u32) ![]u8 {
        var json = std.ArrayList(u8).init(self.allocator);
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

    fn benchmarkLexer(self: *Self, test_data: []const TestData) !void {
        for (test_data) |data| {
            const benchmark_name = try std.fmt.allocPrint(self.allocator, "lexer_{s}", .{data.name});
            defer self.allocator.free(benchmark_name);

            const result = try self.measureOperation(benchmark_name, struct {
                allocator: std.mem.Allocator,
                content: []const u8,

                pub fn run(ctx: @This()) !void {
                    var lexer = JsonLexer.init(ctx.allocator, ctx.content, .{});
                    defer lexer.deinit();

                    const tokens = try lexer.tokenize();
                    defer ctx.allocator.free(tokens);
                }
            }{ .allocator = self.allocator, .content = data.content });

            try self.results.append(result);

            // Check performance targets
            if (std.mem.eql(u8, data.name, "medium_10kb")) {
                // Target: <0.1ms (100,000ns) for 10KB
                if (result.avg_time_ns > 100_000) {
                    std.log.warn("Lexer performance target missed: {}ns > 100,000ns for 10KB", .{result.avg_time_ns});
                }
            }
        }
    }

    fn benchmarkParser(self: *Self, test_data: []const TestData) !void {
        for (test_data) |data| {
            // Pre-tokenize for parser benchmark
            var lexer = JsonLexer.init(self.allocator, data.content, .{});
            defer lexer.deinit();
            const tokens = try lexer.tokenize();
            defer self.allocator.free(tokens);

            const benchmark_name = try std.fmt.allocPrint(self.allocator, "parser_{s}", .{data.name});
            defer self.allocator.free(benchmark_name);

            const result = try self.measureOperation(benchmark_name, struct {
                allocator: std.mem.Allocator,
                tokens: []const @import("../../parser/foundation/types/token.zig").Token,

                pub fn run(ctx: @This()) !void {
                    var parser = JsonParser.init(ctx.allocator, ctx.tokens, .{});
                    defer parser.deinit();

                    var ast = try parser.parse();
                    defer ast.deinit();
                }
            }{ .allocator = self.allocator, .tokens = tokens });

            try self.results.append(result);

            // Check performance targets
            if (std.mem.eql(u8, data.name, "medium_10kb")) {
                // Target: <1ms (1,000,000ns) for 10KB
                if (result.avg_time_ns > 1_000_000) {
                    std.log.warn("Parser performance target missed: {}ns > 1,000,000ns for 10KB", .{result.avg_time_ns});
                }
            }
        }
    }

    fn benchmarkFormatter(self: *Self, test_data: []const TestData) !void {
        for (test_data) |data| {
            // Pre-parse for formatter benchmark
            var ast = try json_mod.parseJson(self.allocator, data.content);
            defer ast.deinit();

            const benchmark_name = try std.fmt.allocPrint(self.allocator, "formatter_{s}", .{data.name});
            defer self.allocator.free(benchmark_name);

            const result = try self.measureOperation(benchmark_name, struct {
                allocator: std.mem.Allocator,
                ast: @import("../../ast/mod.zig").AST,

                pub fn run(ctx: @This()) !void {
                    var formatter = JsonFormatter.init(ctx.allocator, .{});
                    defer formatter.deinit();

                    const formatted = try formatter.format(ctx.ast);
                    defer ctx.allocator.free(formatted);
                }
            }{ .allocator = self.allocator, .ast = ast });

            try self.results.append(result);

            // Check performance targets
            if (std.mem.eql(u8, data.name, "medium_10kb")) {
                // Target: <0.5ms (500,000ns) for 10KB
                if (result.avg_time_ns > 500_000) {
                    std.log.warn("Formatter performance target missed: {}ns > 500,000ns for 10KB", .{result.avg_time_ns});
                }
            }
        }
    }

    fn benchmarkLinter(self: *Self, test_data: []const TestData) !void {
        for (test_data) |data| {
            // Pre-parse for linter benchmark
            var ast = try json_mod.parseJson(self.allocator, data.content);
            defer ast.deinit();

            const benchmark_name = try std.fmt.allocPrint(self.allocator, "linter_{s}", .{data.name});
            defer self.allocator.free(benchmark_name);

            const enabled_rules = &[_]@import("../interface.zig").Rule{
                .{ .name = "no-duplicate-keys", .description = "", .severity = .@"error", .enabled = true },
                .{ .name = "no-leading-zeros", .description = "", .severity = .warning, .enabled = true },
                .{ .name = "deep-nesting", .description = "", .severity = .warning, .enabled = true },
            };

            const result = try self.measureOperation(benchmark_name, struct {
                allocator: std.mem.Allocator,
                ast: @import("../../ast/mod.zig").AST,
                rules: []const @import("../interface.zig").Rule,

                pub fn run(ctx: @This()) !void {
                    var linter = JsonLinter.init(ctx.allocator, .{});
                    defer linter.deinit();

                    const diagnostics = try linter.lint(ctx.ast, ctx.rules);
                    defer {
                        for (diagnostics) |diag| {
                            ctx.allocator.free(diag.message);
                        }
                        ctx.allocator.free(diagnostics);
                    }
                }
            }{ .allocator = self.allocator, .ast = ast, .rules = enabled_rules });

            try self.results.append(result);
        }
    }

    fn benchmarkAnalyzer(self: *Self, test_data: []const TestData) !void {
        for (test_data) |data| {
            // Pre-parse for analyzer benchmark
            var ast = try json_mod.parseJson(self.allocator, data.content);
            defer ast.deinit();

            const benchmark_name = try std.fmt.allocPrint(self.allocator, "analyzer_{s}", .{data.name});
            defer self.allocator.free(benchmark_name);

            const result = try self.measureOperation(benchmark_name, struct {
                allocator: std.mem.Allocator,
                ast: @import("../../ast/mod.zig").AST,

                pub fn run(ctx: @This()) !void {
                    var analyzer = JsonAnalyzer.init(ctx.allocator, .{});

                    // Test multiple analyzer operations
                    var schema = try analyzer.extractSchema(ctx.ast);
                    defer schema.deinit(ctx.allocator);

                    const stats = try analyzer.generateStatistics(ctx.ast);
                    _ = stats;

                    const symbols = try analyzer.extractSymbols(ctx.ast);
                    defer {
                        for (symbols) |symbol| {
                            ctx.allocator.free(symbol.name);
                            if (symbol.signature) |sig| {
                                ctx.allocator.free(sig);
                            }
                        }
                        ctx.allocator.free(symbols);
                    }
                }
            }{ .allocator = self.allocator, .ast = ast });

            try self.results.append(result);
        }
    }

    fn benchmarkCompletePipeline(self: *Self, test_data: []const TestData) !void {
        for (test_data) |data| {
            const benchmark_name = try std.fmt.allocPrint(self.allocator, "pipeline_{s}", .{data.name});
            defer self.allocator.free(benchmark_name);

            const result = try self.measureOperation(benchmark_name, struct {
                allocator: std.mem.Allocator,
                content: []const u8,

                pub fn run(ctx: @This()) !void {
                    // Complete pipeline: lex → parse → format → lint → analyze
                    var ast = try json_mod.parseJson(ctx.allocator, ctx.content);
                    defer ast.deinit();

                    const formatted = try json_mod.formatJsonString(ctx.allocator, ctx.content);
                    defer ctx.allocator.free(formatted);

                    const diagnostics = try json_mod.validateJson(ctx.allocator, ctx.content);
                    defer {
                        for (diagnostics) |diag| {
                            ctx.allocator.free(diag.message);
                        }
                        ctx.allocator.free(diagnostics);
                    }

                    var schema = try json_mod.extractJsonSchema(ctx.allocator, ctx.content);
                    defer schema.deinit(ctx.allocator);

                    const stats = try json_mod.getJsonStatistics(ctx.allocator, ctx.content);
                    _ = stats;
                }
            }{ .allocator = self.allocator, .content = data.content });

            try self.results.append(result);

            // Check complete pipeline performance targets
            if (std.mem.eql(u8, data.name, "medium_10kb")) {
                // Target: <2ms (2,000,000ns) for 10KB complete pipeline
                if (result.avg_time_ns > 2_000_000) {
                    std.log.warn("Complete pipeline performance target missed: {}ns > 2,000,000ns for 10KB", .{result.avg_time_ns});
                }
            }
        }
    }

    fn measureOperation(self: *Self, name: []const u8, context: anytype) !BenchmarkResult {
        // Warmup
        for (0..self.options.warmup_iterations) |_| {
            try context.run();
        }

        var times = std.ArrayList(u64).init(self.allocator);
        defer times.deinit();

        // Actual measurements
        for (0..self.options.iterations) |_| {
            const start_time = std.time.nanoTimestamp();
            try context.run();
            const end_time = std.time.nanoTimestamp();

            try times.append(@intCast(end_time - start_time));
        }

        // Calculate statistics
        var total_time: u64 = 0;
        var min_time: u64 = std.math.maxInt(u64);
        var max_time: u64 = 0;

        for (times.items) |time| {
            total_time += time;
            min_time = @min(min_time, time);
            max_time = @max(max_time, time);
        }

        const avg_time = total_time / times.items.len;
        const ops_per_second = 1_000_000_000.0 / @as(f64, @floatFromInt(avg_time));

        return BenchmarkResult{
            .name = try self.allocator.dupe(u8, name),
            .iterations = self.options.iterations,
            .total_time_ns = total_time,
            .avg_time_ns = avg_time,
            .min_time_ns = min_time,
            .max_time_ns = max_time,
            .operations_per_second = ops_per_second,
        };
    }

    /// Print benchmark results
    pub fn printResults(self: *Self, writer: anytype) !void {
        try writer.print("JSON Language Implementation Benchmarks\n");
        try writer.print("========================================\n\n");
        try writer.print("Benchmark Name            |   Avg Time |   Min Time |   Max Time | Operations/sec\n");
        try writer.print("--------------------------|------------|------------|------------|---------------\n");

        for (self.results.items) |result| {
            try result.format(writer);
        }

        try writer.print("\nPerformance Targets:\n");
        try writer.print("- Lexer (10KB):     < 100μs   (0.1ms)\n");
        try writer.print("- Parser (10KB):    < 1000μs  (1.0ms)\n");
        try writer.print("- Formatter (10KB): < 500μs   (0.5ms)\n");
        try writer.print("- Pipeline (10KB):  < 2000μs  (2.0ms)\n");
    }

    /// Export results as JSON
    pub fn exportJson(self: *Self, writer: anytype) !void {
        try writer.writeAll("{\n  \"benchmarks\": [\n");

        for (self.results.items, 0..) |result, i| {
            if (i > 0) try writer.writeAll(",\n");

            try writer.print(
                \\    {{
                \\      "name": "{s}",
                \\      "iterations": {},
                \\      "avg_time_ns": {},
                \\      "min_time_ns": {},
                \\      "max_time_ns": {},
                \\      "ops_per_second": {d:.2}
                \\    }}
            , .{
                result.name,
                result.iterations,
                result.avg_time_ns,
                result.min_time_ns,
                result.max_time_ns,
                result.operations_per_second,
            });
        }

        try writer.writeAll("\n  ]\n}");
    }
};

// Test for the benchmark itself
const testing = std.testing;

test "JSON benchmark - smoke test" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var benchmark = JsonBenchmark.init(allocator, .{
        .iterations = 10, // Small number for test
        .warmup_iterations = 2,
    });
    defer benchmark.deinit();

    // Test that benchmark runs without errors
    try benchmark.runAll();

    // Should have results for each test data size and component
    try testing.expect(benchmark.results.items.len > 0);

    // Print results for manual inspection
    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();

    try benchmark.printResults(output.writer());

    // Results should contain expected benchmark names
    const output_text = output.items;
    try testing.expect(std.mem.indexOf(u8, output_text, "lexer_") != null);
    try testing.expect(std.mem.indexOf(u8, output_text, "parser_") != null);
    try testing.expect(std.mem.indexOf(u8, output_text, "formatter_") != null);
}
