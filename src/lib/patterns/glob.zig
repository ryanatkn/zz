const std = @import("std");

/// High-performance glob pattern matching implementation
/// Supports basic wildcards: * and ?
/// Moved from legacy lib/parsing/glob.zig with performance optimizations
pub fn matchSimplePattern(filename: []const u8, pattern: []const u8) bool {
    if (pattern.len == 0) return filename.len == 0;
    if (filename.len == 0) return pattern.len == 0 or std.mem.eql(u8, pattern, "*");

    // Handle exact match (fast path)
    if (std.mem.eql(u8, filename, pattern)) return true;

    // Handle wildcard patterns
    if (std.mem.indexOf(u8, pattern, "*")) |_| {
        return matchWildcard(filename, pattern);
    }

    if (std.mem.indexOf(u8, pattern, "?")) |_| {
        return matchQuestion(filename, pattern);
    }

    return false;
}

/// Match patterns with * wildcard
fn matchWildcard(filename: []const u8, pattern: []const u8) bool {
    // High-performance implementation: split on * and check parts
    var parts = std.mem.splitScalar(u8, pattern, '*');
    var remaining = filename;

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

/// Match patterns with ? wildcard
fn matchQuestion(filename: []const u8, pattern: []const u8) bool {
    if (filename.len != pattern.len) return false;

    for (filename, pattern) |f_char, p_char| {
        if (p_char != '?' and p_char != f_char) return false;
    }

    return true;
}

/// Match multiple patterns (any match succeeds)
pub fn matchAnyPattern(filename: []const u8, patterns: []const []const u8) bool {
    for (patterns) |pattern| {
        if (matchSimplePattern(filename, pattern)) return true;
    }
    return false;
}

/// Compiled glob pattern for repeated matching
pub const CompiledGlob = struct {
    pattern: []const u8,
    has_wildcards: bool,
    parts: ?[][]const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, pattern: []const u8) !CompiledGlob {
        const has_wildcards = std.mem.indexOf(u8, pattern, "*") != null or
            std.mem.indexOf(u8, pattern, "?") != null;

        var parts: ?[][]const u8 = null;
        if (has_wildcards and std.mem.indexOf(u8, pattern, "*") != null) {
            // Pre-split wildcard patterns for performance
            var part_list = std.ArrayList([]const u8).init(allocator);
            var split = std.mem.splitScalar(u8, pattern, '*');
            while (split.next()) |part| {
                if (part.len > 0) {
                    try part_list.append(try allocator.dupe(u8, part));
                }
            }
            parts = try part_list.toOwnedSlice();
        }

        return CompiledGlob{
            .pattern = try allocator.dupe(u8, pattern),
            .has_wildcards = has_wildcards,
            .parts = parts,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CompiledGlob) void {
        if (self.parts) |parts| {
            for (parts) |part| {
                self.allocator.free(part);
            }
            self.allocator.free(parts);
        }
        self.allocator.free(self.pattern);
    }

    pub fn match(self: CompiledGlob, filename: []const u8) bool {
        if (!self.has_wildcards) {
            return std.mem.eql(u8, filename, self.pattern);
        }
        return matchSimplePattern(filename, self.pattern);
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "exact match" {
    try testing.expect(matchSimplePattern("test.zig", "test.zig"));
    try testing.expect(!matchSimplePattern("test.zig", "other.zig"));
}

test "wildcard patterns" {
    try testing.expect(matchSimplePattern("test.zig", "*.zig"));
    try testing.expect(matchSimplePattern("src/main.zig", "src/*.zig"));
    try testing.expect(matchSimplePattern("anything", "*"));
    try testing.expect(!matchSimplePattern("test.js", "*.zig"));
}

test "question mark patterns" {
    try testing.expect(matchSimplePattern("test", "t??t"));
    try testing.expect(matchSimplePattern("file.c", "file.?"));
    try testing.expect(!matchSimplePattern("file.cpp", "file.?"));
}

test "multiple patterns" {
    const patterns = [_][]const u8{ "*.zig", "*.zon", "*.json" };
    try testing.expect(matchAnyPattern("test.zig", &patterns));
    try testing.expect(matchAnyPattern("config.zon", &patterns));
    try testing.expect(!matchAnyPattern("readme.md", &patterns));
}

test "compiled glob performance" {
    var glob = try CompiledGlob.init(testing.allocator, "*.zig");
    defer glob.deinit();

    try testing.expect(glob.match("test.zig"));
    try testing.expect(glob.match("main.zig"));
    try testing.expect(!glob.match("test.js"));
}
