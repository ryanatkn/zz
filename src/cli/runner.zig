const std = @import("std");

const Command = @import("command.zig").Command;
const Help = @import("help.zig");
const tree = @import("../tree/main.zig");
const prompt = @import("../prompt/main.zig");

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
                // Pass full args to tree (it will handle its own parsing)
                try tree.run(self.allocator, args);
            },
            .prompt => {
                // Pass full args to prompt (it will handle its own parsing)
                prompt.run(self.allocator, args) catch |err| {
                    if (err == error.PatternsNotMatched) {
                        // Error already printed to stderr, exit cleanly
                        std.process.exit(1);
                    }
                    if (err == error.BrokenPipe) {
                        // Output was piped and reader closed early (e.g., | head)
                        // This is normal, exit cleanly
                        std.process.exit(0);
                    }
                    return err;
                };
            },
        }
    }
};
