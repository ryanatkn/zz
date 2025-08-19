const std = @import("std");
const types = @import("types.zig");
const BenchmarkResult = types.BenchmarkResult;
const BenchmarkOptions = types.BenchmarkOptions;
const BenchmarkError = types.BenchmarkError;
const StatisticalConfidence = types.StatisticalConfidence;

/// Utility function for timing operations
pub fn measureOperationNamed(
    allocator: std.mem.Allocator,
    name: []const u8,
    duration_ns: u64,
    warmup: bool,
    context: anytype,
    comptime operation: fn (@TypeOf(context)) anyerror!void,
) BenchmarkError!BenchmarkResult {
    return measureOperationNamedWithSuite(allocator, "unknown", name, duration_ns, warmup, context, operation);
}

/// Utility function for timing operations with suite context
pub fn measureOperationNamedWithSuite(
    allocator: std.mem.Allocator,
    suite_name: []const u8,
    name: []const u8,
    duration_ns: u64,
    warmup: bool,
    context: anytype,
    comptime operation: fn (@TypeOf(context)) anyerror!void,
) BenchmarkError!BenchmarkResult {
    std.debug.print("[{s}] Starting \"{s}\" (duration: {}ms)\n", .{ suite_name, name, @divTrunc(duration_ns, 1_000_000) });
    
    // Warmup phase
    if (warmup) {
        try runWarmup(suite_name, context, operation);
    }

    return runBenchmark(allocator, suite_name, name, duration_ns, context, operation);
}

fn runWarmup(
    suite_name: []const u8,
    context: anytype,
    comptime operation: fn (@TypeOf(context)) anyerror!void,
) BenchmarkError!void {
    std.debug.print("[{s}] Warmup: ", .{suite_name});
    const warmup_iterations = 100;
    const warmup_start_time = std.time.nanoTimestamp();
    const warmup_timeout_ns = 10_000_000_000; // 10 second timeout

    for (0..warmup_iterations) |i| {
        // Check for timeout every 10 iterations
        if (i % 10 == 0) {
            const current_time = std.time.nanoTimestamp();
            if ((current_time - warmup_start_time) > warmup_timeout_ns) {
                std.debug.print("TIMEOUT after {}/100 iterations\n", .{i});
                return BenchmarkError.BenchmarkFailed;
            }
            if (i > 0) {
                std.debug.print("{d}", .{i});
                if (i < warmup_iterations - 10) std.debug.print(", ", .{});
            }
        }

        operation(context) catch |err| {
            std.debug.print("ERROR at iteration {}\n", .{i});
            return switch (err) {
                error.OutOfMemory => BenchmarkError.OutOfMemory,
                else => BenchmarkError.BenchmarkFailed,
            };
        };
    }
    std.debug.print("/100 iterations complete\n", .{});
}

fn runBenchmark(
    allocator: std.mem.Allocator,
    suite_name: []const u8,
    name: []const u8,
    duration_ns: u64,
    context: anytype,
    comptime operation: fn (@TypeOf(context)) anyerror!void,
) BenchmarkError!BenchmarkResult {
    var operations: usize = 0;
    const start_time = std.time.nanoTimestamp();
    var current_time = start_time;

    // Adaptive check intervals based on target duration
    const check_interval = calculateCheckInterval(duration_ns);
    const progress_interval = 100_000; // Report progress every 100k operations

    // Prevent infinite loops with maximum iteration count
    const max_operations = 1_000_000_000; // 1 billion operations max
    const benchmark_timeout_ns = 30_000_000_000; // 30 second timeout

    var last_progress_report: u64 = 0;

    // Run operations until duration is reached (NO MINIMUM ITERATIONS)
    while ((current_time - start_time) < duration_ns and operations < max_operations) {
        operation(context) catch |err| {
            std.debug.print("[{s}] ERROR at operation {}\n", .{ suite_name, operations });
            return switch (err) {
                error.OutOfMemory => BenchmarkError.OutOfMemory,
                else => BenchmarkError.BenchmarkFailed,
            };
        };
        operations += 1;

        // Check time at adaptive intervals
        if (operations % check_interval == 0) {
            current_time = std.time.nanoTimestamp();

            // Check for benchmark timeout
            if ((current_time - start_time) > benchmark_timeout_ns) {
                std.debug.print("[{s}] TIMEOUT after {} operations\n", .{ suite_name, operations });
                break;
            }

            // Report progress for very long running benchmarks
            if (operations >= last_progress_report + progress_interval) {
                last_progress_report = operations;
            }
        }
    }

    // Get final accurate time
    const final_time = std.time.nanoTimestamp();
    const elapsed_ns: u64 = @intCast(final_time - start_time);
    const ns_per_op = if (operations > 0) elapsed_ns / operations else elapsed_ns;

    // Calculate statistical confidence
    const confidence = StatisticalConfidence.fromOperationCount(operations);

    // Calculate ops/sec for summary reporting
    const elapsed_ms = @divTrunc(elapsed_ns, 1_000_000);
    const ops_per_sec = if (elapsed_ms > 0) @divTrunc(operations * 1000, @as(usize, @intCast(elapsed_ms))) else operations * 1000;

    // Log completion with confidence indicator
    logCompletion(suite_name, name, operations, elapsed_ms, ns_per_op, ops_per_sec, confidence, max_operations);

    return BenchmarkResult{
        .name = try allocator.dupe(u8, name),
        .total_operations = operations,
        .elapsed_ns = elapsed_ns,
        .ns_per_op = ns_per_op,
        .confidence = confidence,
    };
}

fn calculateCheckInterval(duration_ns: u64) usize {
    // Adaptive check interval based on target duration
    // Short durations: check more frequently
    // Long durations: check less frequently to reduce overhead
    if (duration_ns < 50_000_000) { // < 50ms
        return 10;
    } else if (duration_ns < 500_000_000) { // < 500ms
        return 100;
    } else {
        return 1000;
    }
}

fn logCompletion(
    suite_name: []const u8,
    name: []const u8,
    operations: usize,
    elapsed_ms: u64,
    ns_per_op: u64,
    ops_per_sec: usize,
    confidence: StatisticalConfidence,
    max_operations: usize,
) void {
    const confidence_symbol = confidence.getSymbol();
    
    if (operations >= max_operations) {
        const ops_per_sec_m = ops_per_sec / 1_000_000;
        std.debug.print("[{s}] LIMIT: {s} - {} operations in {}ms ({}ns/op, {}M ops/sec) {s}\n", .{ suite_name, name, operations, elapsed_ms, ns_per_op, ops_per_sec_m, confidence_symbol });
    } else {
        if (operations >= 1_000_000) {
            const ops_f = @as(f64, @floatFromInt(operations)) / 1_000_000.0;
            const ops_per_sec_m = ops_per_sec / 1_000_000;
            std.debug.print("[{s}] Complete: {s} - {d:.1}M ops in {}ms ({}ns/op, {}M ops/sec) {s}\n", .{ suite_name, name, ops_f, elapsed_ms, ns_per_op, ops_per_sec_m, confidence_symbol });
        } else if (operations >= 1_000) {
            const ops_per_sec_k = ops_per_sec / 1_000;
            std.debug.print("[{s}] Complete: {s} - {}k ops in {}ms ({}ns/op, {}k ops/sec) {s}\n", .{ suite_name, name, operations / 1000, elapsed_ms, ns_per_op, ops_per_sec_k, confidence_symbol });
        } else {
            std.debug.print("[{s}] Complete: {s} - {} ops in {}ms ({}ns/op, {} ops/sec) {s}\n", .{ suite_name, name, operations, elapsed_ms, ns_per_op, ops_per_sec, confidence_symbol });
        }
    }

    // Warn about low confidence
    if (confidence == .low or confidence == .insufficient) {
        std.debug.print("[{s}] Warning: {s} has {s} ({} operations)\n", .{ suite_name, name, confidence.getDescription(), operations });
    }
}

/// Utility function for timing operations (backward compatibility)
pub fn measureOperation(
    allocator: std.mem.Allocator,
    duration_ns: u64,
    warmup: bool,
    context: anytype,
    comptime operation: fn (@TypeOf(context)) anyerror!void,
) BenchmarkError!BenchmarkResult {
    return measureOperationNamed(allocator, "operation", duration_ns, warmup, context, operation);
}