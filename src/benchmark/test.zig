const std = @import("std");
const main = @import("main.zig");

test "output format parsing" {
    const OutputFormat = main.OutputFormat;
    
    try std.testing.expect(OutputFormat.fromString("markdown") == .markdown);
    try std.testing.expect(OutputFormat.fromString("json") == .json);
    try std.testing.expect(OutputFormat.fromString("csv") == .csv);
    try std.testing.expect(OutputFormat.fromString("pretty") == .pretty);
    try std.testing.expect(OutputFormat.fromString("invalid") == null);
    try std.testing.expect(OutputFormat.fromString("") == null);
    try std.testing.expect(OutputFormat.fromString("MARKDOWN") == null); // case sensitive
}

test "duration multiplier calculation" {
    const getVarianceMultiplier = main.getVarianceMultiplier;
    const getEffectiveDuration = main.getEffectiveDuration;
    
    // Test built-in variance multipliers for different benchmark types
    try std.testing.expect(getVarianceMultiplier("path") == 2.0);
    try std.testing.expect(getVarianceMultiplier("memory") == 3.0);
    try std.testing.expect(getVarianceMultiplier("string") == 1.0);
    try std.testing.expect(getVarianceMultiplier("glob") == 1.0);
    try std.testing.expect(getVarianceMultiplier("unknown") == 1.0);
    
    // Test effective duration calculation
    const base_duration: u64 = 1_000_000_000; // 1 second in nanoseconds
    
    // Test path benchmark with 2x duration multiplier
    try std.testing.expect(getEffectiveDuration(base_duration, "path", 2.0) == 4_000_000_000); // 1s * 2 (built-in) * 2 (user) = 4s
    
    // Test memory benchmark with 1.5x duration multiplier
    try std.testing.expect(getEffectiveDuration(base_duration, "memory", 1.5) == 4_500_000_000); // 1s * 3 (built-in) * 1.5 (user) = 4.5s
    
    // Test string benchmark with 3x duration multiplier
    try std.testing.expect(getEffectiveDuration(base_duration, "string", 3.0) == 3_000_000_000); // 1s * 1 (built-in) * 3 (user) = 3s
    
    // Test fractional multiplier
    try std.testing.expect(getEffectiveDuration(base_duration, "glob", 0.5) == 500_000_000); // 1s * 1 (built-in) * 0.5 (user) = 0.5s
}

test "duration parsing" {
    const parseDuration = main.parseDuration;
    
    // Test nanoseconds
    try std.testing.expect(try parseDuration("1000ns") == 1000);
    try std.testing.expect(try parseDuration("500000000ns") == 500_000_000);
    
    // Test milliseconds
    try std.testing.expect(try parseDuration("1000ms") == 1_000_000_000);
    try std.testing.expect(try parseDuration("500ms") == 500_000_000);
    
    // Test seconds
    try std.testing.expect(try parseDuration("1s") == 1_000_000_000);
    try std.testing.expect(try parseDuration("2s") == 2_000_000_000);
    
    // Test raw numbers (assumes nanoseconds)
    try std.testing.expect(try parseDuration("1000000") == 1_000_000);
}

test "benchmark module compiles" {
    // Ensure the main module compiles and exports are accessible
    _ = main.run;
    _ = main.OutputFormat;
    
    // If we get here, the module compiled successfully
    try std.testing.expect(true);
}