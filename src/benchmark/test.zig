const std = @import("std");
const testing = std.testing;
const main = @import("main.zig");
const test_helpers = @import("../test_helpers.zig");

test "benchmark module initialization" {
    test_helpers.TestRunner.setModule("Benchmark");
}

test "output format parsing" {
    const OutputFormat = main.OutputFormat;
    
    try testing.expect(OutputFormat.fromString("markdown") == .markdown);
    try testing.expect(OutputFormat.fromString("json") == .json);
    try testing.expect(OutputFormat.fromString("csv") == .csv);
    try testing.expect(OutputFormat.fromString("pretty") == .pretty);
    try testing.expect(OutputFormat.fromString("invalid") == null);
    try testing.expect(OutputFormat.fromString("") == null);
    try testing.expect(OutputFormat.fromString("MARKDOWN") == null); // case sensitive
}

test "duration multiplier calculation" {
    const getBuiltinDurationMultiplier = main.getBuiltinDurationMultiplier;
    const getEffectiveDuration = main.getEffectiveDuration;
    
    // Test built-in duration multipliers for different benchmark types
    try testing.expect(getBuiltinDurationMultiplier("path") == 2.0);
    try testing.expect(getBuiltinDurationMultiplier("memory") == 3.0);
    try testing.expect(getBuiltinDurationMultiplier("string") == 1.0);
    try testing.expect(getBuiltinDurationMultiplier("glob") == 1.0);
    try testing.expect(getBuiltinDurationMultiplier("unknown") == 1.0);
    
    // Test effective duration calculation
    const base_duration: u64 = 1_000_000_000; // 1 second in nanoseconds
    
    // Test path benchmark with 2x duration multiplier
    try testing.expect(getEffectiveDuration(base_duration, "path", 2.0) == 4_000_000_000); // 1s * 2 (built-in) * 2 (user) = 4s
    
    // Test memory benchmark with 1.5x duration multiplier
    try testing.expect(getEffectiveDuration(base_duration, "memory", 1.5) == 4_500_000_000); // 1s * 3 (built-in) * 1.5 (user) = 4.5s
    
    // Test string benchmark with 3x duration multiplier
    try testing.expect(getEffectiveDuration(base_duration, "string", 3.0) == 3_000_000_000); // 1s * 1 (built-in) * 3 (user) = 3s
    
    // Test fractional multiplier
    try testing.expect(getEffectiveDuration(base_duration, "glob", 0.5) == 500_000_000); // 1s * 1 (built-in) * 0.5 (user) = 0.5s
}

test "duration parsing" {
    const parseDuration = main.parseDuration;
    
    // Test nanoseconds
    try testing.expect(try parseDuration("1000ns") == 1000);
    try testing.expect(try parseDuration("500000000ns") == 500_000_000);
    
    // Test milliseconds
    try testing.expect(try parseDuration("1000ms") == 1_000_000_000);
    try testing.expect(try parseDuration("500ms") == 500_000_000);
    
    // Test seconds
    try testing.expect(try parseDuration("1s") == 1_000_000_000);
    try testing.expect(try parseDuration("2s") == 2_000_000_000);
    
    // Test raw numbers (assumes nanoseconds)
    try testing.expect(try parseDuration("1000000") == 1_000_000);
}

test "benchmark module compiles" {
    // Ensure the main module compiles and exports are accessible
    _ = main.run;
    _ = main.OutputFormat;
    
    // If we get here, the module compiled successfully
    try testing.expect(true);
}

test "benchmark module test summary" {
    test_helpers.TestRunner.printSummary();
}

