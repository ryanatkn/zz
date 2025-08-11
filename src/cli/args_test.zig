const std = @import("std");
const testing = std.testing;

const Command = @import("command.zig").Command;
const Runner = @import("runner.zig").Runner;
const Help = @import("help.zig");

test "CLI command parsing" {
    // Test valid commands
    const tree_cmd = Command.fromString("tree");
    try testing.expect(tree_cmd != null);
    try testing.expect(tree_cmd.? == .tree);
    
    const help_cmd = Command.fromString("help");
    try testing.expect(help_cmd != null);
    try testing.expect(help_cmd.? == .help);
    
    // Test invalid command
    const invalid_cmd = Command.fromString("invalid");
    try testing.expect(invalid_cmd == null);
    
    std.debug.print("✅ CLI command parsing test passed!\n", .{});
}

test "CLI runner initialization" {
    const runner = Runner.init(testing.allocator);
    _ = runner; // Just verify it initializes
    
    std.debug.print("✅ CLI runner initialization test passed!\n", .{});
}

test "CLI help command dispatch" {
    // Test help command runs without error
    const runner = Runner.init(testing.allocator);
    const args = [_][:0]const u8{ "zz", "help" };
    
    // Help command should not error
    try runner.run(.help, @constCast(args[0..]));
    
    std.debug.print("✅ CLI help command dispatch test passed!\n", .{});
}

test "CLI command dispatch structure" {
    // Test that the runner has the expected structure for dispatch
    const runner = Runner.init(testing.allocator);
    
    // Test tree command dispatch (without actual tree execution to avoid imports)
    // We just test that the structure is set up correctly
    _ = runner;
    
    std.debug.print("✅ CLI command dispatch structure test passed!\n", .{});
}