const std = @import("std");

// POSIX-only path utilities - optimized for lean builds
// We implement our own instead of std.fs.path because:
// 1. std.fs.path includes Windows/cross-platform logic we don't need
// 2. We can hardcode POSIX assumptions (/ separator) for better performance
// 3. Smaller binary size without cross-platform overhead
// 4. Predictable behavior - no runtime platform detection

/// Check if a filename represents a hidden file (starts with '.')
pub fn isHiddenFile(filename: []const u8) bool {
    return filename.len > 0 and filename[0] == '.';
}

/// Check if a glob pattern explicitly matches hidden files (starts with '.')
pub fn patternMatchesHidden(pattern: []const u8) bool {
    return pattern.len > 0 and pattern[0] == '.';
}

/// Join path components with '/' separator - simple two-component version
pub fn joinPath(allocator: std.mem.Allocator, dir_path: []const u8, filename: []const u8) ![]u8 {
    // Fast path: direct buffer manipulation instead of fmt.allocPrint
    const total_len = dir_path.len + 1 + filename.len; // dir + '/' + filename
    var result = try allocator.alloc(u8, total_len);

    // Copy directory path
    @memcpy(result[0..dir_path.len], dir_path);

    // Add separator
    result[dir_path.len] = '/';

    // Copy filename
    @memcpy(result[dir_path.len + 1 ..][0..filename.len], filename);

    return result;
}

/// Join multiple path components with '/' separator
pub fn joinPaths(allocator: std.mem.Allocator, paths: []const []const u8) ![]u8 {
    if (paths.len == 0) return try allocator.dupe(u8, "");
    if (paths.len == 1) return try allocator.dupe(u8, paths[0]);

    // Calculate total length needed
    var total_len: usize = 0;
    for (paths, 0..) |path, i| {
        total_len += path.len;
        if (i < paths.len - 1) {
            total_len += 1; // for '/'
        }
    }

    var result = try allocator.alloc(u8, total_len);
    var pos: usize = 0;

    for (paths, 0..) |path, i| {
        @memcpy(result[pos..][0..path.len], path);
        pos += path.len;

        if (i < paths.len - 1) {
            result[pos] = '/';
            pos += 1;
        }
    }

    return result;
}

/// Get the basename (last component) of a path
pub fn basename(path: []const u8) []const u8 {
    if (path.len == 0) return "";

    // Find the last separator
    if (std.mem.lastIndexOf(u8, path, "/")) |idx| {
        if (idx == path.len - 1) {
            // Path ends with '/', find previous separator
            if (std.mem.lastIndexOf(u8, path[0..idx], "/")) |prev_idx| {
                return path[prev_idx + 1 .. idx];
            }
            return path[0..idx];
        }
        return path[idx + 1 ..];
    }
    return path;
}

/// Get the directory part of a path (everything before the last separator)
pub fn dirname(path: []const u8) []const u8 {
    if (path.len == 0) return ".";

    // Find the last separator
    if (std.mem.lastIndexOf(u8, path, "/")) |idx| {
        if (idx == 0) return "/";
        return path[0..idx];
    }
    return ".";
}

/// Get the extension of a path (everything after the last dot)
pub fn extension(path: []const u8) []const u8 {
    const base = basename(path);
    if (std.mem.lastIndexOf(u8, base, ".")) |idx| {
        if (idx == 0 or (idx == base.len - 1)) {
            // Hidden file starting with . or file ending with .
            return "";
        }
        return base[idx..];
    }
    return "";
}

/// Normalize a path by removing redundant separators and . components
pub fn normalizePath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (path.len == 0) return try allocator.dupe(u8, ".");

    var parts = std.ArrayList([]const u8).init(allocator);
    defer parts.deinit();

    var iter = std.mem.tokenizeScalar(u8, path, '/');
    while (iter.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".")) {
            continue;
        }
        try parts.append(part);
    }

    if (parts.items.len == 0) {
        return try allocator.dupe(u8, if (path[0] == '/') "/" else ".");
    }

    const result = try joinPaths(allocator, parts.items);

    // Preserve leading slash for absolute paths
    if (path[0] == '/') {
        const abs_result = try std.fmt.allocPrint(allocator, "/{s}", .{result});
        allocator.free(result);
        return abs_result;
    }

    return result;
}

/// Add ./ prefix to relative paths that don't already have it
/// Absolute paths and already-prefixed paths are returned unchanged
pub fn addRelativePrefix(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    // Empty path becomes ./
    if (path.len == 0) {
        return try allocator.dupe(u8, "./");
    }

    // Single dot remains as-is
    if (std.mem.eql(u8, path, ".")) {
        return try allocator.dupe(u8, ".");
    }

    // Absolute paths (starting with /) remain unchanged
    if (path[0] == '/') {
        return try allocator.dupe(u8, path);
    }

    // Already prefixed with ./
    if (path.len >= 2 and path[0] == '.' and path[1] == '/') {
        return try allocator.dupe(u8, path);
    }

    // Parent directory references remain unchanged
    if (path.len >= 3 and path[0] == '.' and path[1] == '.' and path[2] == '/') {
        return try allocator.dupe(u8, path);
    }

    // Add ./ prefix
    return try std.fmt.allocPrint(allocator, "./{s}", .{path});
}

test "addRelativePrefix basic cases" {
    const allocator = std.testing.allocator;

    // Basic relative path
    const result1 = try addRelativePrefix(allocator, "src/file.zig");
    defer allocator.free(result1);
    try std.testing.expectEqualStrings("./src/file.zig", result1);

    // Already prefixed
    const result2 = try addRelativePrefix(allocator, "./src/file.zig");
    defer allocator.free(result2);
    try std.testing.expectEqualStrings("./src/file.zig", result2);

    // Absolute path (unchanged)
    const result3 = try addRelativePrefix(allocator, "/etc/passwd");
    defer allocator.free(result3);
    try std.testing.expectEqualStrings("/etc/passwd", result3);

    // Empty path
    const result4 = try addRelativePrefix(allocator, "");
    defer allocator.free(result4);
    try std.testing.expectEqualStrings("./", result4);

    // Single dot
    const result5 = try addRelativePrefix(allocator, ".");
    defer allocator.free(result5);
    try std.testing.expectEqualStrings(".", result5);

    // Path starting with ../
    const result6 = try addRelativePrefix(allocator, "../parent/file.zig");
    defer allocator.free(result6);
    try std.testing.expectEqualStrings("../parent/file.zig", result6);
}
