// Re-export all public APIs from modular benchmark system

// Core types and utilities
const types = @import("types.zig");
pub const BenchmarkError = types.BenchmarkError;
pub const OutputFormat = types.OutputFormat;
pub const StatisticalConfidence = types.StatisticalConfidence;
pub const BenchmarkOptions = types.BenchmarkOptions;
pub const BenchmarkResult = types.BenchmarkResult;
pub const ComparisonResult = types.ComparisonResult;
pub const BenchmarkSuite = types.BenchmarkSuite;

// Runner and management
const runner = @import("runner.zig");
pub const BenchmarkRunner = runner.BenchmarkRunner;

// Baseline comparison
const baseline = @import("baseline.zig");
pub const BaselineManager = baseline.BaselineManager;

// Timing and measurement
const timer = @import("timer.zig");
pub const measureOperation = timer.measureOperation;
pub const measureOperationNamed = timer.measureOperationNamed;
pub const measureOperationNamedWithSuite = timer.measureOperationNamedWithSuite;

// Utilities
const utils = @import("utils.zig");
pub const parseDuration = utils.parseDuration;

// Suite helpers
const suite = @import("suite.zig");
pub const createSuite = suite.createSuite;
pub const VarianceMultipliers = suite.VarianceMultipliers;