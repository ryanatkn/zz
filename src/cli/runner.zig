const std = @import("std");
const Command = @import("command.zig").Command;
const Help = @import("help.zig");
const tree = @import("../tree/main.zig");
const hex = @import("../hex/main.zig");

pub const Runner = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    pub fn run(self: Self, command: Command, args: [][:0]const u8) !void {
        switch (command) {
            .help => {
                Help.show(args[0]);
            },
            .tree => {
                // Skip program name and command, pass remaining args to tree
                const tree_args = args[1..];
                try tree.run(self.allocator, tree_args);
            },
            .hex => {
                try hex.run(self.allocator);
            },
        }
    }
};
