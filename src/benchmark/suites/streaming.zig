const std = @import("std");
const benchmark_lib = @import("../../lib/benchmark/mod.zig");
const BenchmarkResult = benchmark_lib.BenchmarkResult;
const BenchmarkOptions = benchmark_lib.BenchmarkOptions;
const BenchmarkError = benchmark_lib.BenchmarkError;

// Removed old transform imports - using new streaming architecture

pub fn runStreamingBenchmarks(allocator: std.mem.Allocator, options: BenchmarkOptions) BenchmarkError![]BenchmarkResult {
    // Streaming benchmarks disabled during migration to tagged union architecture
    _ = allocator;
    _ = options;
    return &[_]BenchmarkResult{};
}
