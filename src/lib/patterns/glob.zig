const std = @import("std");

/// High-performance glob pattern matching implementation
/// Supports wildcards: *, ?, and character classes [abc], [0-9], [!abc]
/// Moved from legacy lib/parsing/glob.zig with performance optimizations
pub fn matchSimplePattern(filename: []const u8, pattern: []const u8) bool {
    if (pattern.len == 0) return filename.len == 0;
    if (filename.len == 0) return pattern.len == 0 or std.mem.eql(u8, pattern, "*");

    // Handle exact match (fast path)
    if (std.mem.eql(u8, filename, pattern)) return true;

    // Handle character class patterns
    if (std.mem.indexOf(u8, pattern, "[")) |_| {
        return matchWithCharacterClasses(filename, pattern);
    }

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

/// Match patterns with character classes like [0-9], [abc], [!def]
fn matchWithCharacterClasses(filename: []const u8, pattern: []const u8) bool {
    var f_idx: usize = 0;
    var p_idx: usize = 0;
    
    while (f_idx < filename.len and p_idx < pattern.len) {
        if (pattern[p_idx] == '[') {
            // Find the end of the character class
            var class_end = p_idx + 1;
            while (class_end < pattern.len and pattern[class_end] != ']') {
                class_end += 1;
            }
            if (class_end >= pattern.len) return false; // Malformed pattern
            
            // Check if this character matches the class
            const char_class = pattern[p_idx + 1 .. class_end];
            if (!matchCharacterClass(filename[f_idx], char_class)) {
                return false;
            }
            f_idx += 1;
            p_idx = class_end + 1; // Skip past the ]
        } else if (pattern[p_idx] == '*') {
            return matchWildcard(filename[f_idx..], pattern[p_idx..]);
        } else if (pattern[p_idx] == '?') {
            f_idx += 1;
            p_idx += 1;
        } else {
            // Literal character match
            if (filename[f_idx] != pattern[p_idx]) return false;
            f_idx += 1;
            p_idx += 1;
        }
    }
    
    // Check if both strings are fully consumed
    return f_idx == filename.len and p_idx == pattern.len;
}

/// Check if a character matches a character class like "0-9", "abc", "!def"
fn matchCharacterClass(char: u8, class_spec: []const u8) bool {
    if (class_spec.len == 0) return false;
    
    // Handle negation
    const negated = class_spec[0] == '!';
    const spec = if (negated) class_spec[1..] else class_spec;
    
    var matched = false;
    var i: usize = 0;
    while (i < spec.len) {
        if (i + 2 < spec.len and spec[i + 1] == '-') {
            // Range like "0-9" or "a-z"
            const start = spec[i];
            const end = spec[i + 2];
            if (char >= start and char <= end) {
                matched = true;
                break;
            }
            i += 3;
        } else {
            // Single character
            if (char == spec[i]) {
                matched = true;
                break;
            }
            i += 1;
        }
    }
    
    return if (negated) !matched else matched;
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
