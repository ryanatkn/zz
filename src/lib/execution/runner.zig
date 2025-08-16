const std = @import("std");
const process = @import("../core/process.zig");

/// Re-export CommandResult from process module for compatibility
pub const CommandResult = process.CommandResult;

/// Terminal interface type for animation support
/// Execute a command and capture its output
pub fn executeCommand(
    allocator: std.mem.Allocator,
    command: []const u8,
    args: []const []const u8,
) !CommandResult {
    return executeCommandWithAnimation(allocator, command, args, null);
}

/// Execute a command with optional animation during execution
pub fn executeCommandWithAnimation(
    allocator: std.mem.Allocator,
    command: []const u8,
    args: []const []const u8,
    terminal: anytype,
) !CommandResult {
    // Build the full command args
    var argv = std.ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    // Use the built zz binary
    try argv.append("./zig-out/bin/zz");
    try argv.append(command);
    for (args) |arg| {
        try argv.append(arg);
    }

    // Show stylized message for long-running commands
    if (@TypeOf(terminal) != @TypeOf(null)) {
        if (std.mem.eql(u8, command, "benchmark")) {
            // Use subtle pulse effect for better visual feedback
            try terminal.showPulse(2, "⚡", "Running benchmarks...");
            try terminal.writer.writeAll(" "); // Add space to prevent cursor from jumping
            std.time.sleep(100 * std.time.ns_per_ms); // Brief pause to show the effect
            try terminal.writer.writeAll("\n");
        }
    }

    // Use our process utilities for execution
    return process.executeCommand(allocator, argv.items);
}

/// Execute a command with a timeout
pub fn executeCommandWithTimeout(
    allocator: std.mem.Allocator,
    command: []const u8,
    args: []const []const u8,
    timeout_ms: u64,
) !CommandResult {
    // For now, just use regular execution
    // TODO: Implement timeout mechanism if needed
    _ = timeout_ms;
    return executeCommand(allocator, command, args);
}

/// Execute a command and return only stdout (for simple cases)
pub fn executeSimple(
    allocator: std.mem.Allocator,
    command: []const u8,
    args: []const []const u8,
) ![]u8 {
    const result = try executeCommand(allocator, command, args);
    defer allocator.free(result.stderr);

    if (result.exit_code != 0) {
        allocator.free(result.stdout);
        return error.CommandFailed;
    }

    return result.stdout;
}

/// Format command line for display
pub fn formatCommandLine(
    allocator: std.mem.Allocator,
    command: []const u8,
    args: []const []const u8,
) ![]u8 {
    var cmd_line = std.ArrayList(u8).init(allocator);
    errdefer cmd_line.deinit();

    try cmd_line.appendSlice("zz ");
    try cmd_line.appendSlice(command);

    for (args) |arg| {
        try cmd_line.append(' ');

        // Quote args with spaces or special characters
        const needs_quoting = std.mem.indexOfAny(u8, arg, " \t\n'\"\\$") != null;
        if (needs_quoting) {
            try cmd_line.append('\'');
            try cmd_line.appendSlice(arg);
            try cmd_line.append('\'');
        } else {
            try cmd_line.appendSlice(arg);
        }
    }

    return cmd_line.toOwnedSlice();
}

/// Truncate output to a maximum number of lines
pub fn truncateOutput(
    allocator: std.mem.Allocator,
    output: []const u8,
    max_lines: usize,
) ![]u8 {
    if (max_lines == 0) {
        return allocator.dupe(u8, output);
    }

    var line_count: usize = 0;

    for (output, 0..) |char, i| {
        if (char == '\n') {
            line_count += 1;
            if (line_count >= max_lines) {
                const suffix = "\n...";
                const truncated = try allocator.alloc(u8, i + suffix.len);
                @memcpy(truncated[0..i], output[0..i]);
                @memcpy(truncated[i .. i + suffix.len], suffix);
                return truncated;
            }
        }
    }

    return allocator.dupe(u8, output);
}

/// Check if zz binary exists and is executable
pub fn checkZzBinary() !void {
    const file = std.fs.cwd().openFile("./zig-out/bin/zz", .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Error: zz binary not found. Please run 'zig build' first.\n", .{});
            return error.BinaryNotFound;
        }
        return err;
    };
    defer file.close();

    const stat = try file.stat();
    if (stat.kind != .file) {
        return error.NotAFile;
    }

    // Check if executable (Unix-specific)
    // On POSIX systems, check execute permission
    // This is a simplified check - proper implementation would use stat mode
}

/// Run a series of commands and collect all outputs
pub const BatchResult = struct {
    outputs: []CommandResult,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *BatchResult) void {
        for (self.outputs) |*output| {
            output.deinit();
        }
        self.allocator.free(self.outputs);
    }
};

pub fn executeBatch(
    allocator: std.mem.Allocator,
    commands: []const struct {
        command: []const u8,
        args: []const []const u8,
    },
) !BatchResult {
    var outputs = try allocator.alloc(CommandResult, commands.len);
    errdefer {
        for (outputs[0..commands.len]) |*output| {
            output.deinit();
        }
        allocator.free(outputs);
    }

    for (commands, 0..) |cmd, i| {
        outputs[i] = try executeCommand(allocator, cmd.command, cmd.args);
    }

    return BatchResult{
        .outputs = outputs,
        .allocator = allocator,
    };
}
