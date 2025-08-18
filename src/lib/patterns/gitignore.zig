const std = @import("std");
const primitives = @import("primitives.zig");

/// High-performance gitignore pattern matching
/// Uses shared primitives for consistency across pattern matchers
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
    if (primitives.hasWildcard(pattern)) {
        return primitives.matchWildcardParts(path, pattern);
    }

    // Simple substring match
    return std.mem.indexOf(u8, path, pattern) != null;
}


/// Git ignore patterns structure with efficient memory management
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

    /// Load from directory handle with efficient file reading
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

    /// Create from ZON configuration
    pub fn fromZon(allocator: std.mem.Allocator, zon_patterns: []const []const u8) !GitignorePatterns {
        var patterns = try allocator.alloc([]const u8, zon_patterns.len);
        for (zon_patterns, 0..) |pattern, i| {
            patterns[i] = try allocator.dupe(u8, pattern);
        }
        return GitignorePatterns.init(allocator, patterns);
    }

    /// Convert to ZON representation for serialization
    pub fn toZon(self: GitignorePatterns, allocator: std.mem.Allocator) ![]const u8 {
        var zon = std.ArrayList(u8).init(allocator);
        defer zon.deinit();

        try zon.appendSlice(".{\n");
        for (self.patterns, 0..) |pattern, i| {
            try zon.writer().print("    \"{s}\"", .{pattern});
            if (i < self.patterns.len - 1) try zon.appendSlice(",");
            try zon.appendSlice("\n");
        }
        try zon.appendSlice("}");

        return zon.toOwnedSlice();
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
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        try patterns.append(try allocator.dupe(u8, trimmed));
    }

    return patterns.toOwnedSlice();
}

/// Common gitignore patterns for different project types
pub const CommonPatterns = struct {
    pub const zig_project = [_][]const u8{
        "zig-out/",
        "zig-cache/",
        "*.tmp",
        ".zigmod/",
    };

    pub const node_project = [_][]const u8{
        "node_modules/",
        "dist/",
        "build/",
        "*.log",
        ".env",
    };

    pub const general = [_][]const u8{
        ".DS_Store",
        "Thumbs.db",
        "*.swp",
        "*.swo",
        "*~",
        ".vscode/",
        ".idea/",
    };
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "basic gitignore pattern matching" {
    try testing.expect(matchPattern("node_modules/package", "node_modules/"));
    try testing.expect(matchPattern("src/main.zig", "*.zig"));
    try testing.expect(!matchPattern("src/main.zig", "*.js"));
}

test "gitignore patterns structure" {
    var patterns = try GitignorePatterns.fromZon(testing.allocator, &.{ "*.tmp", "build/" });
    defer patterns.deinit();

    try testing.expect(patterns.shouldIgnore("test.tmp"));
    try testing.expect(patterns.shouldIgnore("build/output"));
    try testing.expect(!patterns.shouldIgnore("src/main.zig"));
}

test "gitignore file parsing" {
    const content =
        \\# Comment
        \\*.tmp
        \\node_modules/
        \\
        \\build/
    ;

    const patterns = try parseGitignore(testing.allocator, content);
    defer {
        for (patterns) |pattern| {
            testing.allocator.free(pattern);
        }
        testing.allocator.free(patterns);
    }

    try testing.expectEqual(@as(usize, 3), patterns.len);
    try testing.expectEqualStrings("*.tmp", patterns[0]);
    try testing.expectEqualStrings("node_modules/", patterns[1]);
    try testing.expectEqualStrings("build/", patterns[2]);
}

test "ZON serialization" {
    var patterns = try GitignorePatterns.fromZon(testing.allocator, &.{ "*.tmp", "build/" });
    defer patterns.deinit();

    const zon = try patterns.toZon(testing.allocator);
    defer testing.allocator.free(zon);

    try testing.expect(std.mem.indexOf(u8, zon, "*.tmp") != null);
    try testing.expect(std.mem.indexOf(u8, zon, "build/") != null);
}
