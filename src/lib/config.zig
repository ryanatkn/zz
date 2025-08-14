const std = @import("std");
const PatternMatcher = @import("parsing/matcher.zig").PatternMatcher;
const GitignorePatterns = @import("parsing/gitignore.zig").GitignorePatterns;
const path_utils = @import("core/path.zig");

// Re-export public types for API compatibility
pub const SharedConfig = @import("../config/shared.zig").SharedConfig;
pub const SymlinkBehavior = @import("../config/shared.zig").SymlinkBehavior;
pub const BasePatterns = @import("../config/shared.zig").BasePatterns;
pub const ZonLoader = @import("../config/zon.zig").ZonLoader;
pub const ZonConfig = @import("../config/zon.zig").ZonConfig;
pub const PatternResolver = @import("../config/resolver.zig").PatternResolver;

// DRY helper functions for common config operations
pub fn shouldIgnorePath(config: SharedConfig, path: []const u8) bool {
    // Built-in behavior: automatically ignore dot-prefixed directories/files
    const basename = path_utils.basename(path);
    if (basename.len > 0 and basename[0] == '.') {
        return true;
    }

    // Check gitignore patterns first (if enabled)
    if (config.respect_gitignore and GitignorePatterns.shouldIgnore(config.gitignore_patterns, path)) {
        return true;
    }

    // Check user-configured patterns using unified pattern matcher
    for (config.ignored_patterns) |pattern| {
        if (PatternMatcher.hasGlobChars(pattern)) {
            // Extract filename for pattern matching
            const filename = path_utils.basename(path);
            if (PatternMatcher.matchSimplePattern(filename, pattern)) {
                return true;
            }
        } else {
            // Use unified pattern matcher (consolidates all duplicate functions)
            if (PatternMatcher.matchesPattern(path, pattern)) {
                return true;
            }
        }
    }
    return false;
}

pub fn shouldHideFile(config: SharedConfig, filename: []const u8) bool {
    for (config.hidden_files) |hidden| {
        if (std.mem.eql(u8, filename, hidden)) {
            return true;
        }
    }
    return false;
}

pub fn handleSymlink(config: SharedConfig, path: []const u8) SymlinkBehavior {
    _ = path; // Path could be used for conditional symlink behavior in future
    return config.symlink_behavior;
}

// Tests for config functionality
test "shouldIgnorePath edge cases" {
    const allocator = std.testing.allocator;

    // Create test config
    var resolver = PatternResolver.init(allocator);
    const ignored = try resolver.resolveIgnoredPatterns(.{ .custom = &[_][]const u8{ "node_modules", "git", "test" } }, null);
    defer {
        for (ignored) |pattern| allocator.free(pattern);
        allocator.free(ignored);
    }

    const hidden = try resolver.resolveHiddenFiles(&[_][]const u8{".DS_Store"});
    defer {
        for (hidden) |file| allocator.free(file);
        allocator.free(hidden);
    }

    const config = SharedConfig{
        .ignored_patterns = ignored,
        .hidden_files = hidden,
        .gitignore_patterns = &[_][]const u8{},
        .symlink_behavior = .skip,
        .respect_gitignore = false,
        .patterns_allocated = true,
    };

    // Test exact matches (should match)
    try std.testing.expect(shouldIgnorePath(config, "node_modules"));
    try std.testing.expect(shouldIgnorePath(config, "path/to/node_modules"));
    try std.testing.expect(shouldIgnorePath(config, "node_modules/package"));

    // Test partial matches (should NOT match - avoid leaky behavior)
    try std.testing.expect(!shouldIgnorePath(config, "my_node_modules"));
    try std.testing.expect(!shouldIgnorePath(config, "node_modules_backup"));
    try std.testing.expect(!shouldIgnorePath(config, "path/to/my_node_modules"));

    // Test component matching
    try std.testing.expect(shouldIgnorePath(config, "src/git/repo"));
    try std.testing.expect(!shouldIgnorePath(config, "src/gitignore"));
    try std.testing.expect(!shouldIgnorePath(config, "src/my_git"));

    // Test case sensitivity
    try std.testing.expect(!shouldIgnorePath(config, "NODE_MODULES"));
    try std.testing.expect(!shouldIgnorePath(config, "Git"));
}

test "shouldHideFile functionality" {
    const allocator = std.testing.allocator;

    var resolver = PatternResolver.init(allocator);
    const ignored = try resolver.resolveIgnoredPatterns(.extend, null);
    defer {
        for (ignored) |pattern| allocator.free(pattern);
        allocator.free(ignored);
    }

    const hidden = try resolver.resolveHiddenFiles(&[_][]const u8{"custom.hidden"});
    defer {
        for (hidden) |file| allocator.free(file);
        allocator.free(hidden);
    }

    const config = SharedConfig{
        .ignored_patterns = ignored,
        .hidden_files = hidden,
        .gitignore_patterns = &[_][]const u8{},
        .symlink_behavior = .skip,
        .respect_gitignore = false,
        .patterns_allocated = true,
    };

    // Test hidden file detection
    try std.testing.expect(shouldHideFile(config, ".DS_Store")); // Default
    try std.testing.expect(shouldHideFile(config, "Thumbs.db")); // Default
    try std.testing.expect(shouldHideFile(config, "custom.hidden")); // Custom

    // Test non-hidden files
    try std.testing.expect(!shouldHideFile(config, "normal.txt"));
    try std.testing.expect(!shouldHideFile(config, ".DS_Store_backup")); // Partial match
}

test "PatternResolver base patterns behavior" {
    const allocator = std.testing.allocator;

    var resolver = PatternResolver.init(allocator);

    // Test extend behavior
    const extended = try resolver.resolveIgnoredPatterns(.extend, &[_][]const u8{"custom"});
    defer {
        for (extended) |pattern| allocator.free(pattern);
        allocator.free(extended);
    }

    // Should include defaults + custom
    try std.testing.expect(extended.len > 10); // Has defaults
    var found_custom = false;
    var found_git = false;
    for (extended) |pattern| {
        if (std.mem.eql(u8, pattern, "custom")) found_custom = true;
        if (std.mem.eql(u8, pattern, ".git")) found_git = true;
    }
    try std.testing.expect(found_custom);
    try std.testing.expect(found_git);

    // Test custom behavior (no defaults)
    const custom = try resolver.resolveIgnoredPatterns(.{ .custom = &[_][]const u8{"only_this"} }, null);
    defer {
        for (custom) |pattern| allocator.free(pattern);
        allocator.free(custom);
    }

    try std.testing.expect(custom.len == 1);
    try std.testing.expect(std.mem.eql(u8, custom[0], "only_this"));
}

test "PatternMatcher unified pattern matching edge cases" {
    // Test exact component matches - all delegated to unified pattern matcher
    try std.testing.expect(PatternMatcher.matchesPattern("node_modules", "node_modules"));
    try std.testing.expect(PatternMatcher.matchesPattern("path/node_modules", "node_modules"));
    try std.testing.expect(PatternMatcher.matchesPattern("node_modules/package", "node_modules"));
    try std.testing.expect(PatternMatcher.matchesPattern("a/node_modules/b", "node_modules"));

    // Test non-matches (leaky patterns) - performance critical behavior preserved
    try std.testing.expect(!PatternMatcher.matchesPattern("my_node_modules", "node_modules"));
    try std.testing.expect(!PatternMatcher.matchesPattern("node_modules_backup", "node_modules"));
    try std.testing.expect(!PatternMatcher.matchesPattern("path/my_node_modules", "node_modules"));
    try std.testing.expect(!PatternMatcher.matchesPattern("path/node_modules_backup", "node_modules"));

    // Test empty and edge cases
    try std.testing.expect(!PatternMatcher.matchesPattern("", "test"));
    try std.testing.expect(!PatternMatcher.matchesPattern("test", ""));
    try std.testing.expect(PatternMatcher.matchesPattern("test", "test"));
}