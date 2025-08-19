const std = @import("std");
const types = @import("types.zig");

// Re-export BenchmarkSuite from types for convenience
pub const BenchmarkSuite = types.BenchmarkSuite;

// Suite creation helpers
pub fn createSuite(
    name: []const u8,
    variance_multiplier: f64,
    runFn: *const fn (allocator: std.mem.Allocator, options: types.BenchmarkOptions) types.BenchmarkError![]types.BenchmarkResult,
) BenchmarkSuite {
    return BenchmarkSuite{
        .name = name,
        .variance_multiplier = variance_multiplier,
        .runFn = runFn,
    };
}

// Common variance multipliers for different benchmark types
pub const VarianceMultipliers = struct {
    pub const cpu_bound: f64 = 1.0;           // Pure CPU operations
    pub const io_bound: f64 = 1.5;            // File I/O operations
    pub const allocation_heavy: f64 = 2.0;    // Memory allocation intensive
    pub const network_dependent: f64 = 3.0;   // Network or highly variable operations
    pub const parsing_complex: f64 = 1.5;     // Language parsing operations
    pub const text_processing: f64 = 1.2;     // Text manipulation operations
};