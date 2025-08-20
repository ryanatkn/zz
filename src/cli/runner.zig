const std = @import("std");

// Core CLI components
const filesystem = @import("../lib/filesystem/interface.zig");
const command_mod = @import("command.zig");
const Help = @import("help.zig");
const errors = @import("../lib/core/errors.zig");
const reporting = @import("../lib/core/reporting.zig");

// Command modules
const tree = @import("../tree/main.zig");
const prompt = @import("../prompt/main.zig");
const benchmark = @import("../benchmark/main.zig");
const format = @import("../format/main.zig");
const echo = @import("../echo/main.zig");
const demo = @import("../demo.zig");
const deps = @import("../deps/main.zig");

// Type aliases
const FilesystemInterface = filesystem.FilesystemInterface;
const Command = command_mod.Command;

pub const Runner = struct {
    allocator: std.mem.Allocator,
    filesystem: FilesystemInterface,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, fs: FilesystemInterface) Self {
        return Self{
            .allocator = allocator,
            .filesystem = fs,
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
                    const error_msg = errors.getMessage(err);
                    reporting.reportError("Tree command failed: {s}", .{error_msg}) catch {};
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
                    const error_msg = errors.getMessage(err);
                    reporting.reportError("Benchmark command failed: {s}", .{error_msg}) catch {};
                    return err;
                };
            },
            .format => {
                // Pass full args and filesystem to format module
                format.run(self.allocator, self.filesystem, args) catch |err| {
                    const error_msg = errors.getMessage(err);
                    reporting.reportError("Format command failed: {s}", .{error_msg}) catch {};
                    return err;
                };
            },
            .echo => {
                // Pass full args to echo module (echo doesn't need filesystem)
                echo.run(self.allocator, args) catch |err| {
                    const error_msg = errors.getMessage(err);
                    reporting.reportError("Echo command failed: {s}", .{error_msg}) catch {};
                    return err;
                };
            },
            .demo => {
                // Pass full args to demo module (demo doesn't need filesystem)
                demo.run(self.allocator, args) catch |err| {
                    const error_msg = errors.getMessage(err);
                    reporting.reportError("Demo command failed: {s}", .{error_msg}) catch {};
                    return err;
                };
            },
            .deps => {
                // Pass full args and filesystem to deps module
                deps.run(self.allocator, self.filesystem, args) catch |err| {
                    const error_msg = errors.getMessage(err);
                    reporting.reportError("Deps command failed: {s}", .{error_msg}) catch {};
                    return err;
                };
            },
        }
    }
};
