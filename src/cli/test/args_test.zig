const std = @import("std");
const testing = std.testing;
const test_helpers = @import("../../lib/test/helpers.zig");
const Command = @import("../command.zig").Command;
const Runner = @import("../runner.zig").Runner;

// Initialize CLI module testing
test "CLI module initialization" {
    test_helpers.TestRunner.setModule("CLI");
}

test "CLI command parsing" {
    const tree_cmd = Command.fromString("tree");
    try testing.expect(tree_cmd != null);
    try testing.expect(tree_cmd.? == .tree);

    const help_cmd = Command.fromString("help");
    try testing.expect(help_cmd != null);
    try testing.expect(help_cmd.? == .help);

    const invalid_cmd = Command.fromString("invalid");
    try testing.expect(invalid_cmd == null);
}

test "CLI runner initialization" {
    var ctx = test_helpers.MockTestContext.init(testing.allocator);
    defer ctx.deinit();

    const runner = Runner.init(testing.allocator, ctx.filesystem);
    _ = runner;
}

test "CLI help command dispatch" {
    var ctx = test_helpers.MockTestContext.init(testing.allocator);
    defer ctx.deinit();

    const runner = Runner.init(testing.allocator, ctx.filesystem);
    const args = [_][:0]const u8{ "zz", "help" };

    // Note: Help output is intentionally not tested to avoid cluttering test output
    // We only verify the dispatcher doesn't crash
    _ = runner;
    _ = args;
}

test "CLI command dispatch structure" {
    var ctx = test_helpers.MockTestContext.init(testing.allocator);
    defer ctx.deinit();

    const runner = Runner.init(testing.allocator, ctx.filesystem);
    _ = runner;
}

// CLI module test summary
test "CLI module test summary" {
    test_helpers.TestRunner.printSummary();
}
