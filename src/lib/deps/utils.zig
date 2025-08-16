const std = @import("std");
const path = @import("../core/path.zig");
const errors = @import("../core/errors.zig");
const io = @import("../core/io.zig");

/// Utility functions for dependency management
pub const Utils = struct {
    /// Build a path by joining components (delegates to existing path utilities)
    pub fn buildPath(allocator: std.mem.Allocator, parts: []const []const u8) ![]u8 {
        return path.joinPaths(allocator, parts);
    }
    
    /// Check if a directory exists
    pub fn directoryExists(dir_path: []const u8) bool {
        return io.isDirectory(dir_path);
    }
    
    /// Check if a file exists
    pub fn fileExists(file_path: []const u8) bool {
        return io.fileExists(file_path);
    }
    
    /// Create directory if it doesn't exist (uses existing error handling)
    pub fn ensureDirectory(dir_path: []const u8) !void {
        return errors.makeDir(dir_path);
    }
    
    /// Read file content or return null if not found
    pub fn readFileOptional(allocator: std.mem.Allocator, file_path: []const u8, max_size: usize) !?[]u8 {
        _ = max_size; // Use io.zig's default size
        return io.readFileOptional(allocator, file_path);
    }
    
    /// Remove 'v' prefix from version string if present
    pub fn cleanVersionString(version: []const u8) []const u8 {
        return if (std.mem.startsWith(u8, version, "v"))
            version[1..]
        else
            version;
    }
    
    /// Extract the base name from a path (delegates to existing path utilities)
    pub fn basename(file_path: []const u8) []const u8 {
        return path.basename(file_path);
    }
};

test "buildPath" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    const path1 = try Utils.buildPath(allocator, &.{"deps", "tree-sitter"});
    defer allocator.free(path1);
    try testing.expectEqualStrings("deps/tree-sitter", path1);
    
    const path2 = try Utils.buildPath(allocator, &.{"a", "b", "c"});
    defer allocator.free(path2);
    try testing.expectEqualStrings("a/b/c", path2);
    
    const path3 = try Utils.buildPath(allocator, &.{});
    defer allocator.free(path3);
    try testing.expectEqualStrings("", path3);
    
    const path4 = try Utils.buildPath(allocator, &.{"single"});
    defer allocator.free(path4);
    try testing.expectEqualStrings("single", path4);
}

test "cleanVersionString" {
    const testing = std.testing;
    
    try testing.expectEqualStrings("1.2.3", Utils.cleanVersionString("v1.2.3"));
    try testing.expectEqualStrings("1.2.3", Utils.cleanVersionString("1.2.3"));
    try testing.expectEqualStrings("", Utils.cleanVersionString("v"));
    try testing.expectEqualStrings("main", Utils.cleanVersionString("main"));
}

test "basename" {
    const testing = std.testing;
    
    try testing.expectEqualStrings("file.txt", Utils.basename("/path/to/file.txt"));
    try testing.expectEqualStrings("dir", Utils.basename("/path/to/dir"));
    try testing.expectEqualStrings("file.txt", Utils.basename("file.txt"));
    try testing.expectEqualStrings("", Utils.basename("/"));
    try testing.expectEqualStrings("", Utils.basename(""));
}