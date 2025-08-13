const std = @import("std");

/// Unified file reading helpers to eliminate duplicate patterns across the codebase
pub const FileHelpers = struct {
    /// Safe file reader with standardized error handling
    pub const SafeFileReader = struct {
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) SafeFileReader {
            return .{ .allocator = allocator };
        }

        /// Read file to owned string with graceful error handling
        /// Returns null for FileNotFound, propagates other errors
        pub fn readToStringOptional(self: SafeFileReader, file_path: []const u8, max_size: usize) !?[]u8 {
            const file = std.fs.cwd().openFile(file_path, .{}) catch |err| switch (err) {
                error.FileNotFound, error.AccessDenied => return null,
                else => return err,
            };
            defer file.close();
            
            const content = try file.readToEndAlloc(self.allocator, max_size);
            return content;
        }

        /// Read file to owned string, error if file doesn't exist
        pub fn readToString(self: SafeFileReader, file_path: []const u8, max_size: usize) ![]u8 {
            const file = try std.fs.cwd().openFile(file_path, .{});
            defer file.close();
            
            return file.readToEndAlloc(self.allocator, max_size);
        }

        /// Read file to provided buffer, returns bytes read
        pub fn readToBuffer(self: SafeFileReader, file_path: []const u8, buffer: []u8) !usize {
            _ = self;
            const file = try std.fs.cwd().openFile(file_path, .{});
            defer file.close();
            
            return file.readAll(buffer);
        }
    };

    /// Fast file hashing using xxHash - consolidated from multiple locations
    pub fn hashFile(allocator: std.mem.Allocator, file_path: []const u8) !u64 {
        _ = allocator;
        const file = std.fs.cwd().openFile(file_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return 0,
            error.AccessDenied => return 0,
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

    /// Get file modification time with graceful error handling
    pub fn getModTime(file_path: []const u8) !?i64 {
        const stat = std.fs.cwd().statFile(file_path) catch |err| switch (err) {
            error.FileNotFound, error.AccessDenied => return null,
            else => return err,
        };
        return @as(i64, @intCast(@divFloor(stat.mtime, std.time.ns_per_s)));
    }

    /// Check if file exists and is accessible
    pub fn exists(file_path: []const u8) bool {
        std.fs.cwd().access(file_path, .{}) catch return false;
        return true;
    }

    /// Safe directory creation with error handling
    pub fn ensureDir(dir_path: []const u8) !void {
        std.fs.cwd().makeDir(dir_path) catch |err| switch (err) {
            error.PathAlreadyExists => {}, // Already exists, that's fine
            else => return err,
        };
    }

    /// Write content to file atomically
    pub fn writeAtomic(file_path: []const u8, content: []const u8) !void {
        const temp_path = try std.fmt.allocPrint(std.heap.page_allocator, "{s}.tmp", .{file_path});
        defer std.heap.page_allocator.free(temp_path);
        
        {
            const file = try std.fs.cwd().createFile(temp_path, .{});
            defer file.close();
            try file.writeAll(content);
        }
        
        try std.fs.cwd().rename(temp_path, file_path);
    }
};

/// Configuration file reader with ZON-specific error handling
pub const ConfigFileReader = struct {
    allocator: std.mem.Allocator,
    reader: FileHelpers.SafeFileReader,

    pub fn init(allocator: std.mem.Allocator) ConfigFileReader {
        return .{
            .allocator = allocator,
            .reader = FileHelpers.SafeFileReader.init(allocator),
        };
    }

    /// Read configuration file with enhanced error context
    pub fn readConfigFile(self: ConfigFileReader, file_path: []const u8) !?[]u8 {
        return self.reader.readToStringOptional(file_path, 1024 * 1024) catch |err| switch (err) {
            error.SystemResources => {
                std.log.warn("Insufficient system resources reading config: {s}", .{file_path});
                return null;
            },
            error.IsDir => {
                std.log.warn("Expected file but found directory: {s}", .{file_path});
                return null;
            },
            error.FileBusy => {
                std.log.warn("Config file is busy: {s}", .{file_path});
                return null;
            },
            else => return err,
        };
    }
};

test "SafeFileReader basic functionality" {
    const testing = std.testing;
    
    var reader = FileHelpers.SafeFileReader.init(testing.allocator);
    
    // Test reading non-existent file returns null
    const result = try reader.readToStringOptional("non_existent_file.txt", 1024);
    try testing.expect(result == null);
    
    // Test file existence check
    try testing.expect(!FileHelpers.exists("non_existent_file.txt"));
}

test "FileHelpers hashing" {
    const testing = std.testing;
    
    // Test hashing non-existent file returns 0
    const hash = try FileHelpers.hashFile(testing.allocator, "non_existent_file.txt");
    try testing.expect(hash == 0);
}