const std = @import("std");
const filesystem = @import("../lib/filesystem/interface.zig");

const command_mod = @import("command.zig");
const help_mod = @import("help.zig");
const runner_mod = @import("runner.zig");

const FilesystemInterface = filesystem.FilesystemInterface;

pub const Command = command_mod.Command;
pub const Help = help_mod;
pub const Runner = runner_mod.Runner;

pub fn run(allocator: std.mem.Allocator, fs: FilesystemInterface) !void {
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

    const runner = Runner.init(allocator, fs);
    try runner.run(command, @ptrCast(args));
}
