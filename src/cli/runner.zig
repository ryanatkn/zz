const std = @import("std");
const FilesystemInterface = @import("../filesystem/interface.zig").FilesystemInterface;

const Command = @import("command.zig").Command;
const Help = @import("help.zig");
const tree = @import("../tree/main.zig");
const prompt = @import("../prompt/main.zig");
const benchmark = @import("../benchmark/main.zig");
const format = @import("../format/main.zig");
const errors = @import("../lib/errors.zig");

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
                tree.run(self.allocator, self.filesystem, args) catch |err| {
                    const stderr = std.io.getStdErr().writer();
                    const error_msg = errors.getMessage(err);
                    stderr.print("Tree command failed: {s}\n", .{error_msg}) catch {};
                    return err;
                };
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
                benchmark.run(self.allocator, args) catch |err| {
                    const stderr = std.io.getStdErr().writer();
                    const error_msg = errors.getMessage(err);
                    stderr.print("Benchmark command failed: {s}\n", .{error_msg}) catch {};
                    return err;
                };
            },
            .format => {
                // Pass full args and filesystem to format module
                format.run(self.allocator, self.filesystem, args) catch |err| {
                    const stderr = std.io.getStdErr().writer();
                    const error_msg = errors.getMessage(err);
                    stderr.print("Format command failed: {s}\n", .{error_msg}) catch {};
                    return err;
                };
            },
        }
    }
};
