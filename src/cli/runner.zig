const std = @import("std");
const Command = @import("command.zig").Command;
const Help = @import("help.zig");
const tree = @import("../tree/main.zig");

pub const Runner = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    pub fn run(self: Self, command: Command, args: [][:0]u8) !void {
        switch (command) {
            .help => {
                Help.show(args[0]);
            },
            .tree => {
                // Skip program name and command, pass remaining args to tree
                const tree_args = args[1..];
                try tree.run(self.allocator, tree_args);
            },
            .yar => {
                try self.runYarGame();
            },
        }
    }

    fn runYarGame(self: Self) !void {
        std.debug.print("Starting YAR - Yet Another RPG...\n", .{});

        // Change to the src/yar directory and compile/run the Zig game with static library
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "sh", "-c", "cd src/yar && zig run main.zig -I../raylib/include ../raylib/lib/libraylib.a -lGL -lm -lpthread -ldl -lrt -lX11 -lc" },
            .cwd = ".",
        }) catch |err| {
            std.debug.print("Failed to run YAR game: {}\n", .{err});
            return;
        };

        if (result.term.Exited != 0) {
            std.debug.print("YAR game failed to compile or run\n", .{});
            if (result.stderr.len > 0) {
                std.debug.print("Error: {s}\n", .{result.stderr});
            }
        }

        self.allocator.free(result.stdout);
        self.allocator.free(result.stderr);
    }
};
