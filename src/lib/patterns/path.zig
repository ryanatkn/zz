const std = @import("std");
const primitives = @import("primitives.zig");

/// Path-specific pattern matching for configuration ignore patterns
/// Handles both directory names (e.g., "node_modules") and full paths (e.g., "src/ignored/dir")
/// Match a path against a pattern using path-aware semantics
pub fn matchPath(path: []const u8, pattern: []const u8) bool {
    // Exact match
    if (std.mem.eql(u8, path, pattern)) {
        return true;
    }

    // If pattern contains path separator, treat as full path pattern
    if (primitives.hasPathSeparator(pattern)) {
        return matchFullPath(path, pattern);
    }

    // Otherwise treat as component pattern (matches any directory with that name)
    return matchComponent(path, pattern);
}

/// Match against full path patterns like "src/tree/compiled"
pub fn matchFullPath(path: []const u8, pattern: []const u8) bool {
    // Direct suffix match (handles /absolute/path/src/tree/compiled)
    if (std.mem.endsWith(u8, path, pattern)) {
        // Ensure it's a proper path boundary
        const match_start = path.len - pattern.len;
        if (match_start == 0 or path[match_start - 1] == '/') {
            return true;
        }
    }

    // Check if path contains pattern as a proper subpath
    return primitives.containsSubpath(path, pattern);
}

/// Match against directory name patterns like "node_modules"
pub fn matchComponent(path: []const u8, pattern: []const u8) bool {
    return primitives.hasPathComponent(path, pattern);
}

/// Check if path is or contains a dot directory
pub fn hasDotDirectory(path: []const u8) bool {
    var i: usize = 0;
    while (i < path.len) : (i += 1) {
        if (primitives.isDotDirectoryAt(path, i)) {
            return true;
        }
    }
    return false;
}

/// Check if path starts with a dot directory
pub fn startsWithDotDirectory(path: []const u8) bool {
    return primitives.isDotDirectoryAt(path, 0);
}

// Tests
test "matchPath - exact matches" {
    try std.testing.expect(matchPath("test.txt", "test.txt"));
    try std.testing.expect(!matchPath("test.txt", "other.txt"));
}

test "matchPath - component patterns" {
    try std.testing.expect(matchPath("src/node_modules/lib", "node_modules"));
    try std.testing.expect(matchPath("deep/path/node_modules", "node_modules"));
    try std.testing.expect(!matchPath("src/node/modules", "node_modules"));
}

test "matchPath - full path patterns" {
    try std.testing.expect(matchPath("project/src/ignored/file.txt", "src/ignored"));
    try std.testing.expect(matchPath("/abs/path/src/ignored/deep", "src/ignored"));
    try std.testing.expect(!matchPath("src/ignore", "src/ignored"));
}

test "matchFullPath - nested patterns" {
    // Test case from tree walker tests
    try std.testing.expect(matchFullPath("src/tree/compiled", "src/tree/compiled"));
    try std.testing.expect(matchFullPath("project/src/tree/compiled", "src/tree/compiled"));
    try std.testing.expect(matchFullPath("src/tree/compiled/deep/path", "src/tree/compiled"));
    try std.testing.expect(!matchFullPath("src/tree/compile", "src/tree/compiled"));
}

test "hasDotDirectory" {
    try std.testing.expect(hasDotDirectory(".git"));
    try std.testing.expect(hasDotDirectory("src/.cache/data"));
    try std.testing.expect(hasDotDirectory(".config/settings"));
    try std.testing.expect(!hasDotDirectory("src/lib"));
    try std.testing.expect(!hasDotDirectory("../parent"));
}
