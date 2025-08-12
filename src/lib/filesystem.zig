const std = @import("std");
const FilesystemInterface = @import("../filesystem.zig").FilesystemInterface;
const DirHandle = @import("../filesystem.zig").DirHandle;

/// Common error handling patterns for filesystem operations
pub const ErrorHandling = struct {
    
    /// Standard graceful error handling for directory operations
    /// Returns null for common "safe to ignore" errors, propagates serious ones
    pub fn handleDirectoryError(err: anyerror) ?anyerror {
        return switch (err) {
            error.FileNotFound,
            error.NotDir,
            error.AccessDenied,
            error.InvalidUtf8,
            error.BadPathName,
            error.SymLinkLoop => null, // Safe to ignore
            else => err, // Propagate serious errors
        };
    }

    /// Standard graceful error handling for file operations  
    /// Returns null for common "safe to ignore" errors, propagates serious ones
    pub fn handleFileError(err: anyerror) ?anyerror {
        return switch (err) {
            error.FileNotFound,
            error.AccessDenied,
            error.IsDir,
            error.InvalidUtf8,
            error.BadPathName => null, // Safe to ignore
            else => err, // Propagate serious errors
        };
    }

    /// Standard graceful error handling for config file operations
    /// Returns null for missing files (use defaults), propagates other errors
    pub fn handleConfigFileError(err: anyerror) ?anyerror {
        return switch (err) {
            error.FileNotFound => null, // Use defaults
            else => err, // Propagate all other errors (parsing, permission, etc.)
        };
    }
};

/// Consolidated filesystem operations with common error patterns
pub const Operations = struct {
    
    /// Safely open a directory for iteration, returning null on common errors
    pub fn openDirSafely(
        filesystem: FilesystemInterface, 
        allocator: std.mem.Allocator,
        path: []const u8,
        options: std.fs.Dir.OpenDirOptions
    ) !?DirHandle {
        const dir = filesystem.openDir(allocator, path, options) catch |err| {
            if (ErrorHandling.handleDirectoryError(err)) |serious_err| {
                return serious_err;
            }
            return null; // Safe to ignore
        };
        return dir;
    }

    /// Safely stat a file, returning null on common errors
    pub fn statFileSafely(
        filesystem: FilesystemInterface,
        allocator: std.mem.Allocator,
        path: []const u8
    ) !?std.fs.File.Stat {
        const stat = filesystem.statFile(allocator, path) catch |err| {
            if (ErrorHandling.handleFileError(err)) |serious_err| {
                return serious_err;
            }
            return null; // Safe to ignore
        };
        return stat;
    }

    /// Read a config file with graceful fallbacks (DirHandle version)
    pub fn readConfigFile(
        dir: DirHandle,
        allocator: std.mem.Allocator,
        filename: []const u8,
        max_bytes: usize
    ) !?[]u8 {
        const content = dir.readFileAlloc(allocator, filename, max_bytes) catch |err| {
            if (ErrorHandling.handleConfigFileError(err)) |serious_err| {
                return serious_err;
            }
            return null; // File not found - use defaults
        };
        return content;
    }

    /// Read a config file with graceful fallbacks (std.fs.Dir version)
    pub fn readConfigFileFromStdDir(
        dir: std.fs.Dir,
        allocator: std.mem.Allocator,
        filename: []const u8,
        max_bytes: usize
    ) !?[]u8 {
        const content = dir.readFileAlloc(allocator, filename, max_bytes) catch |err| {
            if (ErrorHandling.handleConfigFileError(err)) |serious_err| {
                return serious_err;
            }
            return null; // File not found - use defaults
        };
        return content;
    }
};

/// Helper functions for common filesystem patterns
pub const Helpers = struct {
    
    /// Check if a path exists and is a directory
    pub fn isDirectory(filesystem: FilesystemInterface, allocator: std.mem.Allocator, path: []const u8) bool {
        const stat = Operations.statFileSafely(filesystem, allocator, path) catch return false;
        return if (stat) |s| s.kind == .directory else false;
    }

    /// Check if a path exists and is a file
    pub fn isFile(filesystem: FilesystemInterface, allocator: std.mem.Allocator, path: []const u8) bool {
        const stat = Operations.statFileSafely(filesystem, allocator, path) catch return false;
        return if (stat) |s| s.kind == .file else false;
    }

    /// Count entries in a directory (for performance testing)
    pub fn countDirectoryEntries(
        filesystem: FilesystemInterface,
        allocator: std.mem.Allocator,
        path: []const u8
    ) !u32 {
        const dir = Operations.openDirSafely(filesystem, allocator, path, .{ .iterate = true }) catch |err| return err;
        const dir_handle = dir orelse return 0;
        defer dir_handle.close();

        var count: u32 = 0;
        var iter = try dir_handle.iterate(allocator);
        while (try iter.next(allocator)) |_| {
            count += 1;
        }
        return count;
    }
};