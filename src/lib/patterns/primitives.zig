const std = @import("std");

/// Shared pattern matching primitives used by glob, gitignore, and path matchers
/// 
/// ## Layered Pattern Matching Architecture
/// 
/// This module provides the foundation for all pattern matching in zz. The architecture
/// is designed to eliminate code duplication while preserving semantic clarity:
///
/// **Layer 1: Primitives (this module)**
/// - Core pattern matching operations (wildcards, character classes, path boundaries)
/// - No domain-specific semantics - just the mechanics of matching
/// - Single source of truth for common operations
///
/// **Layer 2: Domain-Specific Matchers**
/// - `glob.zig` - Pure glob matching with *, ?, [abc] semantics
/// - `gitignore.zig` - Gitignore rules with /, !, ** semantics  
/// - `path.zig` - Path component and subpath matching semantics
///
/// **Layer 3: Smart Dispatchers**
/// - `config.zig` - Detects pattern type and delegates to appropriate matcher
/// - Other modules use specific matchers directly based on context
///
/// This design avoids semantic confusion (e.g., what does "/" mean in different contexts)
/// while still sharing the low-level matching logic for consistency and performance.

/// Check if a pattern contains wildcard characters
pub fn hasWildcard(pattern: []const u8) bool {
    return std.mem.indexOf(u8, pattern, "*") != null or
           std.mem.indexOf(u8, pattern, "?") != null or
           std.mem.indexOf(u8, pattern, "[") != null;
}

/// Check if a pattern contains path separators
pub fn hasPathSeparator(pattern: []const u8) bool {
    return std.mem.indexOf(u8, pattern, "/") != null;
}

/// Check if position in path is at a path boundary (start, end, or adjacent to /)
pub fn isPathBoundary(path: []const u8, pos: usize) bool {
    if (pos == 0) return true;
    if (pos >= path.len) return true;
    if (pos > 0 and path[pos - 1] == '/') return true;
    if (pos < path.len and path[pos] == '/') return true;
    return false;
}

/// Match a simple wildcard pattern against text
/// Handles * (zero or more chars) but not path separators
pub fn matchWildcardSimple(text: []const u8, pattern: []const u8) bool {
    var t_idx: usize = 0;
    var p_idx: usize = 0;
    var star_idx: ?usize = null;
    var star_match: usize = 0;

    while (t_idx < text.len) {
        if (p_idx < pattern.len and (pattern[p_idx] == text[t_idx] or pattern[p_idx] == '?')) {
            t_idx += 1;
            p_idx += 1;
        } else if (p_idx < pattern.len and pattern[p_idx] == '*') {
            star_idx = p_idx;
            star_match = t_idx;
            p_idx += 1;
        } else if (star_idx != null) {
            p_idx = star_idx.? + 1;
            star_match += 1;
            t_idx = star_match;
        } else {
            return false;
        }
    }

    while (p_idx < pattern.len and pattern[p_idx] == '*') {
        p_idx += 1;
    }

    return p_idx == pattern.len;
}

/// Split pattern on wildcards and check if all parts appear in sequence
/// This is optimized for patterns like "*.zig" or "test*.txt"
pub fn matchWildcardParts(text: []const u8, pattern: []const u8) bool {
    var parts = std.mem.splitScalar(u8, pattern, '*');
    var remaining = text;
    var is_first = true;
    const has_trailing_star = std.mem.endsWith(u8, pattern, "*");

    while (parts.next()) |part| {
        if (part.len == 0) continue;

        if (is_first and !std.mem.startsWith(u8, pattern, "*")) {
            // First part must match at start if no leading *
            if (!std.mem.startsWith(u8, remaining, part)) {
                return false;
            }
            remaining = remaining[part.len..];
        } else if (parts.peek() == null and !has_trailing_star) {
            // Last part must match at end if no trailing *
            if (!std.mem.endsWith(u8, remaining, part)) {
                return false;
            }
            return true;
        } else {
            // Middle parts can appear anywhere
            if (std.mem.indexOf(u8, remaining, part)) |pos| {
                remaining = remaining[pos + part.len ..];
            } else {
                return false;
            }
        }
        is_first = false;
    }

    return true;
}

/// Check if a character matches a character class specification
/// Supports ranges like "0-9", "a-z", sets like "abc", and negation with "!" or "^"
pub fn matchCharacterClass(char: u8, class_spec: []const u8) bool {
    if (class_spec.len == 0) return false;

    const negated = class_spec[0] == '!' or class_spec[0] == '^';
    const actual_spec = if (negated) class_spec[1..] else class_spec;

    // Check for ranges (e.g., "0-9", "a-z")
    if (actual_spec.len >= 3) {
        var i: usize = 0;
        while (i + 2 < actual_spec.len) : (i += 1) {
            if (actual_spec[i + 1] == '-') {
                const range_start = actual_spec[i];
                const range_end = actual_spec[i + 2];
                if (char >= range_start and char <= range_end) {
                    return !negated;
                }
                i += 2; // Skip the range
            }
        }
    }

    // Check for literal characters
    for (actual_spec) |spec_char| {
        if (spec_char != '-' and char == spec_char) {
            return !negated;
        }
    }

    return negated;
}

/// Check if path component at given position is a dot directory (e.g., .git, .cache)
pub fn isDotDirectoryAt(path: []const u8, pos: usize) bool {
    if (pos >= path.len) return false;
    if (path[pos] != '.') return false;
    
    // Must be at start or after /
    if (pos > 0 and path[pos - 1] != '/') return false;
    
    // Must have at least one more character
    if (pos + 1 >= path.len) return false;
    
    // Find end of component
    const end = std.mem.indexOfScalarPos(u8, path, pos, '/') orelse path.len;
    const component = path[pos..end];
    
    // Must be more than just "." or ".."
    return component.len > 1 and !std.mem.eql(u8, component, "..");
}

/// Find all path components (split by /)
pub const PathComponentIterator = struct {
    path: []const u8,
    index: usize = 0,

    pub fn next(self: *PathComponentIterator) ?[]const u8 {
        if (self.index >= self.path.len) return null;

        // Skip leading slashes
        while (self.index < self.path.len and self.path[self.index] == '/') {
            self.index += 1;
        }

        if (self.index >= self.path.len) return null;

        const start = self.index;
        while (self.index < self.path.len and self.path[self.index] != '/') {
            self.index += 1;
        }

        return self.path[start..self.index];
    }
};

/// Iterate over path components
pub fn iterateComponents(path: []const u8) PathComponentIterator {
    return PathComponentIterator{ .path = path };
}

/// Check if any component in path matches the given name
pub fn hasPathComponent(path: []const u8, component_name: []const u8) bool {
    var iter = iterateComponents(path);
    while (iter.next()) |component| {
        if (std.mem.eql(u8, component, component_name)) {
            return true;
        }
    }
    return false;
}

/// Check if path contains pattern as a proper subpath
pub fn containsSubpath(path: []const u8, subpath: []const u8) bool {
    if (std.mem.indexOf(u8, path, subpath)) |pos| {
        // Check boundaries
        const at_start = pos == 0;
        const after_sep = pos > 0 and path[pos - 1] == '/';
        const at_end = pos + subpath.len == path.len;
        const before_sep = pos + subpath.len < path.len and path[pos + subpath.len] == '/';
        
        return (at_start or after_sep) and (at_end or before_sep);
    }
    return false;
}

// Tests
test "hasWildcard" {
    try std.testing.expect(hasWildcard("*.zig"));
    try std.testing.expect(hasWildcard("test?.txt"));
    try std.testing.expect(hasWildcard("[abc].txt"));
    try std.testing.expect(!hasWildcard("normal.txt"));
}

test "isPathBoundary" {
    const path = "src/lib/test.zig";
    try std.testing.expect(isPathBoundary(path, 0)); // start
    try std.testing.expect(isPathBoundary(path, 3)); // before /
    try std.testing.expect(isPathBoundary(path, 4)); // after /
    try std.testing.expect(!isPathBoundary(path, 5)); // middle of "lib"
    try std.testing.expect(isPathBoundary(path, path.len)); // end
}

test "matchWildcardSimple" {
    try std.testing.expect(matchWildcardSimple("test.zig", "*.zig"));
    try std.testing.expect(matchWildcardSimple("test.zig", "test.*"));
    try std.testing.expect(matchWildcardSimple("test.zig", "t?st.zig"));
    try std.testing.expect(!matchWildcardSimple("test.zig", "*.txt"));
}

test "matchCharacterClass" {
    try std.testing.expect(matchCharacterClass('5', "0-9"));
    try std.testing.expect(matchCharacterClass('b', "abc"));
    try std.testing.expect(!matchCharacterClass('d', "abc"));
    try std.testing.expect(matchCharacterClass('d', "!abc"));
    try std.testing.expect(!matchCharacterClass('a', "!abc"));
    // Test ^ negation as well
    try std.testing.expect(matchCharacterClass('d', "^abc"));
    try std.testing.expect(!matchCharacterClass('a', "^abc"));
}

test "hasPathComponent" {
    const path = "src/node_modules/lib/test.js";
    try std.testing.expect(hasPathComponent(path, "node_modules"));
    try std.testing.expect(hasPathComponent(path, "lib"));
    try std.testing.expect(!hasPathComponent(path, "modules")); // partial match
}

test "containsSubpath" {
    const path = "project/src/ignored/deep/file.txt";
    try std.testing.expect(containsSubpath(path, "src/ignored"));
    try std.testing.expect(containsSubpath(path, "ignored/deep"));
    try std.testing.expect(!containsSubpath(path, "rc/ignored")); // not at boundary
}