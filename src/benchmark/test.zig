const std = @import("std");
const testing = std.testing;
const main = @import("main.zig");
const test_helpers = @import("../lib/test/helpers.zig");

test "benchmark module initialization" {
    test_helpers.TestRunner.setModule("Benchmark");
}

test "output format parsing" {
    try testing.expect(main.OutputFormat.fromString("markdown") == .markdown);
    try testing.expect(main.OutputFormat.fromString("json") == .json);
    try testing.expect(main.OutputFormat.fromString("csv") == .csv);
    try testing.expect(main.OutputFormat.fromString("pretty") == .pretty);
    try testing.expect(main.OutputFormat.fromString("invalid") == null);
}

// TODO: Reimplement benchmark functionality tests after lib/benchmark.zig is restored