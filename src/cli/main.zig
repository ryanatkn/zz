const std = @import("std");
const FilesystemInterface = @import("../filesystem.zig").FilesystemInterface;

pub const Command = @import("command.zig").Command;
pub const Help = @import("help.zig");
pub const Runner = @import("runner.zig").Runner;

pub fn run(allocator: std.mem.Allocator, filesystem: FilesystemInterface) !void {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        Help.show(args[0]);
        return; // Exit normally when showing help
    }

    const command = Command.fromString(args[1]) orelse {
        std.debug.print("Unknown command: {s}\n\n", .{args[1]});
        Help.show(args[0]);
        std.process.exit(1);
    };

    const runner = Runner.init(allocator, filesystem);
    try runner.run(command, @ptrCast(args));
}
