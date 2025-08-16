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
    const content = try file.readToEndAlloc(allocator, 1024 * 1024 * 1024);
    return content;
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

/// Delete directory tree, ignoring if it doesn't exist
pub fn deleteTree(path: []const u8) !void {
    std.fs.cwd().deleteTree(path) catch |err| {
        // Simply ignore FileNotFound without switch
        if (err == error.FileNotFound) return;
        return err;
    };
}

/// Delete file, ignoring if it doesn't exist  
pub fn deleteFile(path: []const u8) !void {
    std.fs.cwd().deleteFile(path) catch |err| switch (err) {
        error.FileNotFound => {}, // Ignore if doesn't exist
        else => return err,
    };
}

/// Rename file or directory
pub fn rename(old_path: []const u8, new_path: []const u8) !void {
    try std.fs.cwd().rename(old_path, new_path);
}

/// Atomic move operation (rename with optional cross-device support)
pub fn atomicMove(source: []const u8, dest: []const u8) !void {
    // First try simple rename (works if same filesystem)
    std.fs.cwd().rename(source, dest) catch |err| switch (err) {
        error.RenameAcrossMountPoints, error.AccessDenied => {
            // Fall back to copy + delete for cross-device moves
            const stat = try std.fs.cwd().statFile(source);
            if (stat.kind == .directory) {
                try copyDirectory(std.heap.page_allocator, source, dest);
                try deleteTree(source);
            } else {
                try copyFile(source, dest);
                try deleteFile(source);
            }
        },
        else => return err,
    };
}

/// Copy a file from source to destination
pub fn copyFile(source_path: []const u8, dest_path: []const u8) !void {
    try std.fs.cwd().copyFile(source_path, std.fs.cwd(), dest_path, .{});
}

/// Copy a directory recursively
pub fn copyDirectory(allocator: std.mem.Allocator, source_path: []const u8, dest_path: []const u8) !void {
    // Create destination directory
    try ensureDir(dest_path);
    
    // Open source directory
    var source_dir = try std.fs.cwd().openDir(source_path, .{ .iterate = true });
    defer source_dir.close();
    
    // Iterate through source directory
    var walker = try source_dir.walk(allocator);
    defer walker.deinit();
    
    while (try walker.next()) |entry| {
        const source_item = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ source_path, entry.path });
        defer allocator.free(source_item);
        
        const dest_item = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dest_path, entry.path });
        defer allocator.free(dest_item);
        
        switch (entry.kind) {
            .directory => try ensureDir(dest_item),
            .file => {
                // Ensure parent directory exists
                if (std.fs.path.dirname(dest_item)) |parent| {
                    try ensureDir(parent);
                }
                try copyFile(source_item, dest_item);
            },
            else => {}, // Skip other file types
        }
    }
}

/// Read file with size limit
pub fn readFileWithLimit(allocator: std.mem.Allocator, path: []const u8, max_size: usize) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return file.readToEndAlloc(allocator, max_size);
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
    // Skip actual progress output in tests to avoid hanging
    const progress = Progress.init(100);
    // Just test that init works, don't actually update or finish
    _ = progress;
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

test "rename and atomic operations" {
    const testing = std.testing;
    const test_dir = "test_io_ops";
    
    // Create test directory
    try ensureDir(test_dir);
    defer deleteTree(test_dir) catch {};
    
    // Test file operations
    const test_file = test_dir ++ "/test.txt";
    const renamed_file = test_dir ++ "/renamed.txt";
    try writeFile(test_file, "test content");
    
    // Test rename
    try rename(test_file, renamed_file);
    try testing.expect(!fileExists(test_file));
    try testing.expect(fileExists(renamed_file));
    
    // Test copyFile
    const copied_file = test_dir ++ "/copied.txt";
    try copyFile(renamed_file, copied_file);
    try testing.expect(fileExists(renamed_file));
    try testing.expect(fileExists(copied_file));
    
    // Verify content
    const content = try readFile(testing.allocator, copied_file);
    defer testing.allocator.free(content);
    try testing.expectEqualStrings("test content", content);
}

test "copyDirectory" {
    const testing = std.testing;
    const source_dir = "test_copy_source";
    const dest_dir = "test_copy_dest";
    
    // Create source directory structure
    try ensureDir(source_dir);
    defer deleteTree(source_dir) catch {};
    try ensureDir(source_dir ++ "/subdir");
    try writeFile(source_dir ++ "/file1.txt", "content1");
    try writeFile(source_dir ++ "/subdir/file2.txt", "content2");
    
    // Copy directory
    try copyDirectory(testing.allocator, source_dir, dest_dir);
    defer deleteTree(dest_dir) catch {};
    
    // Verify structure
    try testing.expect(fileExists(dest_dir ++ "/file1.txt"));
    try testing.expect(fileExists(dest_dir ++ "/subdir/file2.txt"));
    
    // Verify content
    const content1 = try readFile(testing.allocator, dest_dir ++ "/file1.txt");
    defer testing.allocator.free(content1);
    try testing.expectEqualStrings("content1", content1);
    
    const content2 = try readFile(testing.allocator, dest_dir ++ "/subdir/file2.txt");
    defer testing.allocator.free(content2);
    try testing.expectEqualStrings("content2", content2);
}

test "readFileWithLimit" {
    const testing = std.testing;
    const test_file = "test_limit.txt";
    
    try writeFile(test_file, "short content");
    defer deleteFile(test_file) catch {};
    
    // Read with sufficient limit
    const content = try readFileWithLimit(testing.allocator, test_file, 1024);
    defer testing.allocator.free(content);
    try testing.expectEqualStrings("short content", content);
    
    // Read with exact limit
    const exact = try readFileWithLimit(testing.allocator, test_file, 13);
    defer testing.allocator.free(exact);
    try testing.expectEqualStrings("short content", exact);
}
