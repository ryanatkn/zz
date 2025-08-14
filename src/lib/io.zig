const std = @import("std");

/// I/O utilities consolidating file_helpers.zig and io_helpers.zig
/// Clean, idiomatic Zig with direct stdlib usage

// ============================================================================
// File Operations
// ============================================================================

/// Read file to owned string
pub fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return file.readToEndAlloc(allocator, 1024 * 1024 * 1024); // 1GB max
}

/// Read file to owned string, returns null if not found
pub fn readFileOptional(allocator: std.mem.Allocator, path: []const u8) !?[]u8 {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound, error.AccessDenied => return null,
        else => return err,
    };
    defer file.close();
    return file.readToEndAlloc(allocator, 1024 * 1024 * 1024);
}

/// Write content to file
pub fn writeFile(path: []const u8, data: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll(data);
}

/// Write content to file atomically (via temp file)
pub fn writeFileAtomic(allocator: std.mem.Allocator, path: []const u8, data: []const u8) !void {
    const temp_path = try std.fmt.allocPrint(allocator, "{s}.tmp", .{path});
    defer allocator.free(temp_path);
    
    {
        const file = try std.fs.cwd().createFile(temp_path, .{});
        defer file.close();
        try file.writeAll(data);
    }
    
    try std.fs.cwd().rename(temp_path, path);
}

/// Hash file content using xxHash
pub fn hashFile(path: []const u8) !u64 {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound, error.AccessDenied => return 0,
        else => return err,
    };
    defer file.close();

    var hasher = std.hash.XxHash64.init(0);
    var buffer: [4096]u8 = undefined;
    
    while (true) {
        const bytes_read = file.readAll(buffer[0..]) catch |err| switch (err) {
            error.BrokenPipe => break,
            else => return err,
        };
        if (bytes_read == 0) break;
        hasher.update(buffer[0..bytes_read]);
    }
    
    return hasher.final();
}

/// Check if file exists
pub fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

/// Check if path is a directory
pub fn isDirectory(path: []const u8) bool {
    const stat = std.fs.cwd().statFile(path) catch return false;
    return stat.kind == .directory;
}

/// Get file modification time
pub fn getModTime(path: []const u8) !?i64 {
    const stat = std.fs.cwd().statFile(path) catch |err| switch (err) {
        error.FileNotFound, error.AccessDenied => return null,
        else => return err,
    };
    return @as(i64, @intCast(@divFloor(stat.mtime, std.time.ns_per_s)));
}

/// Create directory (and parents if needed)
pub fn ensureDir(path: []const u8) !void {
    std.fs.cwd().makePath(path) catch |err| switch (err) {
        error.PathAlreadyExists => {}, // Already exists
        else => return err,
    };
}

// ============================================================================
// Standard I/O
// ============================================================================

/// Write to stdout
pub fn writeStdout(text: []const u8) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(text);
}

/// Write to stderr
pub fn writeStderr(text: []const u8) !void {
    const stderr = std.io.getStdErr().writer();
    try stderr.writeAll(text);
}

/// Print to stdout with formatting
pub fn printStdout(comptime format: []const u8, args: anytype) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print(format, args);
}

/// Print to stderr with formatting
pub fn printStderr(comptime format: []const u8, args: anytype) !void {
    const stderr = std.io.getStdErr().writer();
    try stderr.print(format, args);
}

// ============================================================================
// Buffered I/O
// ============================================================================

/// Buffered stdout writer
pub const BufferedStdout = struct {
    writer: std.io.BufferedWriter(4096, std.fs.File.Writer),
    
    pub fn init() BufferedStdout {
        const stdout = std.io.getStdOut().writer();
        return BufferedStdout{
            .writer = std.io.bufferedWriter(stdout),
        };
    }
    
    pub fn write(self: *BufferedStdout, bytes: []const u8) !void {
        try self.writer.writer().writeAll(bytes);
    }
    
    pub fn print(self: *BufferedStdout, comptime format: []const u8, args: anytype) !void {
        try self.writer.writer().print(format, args);
    }
    
    pub fn flush(self: *BufferedStdout) !void {
        try self.writer.flush();
    }
    
    pub fn deinit(self: *BufferedStdout) void {
        self.flush() catch {};
    }
};

/// Buffered stderr writer
pub const BufferedStderr = struct {
    writer: std.io.BufferedWriter(4096, std.fs.File.Writer),
    
    pub fn init() BufferedStderr {
        const stderr = std.io.getStdErr().writer();
        return BufferedStderr{
            .writer = std.io.bufferedWriter(stderr),
        };
    }
    
    pub fn write(self: *BufferedStderr, bytes: []const u8) !void {
        try self.writer.writer().writeAll(bytes);
    }
    
    pub fn print(self: *BufferedStderr, comptime format: []const u8, args: anytype) !void {
        try self.writer.writer().print(format, args);
    }
    
    pub fn flush(self: *BufferedStderr) !void {
        try self.writer.flush();
    }
    
    pub fn deinit(self: *BufferedStderr) void {
        self.flush() catch {};
    }
};

// ============================================================================
// Color Support
// ============================================================================

/// ANSI color codes
pub const Color = struct {
    pub const reset = "\x1b[0m";
    pub const bold = "\x1b[1m";
    pub const dim = "\x1b[2m";
    pub const red = "\x1b[31m";
    pub const green = "\x1b[32m";
    pub const yellow = "\x1b[33m";
    pub const blue = "\x1b[34m";
    pub const cyan = "\x1b[36m";
    pub const gray = "\x1b[90m";
};

/// Check if stdout supports colors
pub fn supportsColors() bool {
    return std.io.getStdOut().isTty();
}

/// Print colored text to stdout
pub fn printColored(comptime color: []const u8, text: []const u8) !void {
    if (supportsColors()) {
        try printStdout("{s}{s}{s}", .{ color, text, Color.reset });
    } else {
        try printStdout("{s}", .{text});
    }
}

/// Print colored text with formatting
pub fn printColoredFmt(comptime color: []const u8, comptime format: []const u8, args: anytype) !void {
    if (supportsColors()) {
        try printStdout("{s}" ++ format ++ "{s}", .{color} ++ args ++ .{Color.reset});
    } else {
        try printStdout(format, args);
    }
}

// ============================================================================
// Progress Reporting
// ============================================================================

/// Simple progress reporter
pub const Progress = struct {
    total: usize,
    current: usize,
    last_percent: u8,
    writer: BufferedStdout,
    
    pub fn init(total: usize) Progress {
        return Progress{
            .total = total,
            .current = 0,
            .last_percent = 255, // Invalid to force first update
            .writer = BufferedStdout.init(),
        };
    }
    
    pub fn update(self: *Progress, current: usize) !void {
        self.current = current;
        const percent = if (self.total > 0) @as(u8, @intCast((current * 100) / self.total)) else 0;
        
        if (percent != self.last_percent) {
            try self.writer.print("\rProgress: {d}% ({d}/{d})", .{ percent, current, self.total });
            try self.writer.flush();
            self.last_percent = percent;
        }
    }
    
    pub fn finish(self: *Progress) !void {
        try self.writer.write("\n");
        try self.writer.flush();
    }
    
    pub fn deinit(self: *Progress) void {
        self.writer.deinit();
    }
};

// ============================================================================
// Environment Variables
// ============================================================================

/// Get environment variable with default
pub fn getEnvVar(allocator: std.mem.Allocator, name: []const u8, default_value: []const u8) ![]u8 {
    return std.process.getEnvVarOwned(allocator, name) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => try allocator.dupe(u8, default_value),
        else => err,
    };
}

/// Check if environment variable is truthy
pub fn isEnvVarTrue(allocator: std.mem.Allocator, name: []const u8) bool {
    const value = std.process.getEnvVarOwned(allocator, name) catch return false;
    defer allocator.free(value);
    
    return std.mem.eql(u8, value, "1") or 
           std.mem.eql(u8, value, "true") or 
           std.mem.eql(u8, value, "TRUE") or
           std.mem.eql(u8, value, "yes") or
           std.mem.eql(u8, value, "YES");
}

test "file operations" {
    const testing = std.testing;
    
    // Test file existence
    try testing.expect(!fileExists("non_existent_file.txt"));
    
    // Test hash of non-existent file
    const hash = try hashFile("non_existent_file.txt");
    try testing.expect(hash == 0);
}

test "buffered writers" {
    var stdout = BufferedStdout.init();
    defer stdout.deinit();
    
    var stderr = BufferedStderr.init();
    defer stderr.deinit();
    
    // Just test they can be created
}

test "progress reporter" {
    var progress = Progress.init(100);
    defer progress.deinit();
    
    try progress.update(50);
    try progress.finish();
}

test "environment variables" {
    const testing = std.testing;
    
    const value = try getEnvVar(testing.allocator, "NONEXISTENT_VAR", "default");
    defer testing.allocator.free(value);
    try testing.expectEqualStrings("default", value);
    
    try testing.expect(!isEnvVarTrue(testing.allocator, "NONEXISTENT_VAR"));
}

test "color support" {
    // Just test it doesn't crash
    _ = supportsColors();
}