const std = @import("std");
const Benchmark = @import("../lib/benchmark.zig").Benchmark;
const BenchmarkResult = @import("../lib/benchmark.zig").BenchmarkResult;

pub const OutputFormat = enum {
    markdown,
    json,
    csv,
    pretty,
    
    pub fn fromString(s: []const u8) ?OutputFormat {
        if (std.mem.eql(u8, s, "markdown")) return .markdown;
        if (std.mem.eql(u8, s, "json")) return .json;
        if (std.mem.eql(u8, s, "csv")) return .csv;
        if (std.mem.eql(u8, s, "pretty")) return .pretty;
        return null;
    }
};

const Options = struct {
    iterations: usize = 1000,  // Base iterations (will be scaled per benchmark)
    format: OutputFormat = .markdown,
    baseline: ?[]const u8 = null, // Baseline file for comparison
    no_compare: bool = false, // Disable automatic comparison
    only: ?[]const u8 = null, // Run only specific benchmarks (comma-separated)
    skip: ?[]const u8 = null, // Skip specific benchmarks (comma-separated)
    warmup: bool = false,
    // For filtering
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
        } else if (std.mem.startsWith(u8, arg, "--format=")) {
            const value = arg["--format=".len..];
            options.format = OutputFormat.fromString(value) orelse {
                std.debug.print("Unknown format: {s}\n", .{value});
                std.debug.print("Valid formats: markdown, json, csv, pretty\n", .{});
                std.process.exit(1);
            };
        } else if (std.mem.startsWith(u8, arg, "--baseline=")) {
            options.baseline = arg["--baseline=".len..];
        } else if (std.mem.eql(u8, arg, "--no-compare")) {
            options.no_compare = true;
        } else if (std.mem.startsWith(u8, arg, "--only=")) {
            options.only = arg["--only=".len..];
            options.run_all = false;
            // Parse the only list
            var iter = std.mem.tokenizeScalar(u8, options.only.?, ',');
            while (iter.next()) |name| {
                if (std.mem.eql(u8, name, "path")) options.run_path = true;
                if (std.mem.eql(u8, name, "string") or std.mem.eql(u8, name, "string-pool")) options.run_string_pool = true;
                if (std.mem.eql(u8, name, "memory") or std.mem.eql(u8, name, "memory-pools")) options.run_memory_pools = true;
                if (std.mem.eql(u8, name, "glob")) options.run_glob = true;
            }
        } else if (std.mem.startsWith(u8, arg, "--skip=")) {
            options.skip = arg["--skip=".len..];
            // When using skip, we need to first enable all, then disable specific ones
            options.run_path = true;
            options.run_string_pool = true;
            options.run_memory_pools = true;
            options.run_glob = true;
            options.run_all = false;
            
            // Parse the skip list and disable those benchmarks
            var iter = std.mem.tokenizeScalar(u8, options.skip.?, ',');
            while (iter.next()) |name| {
                if (std.mem.eql(u8, name, "path")) options.run_path = false;
                if (std.mem.eql(u8, name, "string") or std.mem.eql(u8, name, "string-pool")) options.run_string_pool = false;
                if (std.mem.eql(u8, name, "memory") or std.mem.eql(u8, name, "memory-pools")) options.run_memory_pools = false;
                if (std.mem.eql(u8, name, "glob")) options.run_glob = false;
            }
        } else if (std.mem.eql(u8, arg, "--warmup")) {
            options.warmup = true;
        } else {
            std.debug.print("Unknown benchmark option: {s}\n", .{arg});
            std.debug.print("Run 'zz help' for usage information\n", .{});
            std.process.exit(1);
        }
    }

    // Load baseline for comparison (for markdown and pretty formats)
    var baseline_results: ?[]BenchmarkResult = null;
    defer if (baseline_results) |results| {
        for (results) |r| allocator.free(r.name);
        allocator.free(results);
    };

    // Auto-load baseline for markdown and pretty formats unless disabled
    if ((options.format == .markdown or options.format == .pretty) and !options.no_compare) {
        const baseline_path = options.baseline orelse "benchmarks/baseline.md";
        
        if (std.fs.cwd().openFile(baseline_path, .{})) |file| {
            defer file.close();
            
            const content = try file.readToEndAlloc(allocator, 1024 * 1024);
            defer allocator.free(content);
            
            baseline_results = try Benchmark.loadFromMarkdown(allocator, content);
        } else |err| {
            // Only error if explicitly specified
            if (options.baseline != null) {
                if (err == error.FileNotFound) {
                    std.debug.print("Baseline file not found: {s}\n", .{baseline_path});
                } else {
                    std.debug.print("Error reading baseline: {}\n", .{err});
                }
                std.process.exit(1);
            }
            // Otherwise silent - no baseline is normal
        }
    }

    // Create benchmark runner
    var bench = Benchmark.init(allocator);
    defer bench.deinit();

    // Warm-up phase if requested
    if (options.warmup) {
        try warmUp(allocator);
    }

    // Run selected benchmarks with scaled iterations to target ~200ms each
    // Path Joining: ~47μs/op, need ~200 iterations for 200ms total
    if (options.run_all or options.run_path) {
        const path_iterations = options.iterations / 5;  // 200 iterations at base 1000
        try bench.benchmarkPathJoining(path_iterations, false);
    }

    // String Pool: ~145ns/op, need ~200,000 iterations for 200ms total
    if (options.run_all or options.run_string_pool) {
        const string_iterations = options.iterations * 200;  // 200,000 iterations at base 1000
        try bench.benchmarkStringPool(string_iterations, false);
    }

    // Memory Pools: ~50μs/op, need ~4000 iterations for 200ms total
    if (options.run_all or options.run_memory_pools) {
        const memory_iterations = options.iterations * 4;  // 4,000 iterations at base 1000
        try bench.benchmarkMemoryPools(memory_iterations, false);
    }

    // Glob Patterns: ~25ns/op, need ~2,000,000 iterations for 200ms total
    if (options.run_all or options.run_glob) {
        const glob_iterations = options.iterations * 2000;  // 2,000,000 iterations at base 1000
        try bench.benchmarkGlobPatterns(glob_iterations, false);
    }

    // Output results in requested format to stdout
    const stdout = std.io.getStdOut().writer();
    const build_mode = "Debug"; // We can make this dynamic later if needed
    
    switch (options.format) {
        .markdown => try bench.writeMarkdown(stdout, baseline_results, build_mode, options.iterations),
        .json => try bench.writeJSON(stdout, build_mode, options.iterations),
        .csv => try bench.writeCSV(stdout),
        .pretty => try bench.writePretty(stdout, baseline_results),
    }
    
    // Check for regressions if comparing (exit with error code if found)
    if (baseline_results) |baseline| {
        var has_regression = false;
        for (bench.getResults()) |result| {
            for (baseline) |base| {
                if (std.mem.eql(u8, base.name, result.name)) {
                    const change = @as(f64, @floatFromInt(result.ns_per_op)) /
                        @as(f64, @floatFromInt(base.ns_per_op)) - 1.0;
                    if (change > 0.2) { // 20% regression threshold (more tolerance for Debug mode)
                        has_regression = true;
                    }
                }
            }
        }
        if (has_regression) {
            std.process.exit(1);
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

