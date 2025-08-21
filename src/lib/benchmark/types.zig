const std = @import("std");

// Core benchmark types and utilities
pub const BenchmarkError = error{
    InvalidDuration,
    InvalidFormat,
    InvalidFilter,
    BaselineNotFound,
    BenchmarkFailed,
    OutOfMemory,
};

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

pub const StatisticalConfidence = enum {
    high, // >1000 operations
    medium, // 100-1000 operations
    low, // 10-100 operations
    insufficient, // <10 operations

    pub fn fromOperationCount(operations: usize) StatisticalConfidence {
        if (operations >= 1000) return .high;
        if (operations >= 100) return .medium;
        if (operations >= 10) return .low;
        return .insufficient;
    }

    pub fn getSymbol(self: StatisticalConfidence) []const u8 {
        return switch (self) {
            .high => "✓",
            .medium => "○",
            .low => "△",
            .insufficient => "⚠",
        };
    }

    pub fn getDescription(self: StatisticalConfidence) []const u8 {
        return switch (self) {
            .high => "High confidence",
            .medium => "Medium confidence",
            .low => "Low confidence",
            .insufficient => "Insufficient data",
        };
    }
};

pub const BenchmarkOptions = struct {
    /// Duration to run each benchmark in nanoseconds (default: 200ms)
    duration_ns: u64 = 2_000_000_000,
    /// Output format for results
    format: OutputFormat = .markdown,
    /// Path to baseline file for comparison
    baseline: ?[]const u8 = null,
    /// Disable baseline comparison even if baseline exists
    no_compare: bool = false,
    /// Only run benchmarks matching these names (comma-separated)
    only: ?[]const u8 = null,
    /// Skip benchmarks matching these names (comma-separated)
    skip: ?[]const u8 = null,
    /// Include warmup phase before timing
    warmup: bool = true,
    /// Duration multiplier (multiplies duration_ns for longer statistical accuracy)
    duration_multiplier: f64 = 1.0,
    /// Minimum statistical confidence required (fail if not met)
    min_confidence: ?StatisticalConfidence = null,
};

pub const BenchmarkResult = struct {
    name: []const u8,
    total_operations: usize,
    elapsed_ns: u64,
    ns_per_op: u64,
    confidence: StatisticalConfidence,
    extra_info: ?[]const u8 = null,

    /// Free memory owned by this result
    pub fn deinit(self: BenchmarkResult, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.extra_info) |info| {
            allocator.free(info);
        }
    }

    /// Get human-readable time units
    pub fn getTimeUnit(self: BenchmarkResult) struct { value: f64, unit: []const u8 } {
        const ns = @as(f64, @floatFromInt(self.ns_per_op));
        if (ns < 1_000) return .{ .value = ns, .unit = "ns" };
        if (ns < 1_000_000) return .{ .value = ns / 1_000.0, .unit = "μs" };
        if (ns < 1_000_000_000) return .{ .value = ns / 1_000_000.0, .unit = "ms" };
        return .{ .value = ns / 1_000_000_000.0, .unit = "s" };
    }

    /// Check if this result meets minimum confidence requirements
    pub fn meetsConfidenceRequirement(self: BenchmarkResult, min_confidence: ?StatisticalConfidence) bool {
        const min_conf = min_confidence orelse return true;
        return switch (min_conf) {
            .insufficient => true,
            .low => self.confidence != .insufficient,
            .medium => self.confidence == .medium or self.confidence == .high,
            .high => self.confidence == .high,
        };
    }
};

/// Comparison result between current and baseline
pub const ComparisonResult = struct {
    baseline_ns_per_op: u64,
    current_ns_per_op: u64,
    percent_change: f64,
    is_improvement: bool,
    is_regression: bool,

    const REGRESSION_THRESHOLD = 20.0; // 20% regression threshold
    const IMPROVEMENT_THRESHOLD = -1.0; // 1% improvement threshold

    pub fn init(baseline_ns: u64, current_ns: u64) ComparisonResult {
        const baseline_f = @as(f64, @floatFromInt(baseline_ns));
        const current_f = @as(f64, @floatFromInt(current_ns));
        const percent_change = ((current_f - baseline_f) / baseline_f) * 100.0;

        return ComparisonResult{
            .baseline_ns_per_op = baseline_ns,
            .current_ns_per_op = current_ns,
            .percent_change = percent_change,
            .is_improvement = percent_change < IMPROVEMENT_THRESHOLD,
            .is_regression = percent_change > REGRESSION_THRESHOLD,
        };
    }
};

/// Interface for benchmark implementations
pub const BenchmarkSuite = struct {
    name: []const u8,
    /// Function to run the benchmark suite
    runFn: *const fn (allocator: std.mem.Allocator, options: BenchmarkOptions) BenchmarkError![]BenchmarkResult,

    pub fn run(self: BenchmarkSuite, allocator: std.mem.Allocator, options: BenchmarkOptions) BenchmarkError![]BenchmarkResult {
        return self.runFn(allocator, options);
    }
};
