const std = @import("std");

/// Simple pattern matcher for file paths and content
pub const PatternMatcher = struct {
    allocator: std.mem.Allocator,
    patterns: [][]const u8,

    pub fn init(allocator: std.mem.Allocator, patterns: []const []const u8) !PatternMatcher {
        var owned_patterns = try allocator.alloc([]const u8, patterns.len);
        for (patterns, 0..) |pattern, i| {
            owned_patterns[i] = try allocator.dupe(u8, pattern);
        }

        return PatternMatcher{
            .allocator = allocator,
            .patterns = owned_patterns,
        };
    }

    pub fn deinit(self: *PatternMatcher) void {
        for (self.patterns) |pattern| {
            self.allocator.free(pattern);
        }
        self.allocator.free(self.patterns);
    }

    /// Check if path matches any pattern
    pub fn matches(self: *const PatternMatcher, path: []const u8) bool {
        for (self.patterns) |pattern| {
            if (matchPattern(path, pattern)) return true;
        }
        return false;
    }

    /// Add a new pattern
    pub fn addPattern(self: *PatternMatcher, pattern: []const u8) !void {
        const new_patterns = try self.allocator.realloc(self.patterns, self.patterns.len + 1);
        new_patterns[new_patterns.len - 1] = try self.allocator.dupe(u8, pattern);
        self.patterns = new_patterns;
    }

    /// Check if pattern contains glob characters
    pub fn hasGlobChars(pattern: []const u8) bool {
        return std.mem.indexOf(u8, pattern, "*") != null or
            std.mem.indexOf(u8, pattern, "?") != null or
            std.mem.indexOf(u8, pattern, "[") != null;
    }

    /// Check if path matches pattern (static version)
    pub fn matchesPattern(path: []const u8, pattern: []const u8) bool {
        return matchPattern(path, pattern);
    }

    /// Simple pattern matching for filenames
    pub fn matchSimplePattern(filename: []const u8, pattern: []const u8) bool {
        return matchWildcard(filename, pattern);
    }
};

/// Match a single pattern against a path
fn matchPattern(path: []const u8, pattern: []const u8) bool {
    // Handle exact matches
    if (std.mem.eql(u8, path, pattern)) return true;

    // Handle wildcard patterns
    if (std.mem.indexOf(u8, pattern, "*")) |_| {
        return matchWildcard(path, pattern);
    }

    // Handle path component matches (not substring)
    // Check if pattern appears as a complete path component
    if (std.mem.indexOf(u8, path, pattern)) |pos| {
        // Check if it's at the start or preceded by a path separator
        const at_start = pos == 0;
        const after_sep = pos > 0 and path[pos - 1] == '/';
        if (!at_start and !after_sep) return false;

        // Check if it's at the end or followed by a path separator
        const end_pos = pos + pattern.len;
        const at_end = end_pos == path.len;
        const before_sep = end_pos < path.len and path[end_pos] == '/';

        return at_end or before_sep;
    }

    return false;
}

/// Simple wildcard matching
fn matchWildcard(path: []const u8, pattern: []const u8) bool {
    var parts = std.mem.splitScalar(u8, pattern, '*');
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

test "pattern matching" {
    const testing = std.testing;

    const patterns = [_][]const u8{ "*.zig", "test_*", "src/" };
    var matcher = try PatternMatcher.init(testing.allocator, &patterns);
    defer matcher.deinit();

    try testing.expect(matcher.matches("main.zig"));
    try testing.expect(matcher.matches("test_parser.zig"));
    try testing.expect(matcher.matches("src/main.zig"));
    try testing.expect(!matcher.matches("README.md"));
}
