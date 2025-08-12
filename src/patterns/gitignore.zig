const std = @import("std");

pub const GitignorePatterns = struct {
    /// Parse gitignore file content into patterns (stateless)
    pub fn parseContent(allocator: std.mem.Allocator, content: []const u8) ![][]const u8 {
        var patterns = std.ArrayList([]const u8).init(allocator);
        defer patterns.deinit();

        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");

            // Skip empty lines and comments
            if (trimmed.len == 0 or trimmed[0] == '#') {
                continue;
            }

            // Store the pattern (we'll handle negation and path logic in matching)
            const pattern = try allocator.dupe(u8, trimmed);
            try patterns.append(pattern);
        }

        return try patterns.toOwnedSlice();
    }

    /// Check if a path should be ignored based on gitignore patterns (stateless)
    pub fn shouldIgnore(patterns: []const []const u8, path: []const u8) bool {
        var should_ignore = false;

        for (patterns) |pattern| {
            // Handle negation patterns (!)
            if (pattern.len > 0 and pattern[0] == '!') {
                const negated_pattern = pattern[1..];
                if (matchesPattern(path, negated_pattern)) {
                    should_ignore = false; // Negation overrides
                }
            } else {
                if (matchesPattern(path, pattern)) {
                    should_ignore = true;
                }
            }
        }

        return should_ignore;
    }

    /// Unified gitignore pattern matching
    /// Consolidates: matchesGitignorePattern + matchesSimpleGitignorePattern
    pub fn matchesPattern(path: []const u8, pattern: []const u8) bool {
        // Directory-only patterns end with /
        if (std.mem.endsWith(u8, pattern, "/")) {
            // For now, treat as regular pattern without the /
            const dir_pattern = pattern[0 .. pattern.len - 1];
            return matchesSimpleGitignorePattern(path, dir_pattern);
        }

        // Absolute patterns start with /
        if (std.mem.startsWith(u8, pattern, "/")) {
            const abs_pattern = pattern[1..];
            return std.mem.startsWith(u8, path, abs_pattern);
        }

        // Relative patterns match anywhere in the path
        return matchesSimpleGitignorePattern(path, pattern);
    }

    /// Simple pattern matching for gitignore (basic wildcards)
    fn matchesSimpleGitignorePattern(path: []const u8, pattern: []const u8) bool {
        // Handle simple wildcards
        if (std.mem.indexOf(u8, pattern, "*") != null) {
            // Very basic wildcard support - full implementation would need proper glob matching
            if (std.mem.eql(u8, pattern, "*")) return true;

            if (std.mem.startsWith(u8, pattern, "*.")) {
                const ext = pattern[2..];
                return std.mem.endsWith(u8, path, ext);
            }
        }

        // Exact match or path component match
        const basename = std.fs.path.basename(path);
        if (std.mem.eql(u8, basename, pattern)) {
            return true;
        }

        // Check if any path component matches
        var parts = std.mem.splitScalar(u8, path, '/');
        while (parts.next()) |part| {
            if (std.mem.eql(u8, part, pattern)) {
                return true;
            }
        }

        return false;
    }

    /// Load gitignore patterns from file (stateless)
    pub fn loadFromFile(allocator: std.mem.Allocator, file_path: []const u8) ![][]const u8 {
        return loadFromDir(allocator, std.fs.cwd(), file_path);
    }

    /// Load gitignore patterns from a directory (stateless)
    pub fn loadFromDir(allocator: std.mem.Allocator, dir: std.fs.Dir, file_path: []const u8) ![][]const u8 {
        // Simple approach: just try to read .gitignore from the specified directory
        // For now, don't walk up the directory tree to keep implementation simple
        if (dir.readFileAlloc(allocator, file_path, 1024 * 1024)) |content| {
            defer allocator.free(content);
            return try parseContent(allocator, content);
        } else |_| {
            // File doesn't exist or can't be read, return empty patterns
            return try allocator.alloc([]const u8, 0);
        }
    }
};

// Tests for gitignore functionality
test "GitignorePatterns.parseContent basic parsing" {
    const allocator = std.testing.allocator;

    const content =
        \\# This is a comment
        \\node_modules
        \\*.log
        \\
        \\temp/
        \\!important.log
    ;

    const patterns = try GitignorePatterns.parseContent(allocator, content);
    defer {
        for (patterns) |pattern| {
            allocator.free(pattern);
        }
        allocator.free(patterns);
    }

    try std.testing.expect(patterns.len == 4);
    try std.testing.expectEqualStrings("node_modules", patterns[0]);
    try std.testing.expectEqualStrings("*.log", patterns[1]);
    try std.testing.expectEqualStrings("temp/", patterns[2]);
    try std.testing.expectEqualStrings("!important.log", patterns[3]);
}

test "GitignorePatterns.shouldIgnore pattern logic" {
    const patterns = [_][]const u8{ "node_modules", "*.log", "!important.log" };

    try std.testing.expect(GitignorePatterns.shouldIgnore(&patterns, "node_modules"));
    try std.testing.expect(GitignorePatterns.shouldIgnore(&patterns, "path/to/node_modules"));
    try std.testing.expect(GitignorePatterns.shouldIgnore(&patterns, "test.log"));
    try std.testing.expect(!GitignorePatterns.shouldIgnore(&patterns, "important.log")); // Negated
    try std.testing.expect(!GitignorePatterns.shouldIgnore(&patterns, "test.txt"));
}

test "GitignorePatterns.matchesPattern unified matching" {
    // Directory patterns
    try std.testing.expect(GitignorePatterns.matchesPattern("temp", "temp/"));

    // Absolute patterns
    try std.testing.expect(GitignorePatterns.matchesPattern("build/output", "/build"));
    try std.testing.expect(!GitignorePatterns.matchesPattern("src/build", "/build"));

    // Relative patterns
    try std.testing.expect(GitignorePatterns.matchesPattern("any/path/node_modules", "node_modules"));
    try std.testing.expect(GitignorePatterns.matchesPattern("test.log", "*.log"));
}
