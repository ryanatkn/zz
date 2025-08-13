const std = @import("std");
const FilesystemInterface = @import("../filesystem/interface.zig").FilesystemInterface;

const Command = @import("command.zig").Command;
const Help = @import("help.zig");
const tree = @import("../tree/main.zig");
const prompt = @import("../prompt/main.zig");
const benchmark = @import("../benchmark/main.zig");

pub const Runner = struct {
    allocator: std.mem.Allocator,
    filesystem: FilesystemInterface,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, filesystem: FilesystemInterface) Self {
        return Self{
            .allocator = allocator,
            .filesystem = filesystem,
        };
    }

    pub fn run(self: Self, command: Command, args: [][:0]const u8) !void {
        switch (command) {
            .help => {
                // This case should never be reached as help is handled in main.zig
                // But we keep it for completeness and backward compatibility
                Help.show(args[0]);
            },
            .tree => {
                // Pass full args and filesystem to tree
                try tree.run(self.allocator, self.filesystem, args);
            },
            .prompt => {
                // Pass full args and filesystem to prompt
                prompt.run(self.allocator, self.filesystem, args) catch |err| {
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
            .benchmark => {
                // Pass full args to benchmark module
                try benchmark.run(self.allocator, args);
            },
        }
    }
};
