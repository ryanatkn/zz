const std = @import("std");
const glob = @import("../patterns/glob.zig");

/// Path pattern matching for dependency file filtering
/// Uses glob.zig for robust pattern matching while maintaining dependency-specific logic
///
/// This module handles include/exclude pattern logic specific to dependency management:
/// - Include patterns: If specified, ONLY copy matching files (whitelist)
/// - Exclude patterns: Never copy matching files (blacklist)
/// - Include takes precedence, then exclude is applied
/// - Always excludes .git directories automatically
///
/// Delegates actual pattern matching to glob.zig for consistency with the rest of the codebase.
pub const PathMatcher = struct {
    /// Check if a path matches a glob pattern
    /// Supports all glob.zig patterns:
    /// - *.ext (file extension matching)
    /// - dir/ (directory matching with trailing slash)
    /// - path/*.ext (path with wildcards)
    /// - **/dir/ (recursive directory patterns)
    /// - ?, [abc], [a-z], [!0-9] (character classes via glob.zig)
    pub fn matchesPattern(path: []const u8, pattern: []const u8) bool {
        // Handle exact matches first
        if (std.mem.eql(u8, path, pattern)) return true;

        // Handle directory patterns (trailing slash)
        if (std.mem.endsWith(u8, pattern, "/")) {
            const dir_pattern = pattern[0 .. pattern.len - 1];

            // Check if path starts with the directory pattern
            if (std.mem.startsWith(u8, path, dir_pattern)) {
                // Ensure it's actually a directory boundary
                if (path.len == dir_pattern.len) return true; // Exact directory match
                if (path.len > dir_pattern.len and path[dir_pattern.len] == '/') return true;
            }

            // Handle recursive directory patterns (**/dir/)
            if (std.mem.startsWith(u8, pattern, "**/")) {
                const recursive_pattern = pattern[3..]; // Skip "*/"
                if (std.mem.indexOf(u8, path, recursive_pattern)) |_| return true;
            }

            return false;
        }

        // Handle wildcard patterns using glob module
        return glob.matchSimplePattern(path, pattern);
    }

    /// Check if path should be included based on include patterns
    /// If include_patterns is empty, include everything
    /// If include_patterns is non-empty, only include matching paths
    pub fn shouldInclude(path: []const u8, include_patterns: []const []const u8) bool {
        // Empty include list means include everything
        if (include_patterns.len == 0) return true;

        // Check if path matches any include pattern
        for (include_patterns) |pattern| {
            if (matchesPattern(path, pattern)) return true;
        }

        return false;
    }

    /// Check if path should be excluded based on exclude patterns
    pub fn shouldExclude(path: []const u8, exclude_patterns: []const []const u8) bool {
        // Always exclude .git directory
        if (std.mem.startsWith(u8, path, ".git")) return true;
        if (std.mem.indexOf(u8, path, "/.git")) |_| return true;

        // Check exclude patterns
        for (exclude_patterns) |pattern| {
            if (matchesPattern(path, pattern)) return true;
        }

        return false;
    }

    /// Determine if a path should be copied based on include and exclude patterns
    /// Logic: Include wins if specified, then exclude is applied
    pub fn shouldCopyPath(path: []const u8, include_patterns: []const []const u8, exclude_patterns: []const []const u8) bool {
        // First check include patterns
        if (!shouldInclude(path, include_patterns)) return false;

        // Then check exclude patterns (exclude wins)
        if (shouldExclude(path, exclude_patterns)) return false;

        return true;
    }
};

// Tests
test "PathMatcher - exact matches" {
    const testing = std.testing;

    try testing.expect(PathMatcher.matchesPattern("file.txt", "file.txt"));
    try testing.expect(!PathMatcher.matchesPattern("file.txt", "other.txt"));
}

test "PathMatcher - wildcard patterns" {
    const testing = std.testing;

    // File extension patterns
    try testing.expect(PathMatcher.matchesPattern("file.txt", "*.txt"));
    try testing.expect(PathMatcher.matchesPattern("long_filename.zig", "*.zig"));
    try testing.expect(!PathMatcher.matchesPattern("file.txt", "*.zig"));

    // Prefix patterns
    try testing.expect(PathMatcher.matchesPattern("build.zig", "build*"));
    try testing.expect(PathMatcher.matchesPattern("build.zig.zon", "build*"));
    try testing.expect(!PathMatcher.matchesPattern("src.zig", "build*"));

    // Path with wildcards
    try testing.expect(PathMatcher.matchesPattern("src/main.zig", "src/*.zig"));
    try testing.expect(!PathMatcher.matchesPattern("test/main.zig", "src/*.zig"));
}

test "PathMatcher - directory patterns" {
    const testing = std.testing;

    // Directory with trailing slash
    try testing.expect(PathMatcher.matchesPattern("test", "test/"));
    try testing.expect(PathMatcher.matchesPattern("test/file.zig", "test/"));
    try testing.expect(PathMatcher.matchesPattern("test/subdir/file.zig", "test/"));
    try testing.expect(!PathMatcher.matchesPattern("testing/file.zig", "test/"));

    // Recursive directory patterns
    try testing.expect(PathMatcher.matchesPattern("any/path/test/file.zig", "**/test/"));
    try testing.expect(PathMatcher.matchesPattern("deep/nested/path/docs/readme.md", "**/docs/"));
}

test "PathMatcher - shouldInclude logic" {
    const testing = std.testing;

    // Empty include list includes everything
    try testing.expect(PathMatcher.shouldInclude("any/file.txt", &.{}));

    // Non-empty include list filters
    const include_patterns = &.{ "src/", "*.zig" };
    try testing.expect(PathMatcher.shouldInclude("src/main.zig", include_patterns));
    try testing.expect(PathMatcher.shouldInclude("test.zig", include_patterns));
    try testing.expect(!PathMatcher.shouldInclude("docs/readme.md", include_patterns));
}

test "PathMatcher - shouldExclude logic" {
    const testing = std.testing;

    // Always excludes .git
    try testing.expect(PathMatcher.shouldExclude(".git", &.{}));
    try testing.expect(PathMatcher.shouldExclude(".git/config", &.{}));
    try testing.expect(PathMatcher.shouldExclude("subdir/.git/config", &.{}));

    // Custom exclude patterns
    const exclude_patterns = &.{ "*.md", "test/" };
    try testing.expect(PathMatcher.shouldExclude("README.md", exclude_patterns));
    try testing.expect(PathMatcher.shouldExclude("test/file.zig", exclude_patterns));
    try testing.expect(!PathMatcher.shouldExclude("src/main.zig", exclude_patterns));
}

test "PathMatcher - shouldCopyPath integration" {
    const testing = std.testing;

    const include_patterns = &.{ "src/", "*.zig" };
    const exclude_patterns = &.{ "*.test.zig", "test/" };

    // Should copy: matches include, not excluded
    try testing.expect(PathMatcher.shouldCopyPath("src/main.zig", include_patterns, exclude_patterns));
    try testing.expect(PathMatcher.shouldCopyPath("utils.zig", include_patterns, exclude_patterns));

    // Should not copy: doesn't match include
    try testing.expect(!PathMatcher.shouldCopyPath("docs/readme.md", include_patterns, exclude_patterns));

    // Should not copy: matches include but excluded
    try testing.expect(!PathMatcher.shouldCopyPath("src/main.test.zig", include_patterns, exclude_patterns));
    try testing.expect(!PathMatcher.shouldCopyPath("test/helper.zig", include_patterns, exclude_patterns));

    // Should not copy: .git always excluded
    try testing.expect(!PathMatcher.shouldCopyPath(".git/config", include_patterns, exclude_patterns));
}
