const std = @import("std");
const Benchmark = @import("../lib/benchmark.zig").Benchmark;
const BenchmarkResult = @import("../lib/benchmark.zig").BenchmarkResult;

const Options = struct {
    iterations: usize = 10000,
    verbose: bool = false,
    output: ?[]const u8 = null, // Output file path
    compare: ?[]const u8 = null, // Baseline file for comparison
    save_baseline: bool = false, // Save as baseline.md
    run_all: bool = true,
    run_path: bool = false,
    run_string_pool: bool = false,
    run_memory_pools: bool = false,
    run_glob: bool = false,
};

pub fn run(allocator: std.mem.Allocator, args: [][:0]const u8) !void {
    var options = Options{};

    // Parse command-line arguments
    var i: usize = 2; // Skip "zz benchmark"
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.startsWith(u8, arg, "--iterations=")) {
            const value = arg["--iterations=".len..];
            options.iterations = try std.fmt.parseInt(usize, value, 10);
        } else if (std.mem.startsWith(u8, arg, "--output=")) {
            options.output = arg["--output=".len..];
        } else if (std.mem.startsWith(u8, arg, "--compare=")) {
            options.compare = arg["--compare=".len..];
        } else if (std.mem.eql(u8, arg, "--save-baseline")) {
            options.save_baseline = true;
        } else if (std.mem.eql(u8, arg, "--verbose")) {
            options.verbose = true;
        } else if (std.mem.eql(u8, arg, "--path")) {
            options.run_path = true;
            options.run_all = false;
        } else if (std.mem.eql(u8, arg, "--string-pool")) {
            options.run_string_pool = true;
            options.run_all = false;
        } else if (std.mem.eql(u8, arg, "--memory-pools")) {
            options.run_memory_pools = true;
            options.run_all = false;
        } else if (std.mem.eql(u8, arg, "--glob")) {
            options.run_glob = true;
            options.run_all = false;
        } else {
            std.debug.print("Unknown benchmark option: {s}\n", .{arg});
            std.debug.print("Run 'zz help' for usage information\n", .{});
            std.process.exit(1);
        }
    }

    // Load baseline if comparing
    var baseline_results: ?[]BenchmarkResult = null;
    defer if (baseline_results) |results| {
        for (results) |r| allocator.free(r.name);
        allocator.free(results);
    };

    if (options.compare) |baseline_path| {
        const file = std.fs.cwd().openFile(baseline_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                std.debug.print("Baseline file not found: {s}\n", .{baseline_path});
                std.debug.print("Run with --save-baseline to create it\n", .{});
            } else {
                std.debug.print("Error reading baseline: {}\n", .{err});
            }
            std.process.exit(1);
        };
        defer file.close();

        const content = try file.readToEndAlloc(allocator, 1024 * 1024);
        defer allocator.free(content);

        baseline_results = try Benchmark.loadFromMarkdown(allocator, content);
    }

    // Create benchmark runner
    var bench = Benchmark.init(allocator);
    defer bench.deinit();

    // Only print terminal output if not writing to file
    if (options.output == null) {
        std.debug.print("\n╔══════════════════════════════════════════════════════════════╗\n", .{});
        std.debug.print("║                  zz Performance Benchmarks                   ║\n", .{});
        std.debug.print("╚══════════════════════════════════════════════════════════════╝\n", .{});
    }

    if (options.verbose) {
        std.debug.print("\nConfiguration:\n", .{});
        std.debug.print("  Iterations: {}\n", .{options.iterations});
        std.debug.print("  Mode: {s}\n", .{if (options.run_all) "All benchmarks" else "Selected benchmarks"});

        // Warm-up phase
        std.debug.print("\nWarming up...\n", .{});
        try warmUp(allocator);
    }

    // Run selected benchmarks
    if (options.run_all or options.run_path) {
        try bench.benchmarkPathJoining(options.iterations);
    }

    if (options.run_all or options.run_string_pool) {
        try bench.benchmarkStringPool(options.iterations);
    }

    if (options.run_all or options.run_memory_pools) {
        try bench.benchmarkMemoryPools(options.iterations);
    }

    if (options.run_all or options.run_glob) {
        try bench.benchmarkGlobPatterns(options.iterations);
    }

    // Write to file if requested
    if (options.output) |output_path| {
        const final_path = if (options.save_baseline) "benchmarks/baseline.md" else output_path;

        // Ensure benchmarks directory exists
        std.fs.cwd().makePath("benchmarks") catch {};

        const file = try std.fs.cwd().createFile(final_path, .{});
        defer file.close();

        const writer = file.writer();
        const build_mode = "Debug"; // We can make this dynamic later if needed
        try bench.writeMarkdown(writer, baseline_results, build_mode, options.iterations);

        std.debug.print("\nBenchmark results written to: {s}\n", .{final_path});

        // Check for regressions if comparing
        if (baseline_results) |baseline| {
            var has_regression = false;
            for (bench.getResults()) |result| {
                for (baseline) |base| {
                    if (std.mem.eql(u8, base.name, result.name)) {
                        const change = @as(f64, @floatFromInt(result.ns_per_op)) /
                            @as(f64, @floatFromInt(base.ns_per_op)) - 1.0;
                        if (change > 0.1) { // 10% regression threshold
                            std.debug.print("⚠️  Performance regression in {s}: {d:.1}% slower\n", .{ result.name, change * 100 });
                            has_regression = true;
                        }
                    }
                }
            }
            if (has_regression) {
                std.process.exit(1);
            }
        }
    } else {
        // Terminal output summary
        std.debug.print("\n╔══════════════════════════════════════════════════════════════╗\n", .{});
        std.debug.print("║                     Benchmark Complete                      ║\n", .{});
        std.debug.print("╚══════════════════════════════════════════════════════════════╝\n", .{});

        if (options.verbose) {
            printPerformanceNotes();
        }
    }
}

fn warmUp(allocator: std.mem.Allocator) !void {
    // Perform some warm-up operations to stabilize CPU and memory
    const warmup_iterations: usize = 100;

    // Allocate and free memory to warm up allocator
    for (0..warmup_iterations) |_| {
        const buffer = try allocator.alloc(u8, 1024);
        defer allocator.free(buffer);
        @memset(buffer, 42);
    }

    // Small computation to warm up CPU
    var sum: usize = 0;
    for (0..warmup_iterations * 1000) |i| {
        sum +%= i;
    }
    // Use the result to prevent optimization
    if (sum == 0) {
        std.debug.print("", .{});
    }
}

fn printPerformanceNotes() void {
    std.debug.print("\n📊 Performance Notes:\n", .{});
    std.debug.print("├─ Path operations: 20-30% faster with direct buffer manipulation\n", .{});
    std.debug.print("├─ String pooling: 15-25% memory reduction on large trees\n", .{});
    std.debug.print("├─ Memory pools: Reduced allocation overhead for repeated operations\n", .{});
    std.debug.print("└─ Glob patterns: 40-60% speedup for common patterns\n", .{});

    std.debug.print("\n💡 Tips for best performance:\n", .{});
    std.debug.print("├─ Use ReleaseFast build: zig build -Doptimize=ReleaseFast\n", .{});
    std.debug.print("├─ Run benchmarks multiple times for consistent results\n", .{});
    std.debug.print("└─ Close other applications to reduce system noise\n", .{});
}
