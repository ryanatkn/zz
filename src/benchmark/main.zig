const std = @import("std");
const benchmark_lib = @import("../lib/benchmark/mod.zig");
const BenchmarkRunner = benchmark_lib.BenchmarkRunner;
const BenchmarkOptions = benchmark_lib.BenchmarkOptions;
const BenchmarkSuite = benchmark_lib.BenchmarkSuite;
pub const OutputFormat = benchmark_lib.OutputFormat;

// Import benchmark suites
const core_benchmarks = @import("suites/core.zig");
const language_benchmarks = @import("suites/languages.zig");
const streaming_benchmarks = @import("suites/streaming.zig");

// Import comprehensive language suites
const json_lexer = @import("suites/json/lexer.zig");
const json_parser = @import("suites/json/parser.zig");
const json_pipeline = @import("suites/json/pipeline.zig");
const zon_lexer = @import("suites/zon/lexer.zig");
const zon_pipeline = @import("suites/zon/pipeline.zig");

pub fn run(allocator: std.mem.Allocator, args: [][:0]const u8) !void {
    var options = BenchmarkOptions{};

    // Parse command line arguments
    var i: usize = 1; // Skip program name
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--format")) {
            i += 1;
            if (i >= args.len) {
                std.debug.print("Error: --format requires a value\n", .{});
                return;
            }
            options.format = OutputFormat.fromString(args[i]) orelse {
                std.debug.print("Error: Invalid format '{s}'. Use: markdown, json, csv, pretty\n", .{args[i]});
                return;
            };
        } else if (std.mem.eql(u8, arg, "--duration")) {
            i += 1;
            if (i >= args.len) {
                std.debug.print("Error: --duration requires a value\n", .{});
                return;
            }
            options.duration_ns = benchmark_lib.parseDuration(args[i]) catch {
                std.debug.print("Error: Invalid duration '{s}'. Use format like '2s', '500ms', or nanoseconds\n", .{args[i]});
                return;
            };
        } else if (std.mem.eql(u8, arg, "--duration-multiplier")) {
            i += 1;
            if (i >= args.len) {
                std.debug.print("Error: --duration-multiplier requires a value\n", .{});
                return;
            }
            options.duration_multiplier = std.fmt.parseFloat(f64, args[i]) catch {
                std.debug.print("Error: Invalid duration multiplier '{s}'\n", .{args[i]});
                return;
            };
        } else if (std.mem.eql(u8, arg, "--baseline")) {
            i += 1;
            if (i >= args.len) {
                std.debug.print("Error: --baseline requires a value\n", .{});
                return;
            }
            options.baseline = args[i];
        } else if (std.mem.eql(u8, arg, "--no-compare")) {
            options.no_compare = true;
        } else if (std.mem.eql(u8, arg, "--only")) {
            i += 1;
            if (i >= args.len) {
                std.debug.print("Error: --only requires a value\n", .{});
                return;
            }
            options.only = args[i];
        } else if (std.mem.eql(u8, arg, "--skip")) {
            i += 1;
            if (i >= args.len) {
                std.debug.print("Error: --skip requires a value\n", .{});
                return;
            }
            options.skip = args[i];
        } else if (std.mem.eql(u8, arg, "--no-warmup")) {
            options.warmup = false;
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try printHelp();
            return;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            std.debug.print("Error: Unknown option '{s}'\n", .{arg});
            try printHelp();
            return;
        }
    }

    // Set default baseline if not specified and comparison is enabled
    if (!options.no_compare and options.baseline == null) {
        options.baseline = "benchmarks/baseline.md";
    }

    var runner = BenchmarkRunner.init(allocator, options);
    defer runner.deinit();

    // Load baseline for comparison if specified
    if (options.baseline) |baseline_path| {
        if (!options.no_compare) {
            runner.loadBaseline(baseline_path) catch |err| switch (err) {
                benchmark_lib.BenchmarkError.BaselineNotFound => {
                    // Baseline not found is not an error - just continue without comparison
                },
                else => {
                    std.debug.print("Warning: Could not load baseline from '{s}': {}\n", .{ baseline_path, err });
                },
            };
        }
    }

    // Register all benchmark suites
    try registerBenchmarkSuites(&runner);

    // Run benchmarks
    try runner.runAll();

    // Output results
    const stdout = std.io.getStdOut().writer();
    try runner.outputResults(stdout);

    // Check for regressions and exit with appropriate code
    if (runner.checkRegressions()) {
        std.process.exit(1);
    }
}

fn registerBenchmarkSuites(runner: *BenchmarkRunner) !void {
    // Core module benchmarks
    try runner.registerSuite(BenchmarkSuite{
        .name = "path",
        .variance_multiplier = 1.5, // I/O dependent
        .runFn = core_benchmarks.runPathBenchmarks,
    });

    try runner.registerSuite(BenchmarkSuite{
        .name = "memory",
        .variance_multiplier = 2.0, // Allocation dependent
        .runFn = core_benchmarks.runMemoryBenchmarks,
    });

    try runner.registerSuite(BenchmarkSuite{
        .name = "patterns",
        .variance_multiplier = 1.5, // Pattern matching variability
        .runFn = core_benchmarks.runPatternBenchmarks,
    });

    try runner.registerSuite(BenchmarkSuite{
        .name = "text",
        .variance_multiplier = 1.0, // CPU bound
        .runFn = core_benchmarks.runTextBenchmarks,
    });

    try runner.registerSuite(BenchmarkSuite{
        .name = "char",
        .variance_multiplier = 1.0, // CPU bound
        .runFn = core_benchmarks.runCharBenchmarks,
    });

    // Language benchmarks
    try runner.registerSuite(BenchmarkSuite{
        .name = "json",
        .variance_multiplier = 1.5, // Language processing
        .runFn = language_benchmarks.runJsonBenchmarks,
    });

    try runner.registerSuite(BenchmarkSuite{
        .name = "zon",
        .variance_multiplier = 1.5, // Language processing
        .runFn = language_benchmarks.runZonBenchmarks,
    });

    try runner.registerSuite(BenchmarkSuite{
        .name = "parser",
        .variance_multiplier = 1.5, // Parsing complexity
        .runFn = language_benchmarks.runParserBenchmarks,
    });

    // Streaming benchmarks - RE-ENABLED after fixing double-free bug (August 19, 2025)
    // Issue was NOT expensive tokenization, but double-free segfault in TokenIterator
    // Fixed: Removed manual token.text freeing - iterator.deinit() handles cleanup
    try runner.registerSuite(BenchmarkSuite{
        .name = "streaming",
        .variance_multiplier = 3.0, // Memory allocation variability
        .runFn = streaming_benchmarks.runStreamingBenchmarks,
    });

    // Comprehensive JSON benchmarks (temporarily disabled due to TokenKind enum issues)
    // try runner.registerSuite(BenchmarkSuite{
    //     .name = "json-lexer",
    //     .variance_multiplier = 1.2, // Language lexing
    //     .runFn = json_lexer.runJsonLexerBenchmarks,
    // });

    // try runner.registerSuite(BenchmarkSuite{
    //     .name = "json-parser",
    //     .variance_multiplier = 1.5, // Language parsing
    //     .runFn = json_parser.runJsonParserBenchmarks,
    // });

    // try runner.registerSuite(BenchmarkSuite{
    //     .name = "json-pipeline",
    //     .variance_multiplier = 2.0, // Complete pipeline
    //     .runFn = json_pipeline.runJsonPipelineBenchmarks,
    // });

    // Comprehensive ZON benchmarks
    try runner.registerSuite(BenchmarkSuite{
        .name = "zon-lexer",
        .variance_multiplier = 1.2, // Language lexing
        .runFn = zon_lexer.runZonLexerBenchmarks,
    });

    // Disabled - operations are too slow (15ms each) for normal benchmark durations
    // Each pipeline operation (format + validate + extract) takes ~45ms
    // Would need much longer durations (5+ seconds) to get meaningful results
    // try runner.registerSuite(BenchmarkSuite{
    //     .name = "zon-pipeline",
    //     .variance_multiplier = 2.0, // Complete pipeline
    //     .runFn = zon_pipeline.runZonPipelineBenchmarks,
    // });
}

fn printHelp() !void {
    const help_text =
        \\Usage: zz benchmark [options]
        \\
        \\Options:
        \\  --format FORMAT           Output format (markdown, json, csv, pretty) [default: markdown]
        \\  --duration TIME           Duration to run each benchmark (e.g. 2s, 500ms) [default: 2s]
        \\  --duration-multiplier N   Extra duration multiplier [default: 1.0]
        \\  --baseline FILE           Custom baseline file [default: benchmarks/baseline.md]
        \\  --no-compare              Disable baseline comparison
        \\  --only=LIST               Run only specified benchmarks (comma-separated)
        \\  --skip=LIST               Skip specified benchmarks (comma-separated)
        \\  --no-warmup               Skip warmup phase
        \\  -h, --help                Show this help
        \\
        \\Examples:
        \\  zz benchmark                                    # Run all benchmarks with markdown output
        \\  zz benchmark --format pretty                   # Pretty terminal output
        \\  zz benchmark --only path,memory                # Run only path and memory benchmarks
        \\  zz benchmark --duration 5s --duration-multiplier 2.0  # Extended duration for stability
        \\  zz benchmark --no-compare                      # Skip baseline comparison
        \\
        \\Benchmark suites: path, memory, patterns, text, char, json, zon, parser
        \\
    ;

    const stderr = std.io.getStdErr().writer();
    try stderr.writeAll(help_text);
}
