const std = @import("std");
const FilesystemInterface = @import("../lib/filesystem/interface.zig").FilesystemInterface;

pub const Command = @import("command.zig").Command;
pub const Help = @import("help.zig");
pub const Runner = @import("runner.zig").Runner;

pub fn run(allocator: std.mem.Allocator, filesystem: FilesystemInterface) !void {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        Help.showBrief(args[0]);
        return; // Exit normally when showing help
    }

    // Check for help flags
    if (std.mem.eql(u8, args[1], "-h")) {
        Help.showBrief(args[0]);
        return;
    } else if (std.mem.eql(u8, args[1], "--help")) {
        Help.show(args[0]);
        return;
    } else if (std.mem.eql(u8, args[1], "help")) {
        // 'zz help' behaves like 'zz --help'
        Help.show(args[0]);
        return;
    }

    const command = Command.fromString(args[1]) orelse {
        std.debug.print("Unknown command: {s}\n\n", .{args[1]});
        Help.showBrief(args[0]);
        std.process.exit(1);
    };

    const runner = Runner.init(allocator, filesystem);
    try runner.run(command, @ptrCast(args));
}
