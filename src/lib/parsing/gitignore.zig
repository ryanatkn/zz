const std = @import("std");

/// Simple gitignore pattern matching
pub fn shouldIgnoreWithPatterns(path: []const u8, patterns: []const []const u8) bool {
    for (patterns) |pattern| {
        if (matchPattern(path, pattern)) return true;
    }
    return false;
}

/// Match a single gitignore pattern
fn matchPattern(path: []const u8, pattern: []const u8) bool {
    // Handle directory patterns ending with /
    if (std.mem.endsWith(u8, pattern, "/")) {
        const dir_pattern = pattern[0 .. pattern.len - 1];
        return std.mem.indexOf(u8, path, dir_pattern) != null;
    }

    // Handle patterns starting with /
    if (std.mem.startsWith(u8, pattern, "/")) {
        return std.mem.startsWith(u8, path, pattern[1..]);
    }

    // Handle wildcards
    if (std.mem.indexOf(u8, pattern, "*")) |_| {
        return matchWildcard(path, pattern);
    }

    // Simple substring match
    return std.mem.indexOf(u8, path, pattern) != null;
}

/// Simple wildcard matching
fn matchWildcard(path: []const u8, pattern: []const u8) bool {
    var parts = std.mem.splitSequence(u8, pattern, "*");
    var remaining = path;

    while (parts.next()) |part| {
        if (part.len == 0) continue;

        if (std.mem.indexOf(u8, remaining, part)) |pos| {
            remaining = remaining[pos + part.len ..];
        } else {
            return false;
        }
    }

    return true;
}

/// Git ignore patterns structure
pub const GitignorePatterns = struct {
    patterns: [][]const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, patterns: [][]const u8) GitignorePatterns {
        return .{ .patterns = patterns, .allocator = allocator };
    }

    pub fn deinit(self: *GitignorePatterns) void {
        for (self.patterns) |pattern| {
            self.allocator.free(pattern);
        }
        self.allocator.free(self.patterns);
    }

    pub fn shouldIgnore(self: GitignorePatterns, path: []const u8) bool {
        return shouldIgnoreWithPatterns(path, self.patterns);
    }

    pub fn loadFromDirHandle(allocator: std.mem.Allocator, dir: anytype, filename: []const u8) !GitignorePatterns {
        // Try to read the file, return empty patterns if not found
        const content = blk: {
            // Handle both std.fs.Dir and our DirHandle interface
            if (@hasDecl(@TypeOf(dir), "readFileAlloc")) {
                break :blk dir.readFileAlloc(allocator, filename, 1024 * 1024) catch |err| switch (err) {
                    error.FileNotFound => return GitignorePatterns.init(allocator, &[_][]const u8{}),
                    else => return err,
                };
            } else {
                // Fallback for other dir types
                return GitignorePatterns.init(allocator, &[_][]const u8{});
            }
        };
        defer allocator.free(content);

        const patterns = try parseGitignore(allocator, content);
        return GitignorePatterns.init(allocator, patterns);
    }
};

/// Parse gitignore file content into patterns
pub fn parseGitignore(allocator: std.mem.Allocator, content: []const u8) ![][]const u8 {
    var patterns = std.ArrayList([]const u8).init(allocator);
    defer patterns.deinit();

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");

        // Skip empty lines and comments
        if (trimmed.len == 0 or std.mem.startsWith(u8, trimmed, "#")) continue;

        try patterns.append(try allocator.dupe(u8, trimmed));
    }

    return patterns.toOwnedSlice();
}

test "gitignore pattern matching" {
    const testing = std.testing;

    const patterns = [_][]const u8{ "*.log", "node_modules/", ".git" };

    try testing.expect(shouldIgnoreWithPatterns("test.log", &patterns));
    try testing.expect(shouldIgnoreWithPatterns("node_modules/package.json", &patterns));
    try testing.expect(shouldIgnoreWithPatterns(".git/config", &patterns));
    try testing.expect(!shouldIgnoreWithPatterns("src/main.zig", &patterns));
}
