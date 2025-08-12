const std = @import("std");

pub const PatternMatcher = struct {
    /// Unified pattern matching with optimized fast/slow path decision
    /// PERFORMANCE CRITICAL: Preserves 90/10 fast/slow path split from original
    /// Consolidates: matchesSimpleComponent, matchesSimpleComponentInline,
    ///               matchesPathComponent, matchesPathSegment
    pub fn matchesPattern(path: []const u8, pattern: []const u8) bool {
        // Fast path: Simple patterns without slashes (90% of use cases)
        // PERFORMANCE: This handles the majority of patterns efficiently
        if (std.mem.indexOf(u8, pattern, "/") == null) {
            return matchesSimpleComponentOptimized(path, pattern);
        }

        // Slow path: Complex path segment patterns (10% of use cases)
        return matchesPathSegment(path, pattern);
    }

    /// Check if pattern contains glob characters
    pub fn hasGlobChars(pattern: []const u8) bool {
        return std.mem.indexOf(u8, pattern, "*") != null or
            std.mem.indexOf(u8, pattern, "?") != null;
    }

    /// Simple glob pattern matching (basic implementation)
    pub fn matchSimplePattern(text: []const u8, pattern: []const u8) bool {
        // This is a simplified version - for full implementation,
        // should delegate to the glob module's matching logic
        if (std.mem.indexOf(u8, pattern, "*") == null and std.mem.indexOf(u8, pattern, "?") == null) {
            return std.mem.eql(u8, text, pattern);
        }

        // Basic wildcard matching
        if (std.mem.eql(u8, pattern, "*")) return true;

        if (std.mem.startsWith(u8, pattern, "*.")) {
            const ext = pattern[2..];
            return std.mem.endsWith(u8, text, ext);
        }

        // For more complex patterns, this should use proper glob matching
        return false;
    }

    /// Fast path: Optimized matching for simple component patterns (no slashes)
    /// PERFORMANCE CRITICAL: Preserves all original optimizations from hot path
    /// - Quick basename check first (most common case)
    /// - Early exit for single-component paths
    /// - Inline for maximum performance in hot loop
    inline fn matchesSimpleComponentOptimized(path: []const u8, pattern: []const u8) bool {
        // PERFORMANCE: Quick basename check first (most common case)
        const basename = std.fs.path.basename(path);
        if (std.mem.eql(u8, basename, pattern)) {
            return true;
        }

        // PERFORMANCE: Early exit optimization for single-component paths
        // Only do expensive component iteration if basename doesn't match
        // and the path contains separators
        if (std.mem.indexOf(u8, path, "/") == null) {
            return false; // Single component path already checked via basename
        }

        // Check each path component for exact match
        var parts = std.mem.splitScalar(u8, path, '/');
        while (parts.next()) |part| {
            if (std.mem.eql(u8, part, pattern)) {
                return true;
            }
        }

        return false;
    }

    /// Slow path: Complex matching for path segment patterns (with slashes)
    fn matchesPathSegment(path: []const u8, pattern: []const u8) bool {
        // Check if path ends with the pattern
        if (std.mem.endsWith(u8, path, pattern)) {
            // Ensure it's a proper path boundary (not a substring)
            if (path.len == pattern.len or path[path.len - pattern.len - 1] == '/') {
                return true;
            }
        }
        return false;
    }
};
