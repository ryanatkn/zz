const std = @import("std");
const testing = std.testing;
const test_helpers = @import("../../test_helpers.zig");
const Command = @import("../command.zig").Command;
const Runner = @import("../runner.zig").Runner;

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

    try runner.run(.help, @constCast(args[0..]));
}

test "CLI command dispatch structure" {
    var ctx = test_helpers.MockTestContext.init(testing.allocator);
    defer ctx.deinit();

    const runner = Runner.init(testing.allocator, ctx.filesystem);
    _ = runner;
}
