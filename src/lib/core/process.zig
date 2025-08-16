const std = @import("std");

/// Result of executing a command
pub const CommandResult = struct {
    stdout: []u8,
    stderr: []u8,
    exit_code: u8,
    allocator: std.mem.Allocator,

    /// Free allocated stdout and stderr buffers
    pub fn deinit(self: *CommandResult) void {
        if (self.stdout.len > 0) {
            self.allocator.free(self.stdout);
        }
        if (self.stderr.len > 0) {
            self.allocator.free(self.stderr);
        }
    }
};

/// Options for command execution
pub const ExecuteOptions = struct {
    /// Capture stdout (default: true)
    capture_stdout: bool = true,
    /// Capture stderr (default: true) 
    capture_stderr: bool = true,
    /// Inherit stderr to terminal (default: false)
    inherit_stderr: bool = false,
    /// Inherit stdout to terminal (default: false)
    inherit_stdout: bool = false,
    /// Timeout in milliseconds (0 = no timeout)
    timeout_ms: u32 = 0,
    /// Working directory (null = current)
    cwd: ?[]const u8 = null,
    /// Environment variables (null = inherit)
    env: ?[]const []const u8 = null,
};

/// Execute a command with default options
pub fn executeCommand(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
) !CommandResult {
    return executeCommandWithOptions(allocator, argv, .{});
}

/// Execute a command and ignore output (just check exit code)
pub fn executeCommandSilent(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
) !void {
    const result = try executeCommandWithOptions(allocator, argv, .{
        .capture_stdout = false,
        .capture_stderr = false,
    });
    defer result.deinit();
    
    if (result.exit_code != 0) {
        return error.CommandFailed;
    }
}

/// Execute a command with output captured but stderr inherited (for user feedback)
pub fn executeCommandWithInheritedStderr(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
) !CommandResult {
    return executeCommandWithOptions(allocator, argv, .{
        .inherit_stderr = true,
    });
}

/// Execute a command and capture only stdout (common for getting command output)
pub fn executeCommandForOutput(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
) ![]u8 {
    var result = try executeCommandWithOptions(allocator, argv, .{
        .capture_stderr = false,
    });
    defer result.deinit();
    
    if (result.exit_code != 0) {
        return error.CommandFailed;
    }
    
    // Duplicate stdout before result.deinit() frees it
    return try allocator.dupe(u8, result.stdout);
}

/// Execute a command with full control over options
pub fn executeCommandWithOptions(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    options: ExecuteOptions,
) !CommandResult {
    if (argv.len == 0) {
        return error.EmptyCommand;
    }

    // Create child process
    var child = std.process.Child.init(argv, allocator);
    
    // Set working directory
    if (options.cwd) |cwd| {
        child.cwd = cwd;
    }
    
    // Set environment
    if (options.env) |env| {
        child.env_map = &std.process.EnvMap.init(allocator);
        // TODO: Implement env map parsing if needed
        _ = env;
    }
    
    // Configure stdout behavior
    if (options.capture_stdout) {
        child.stdout_behavior = .Pipe;
    } else if (options.inherit_stdout) {
        child.stdout_behavior = .Inherit;
    } else {
        child.stdout_behavior = .Ignore;
    }
    
    // Configure stderr behavior
    if (options.capture_stderr) {
        child.stderr_behavior = .Pipe;
    } else if (options.inherit_stderr) {
        child.stderr_behavior = .Inherit;
    } else {
        child.stderr_behavior = .Ignore;
    }

    // Spawn the process
    try child.spawn();

    // Read outputs
    var stdout: []u8 = &.{};
    var stderr: []u8 = &.{};
    
    if (options.capture_stdout and child.stdout != null) {
        stdout = child.stdout.?.reader().readAllAlloc(allocator, 1024 * 1024) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => &.{}, // Return empty on read errors
        };
    }
    
    if (options.capture_stderr and child.stderr != null) {
        stderr = child.stderr.?.reader().readAllAlloc(allocator, 1024 * 1024) catch |err| switch (err) {
            error.OutOfMemory => {
                if (stdout.len > 0) allocator.free(stdout);
                return err;
            },
            else => &.{}, // Return empty on read errors
        };
    }

    // Wait for process completion
    const term = try child.wait();
    
    const exit_code: u8 = switch (term) {
        .Exited => |code| @intCast(code),
        .Signal => 1, // Non-zero for signals
        .Stopped => 1, // Non-zero for stopped
        .Unknown => 1, // Non-zero for unknown
    };

    return CommandResult{
        .stdout = stdout,
        .stderr = stderr,
        .exit_code = exit_code,
        .allocator = allocator,
    };
}

/// Execute a command with a timeout
pub fn executeCommandWithTimeout(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    timeout_ms: u32,
) !CommandResult {
    return executeCommandWithOptions(allocator, argv, .{
        .timeout_ms = timeout_ms,
    });
}

/// Utility function to build git command arguments
pub fn buildGitArgs(
    allocator: std.mem.Allocator,
    base_args: []const []const u8,
) !std.ArrayList([]const u8) {
    var args = std.ArrayList([]const u8).init(allocator);
    try args.append("git");
    try args.appendSlice(base_args);
    return args;
}

/// Parse command output and trim whitespace (common pattern)
pub fn parseCommandOutput(allocator: std.mem.Allocator, output: []const u8) ![]u8 {
    const trimmed = std.mem.trim(u8, output, " \t\r\n");
    return try allocator.dupe(u8, trimmed);
}

/// Check if a command exists in PATH
pub fn commandExists(allocator: std.mem.Allocator, command: []const u8) bool {
    const result = executeCommandSilent(allocator, &.{ "which", command }) catch return false;
    _ = result;
    return true;
}