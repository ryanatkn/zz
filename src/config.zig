const std = @import("std");

pub const SymlinkBehavior = enum {
    follow,
    skip,
    show,

    pub fn fromString(str: []const u8) ?SymlinkBehavior {
        if (std.mem.eql(u8, str, "follow")) return .follow;
        if (std.mem.eql(u8, str, "skip")) return .skip;
        if (std.mem.eql(u8, str, "show")) return .show;
        return null;
    }
};

pub const BasePatterns = union(enum) {
    extend,
    custom: []const []const u8,

    pub fn fromZon(value: anytype) BasePatterns {
        switch (@TypeOf(value)) {
            []const u8 => {
                if (std.mem.eql(u8, value, "extend")) return .extend;
                return .extend; // Default fallback
            },
            []const []const u8 => return .{ .custom = value },
            else => return .extend, // Default fallback
        }
    }
};

pub const SharedConfig = struct {
    ignored_patterns: []const []const u8,
    hidden_files: []const []const u8,
    symlink_behavior: SymlinkBehavior,
    patterns_allocated: bool,

    const Self = @This();

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        if (self.patterns_allocated) {
            for (self.ignored_patterns) |pattern| {
                allocator.free(pattern);
            }
            for (self.hidden_files) |file| {
                allocator.free(file);
            }
            allocator.free(self.ignored_patterns);
            allocator.free(self.hidden_files);
        }
    }
};

pub const ZonConfig = struct {
    base_patterns: ?BasePatterns = null,
    ignored_patterns: ?[]const []const u8 = null,
    hidden_files: ?[]const []const u8 = null,
    symlink_behavior: ?SymlinkBehavior = null,
    tree: ?TreeSection = null,
    prompt: ?PromptSection = null,

    const TreeSection = struct {
        // Tree-specific overrides if needed in future
    };

    const PromptSection = struct {
        // Prompt-specific overrides if needed in future
    };
};

pub const PatternResolver = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{ .allocator = allocator };
    }

    const default_ignored = [_][]const u8{
        ".git",        ".svn", ".hg", "node_modules", "dist", "build",      "target",
        "__pycache__", "venv", "env", "tmp",          "temp", ".zig-cache", "zig-out",
    };

    const default_hidden = [_][]const u8{ ".DS_Store", "Thumbs.db" };

    pub fn resolveIgnoredPatterns(self: Self, base_patterns: BasePatterns, user_patterns: ?[]const []const u8) ![]const []const u8 {
        switch (base_patterns) {
            .extend => {
                const user = user_patterns orelse &[_][]const u8{};

                // Allocate space for defaults + user patterns
                const total_len = default_ignored.len + user.len;
                const result = try self.allocator.alloc([]const u8, total_len);

                // Copy defaults
                for (default_ignored, 0..) |pattern, i| {
                    result[i] = try self.allocator.dupe(u8, pattern);
                }

                // Copy user patterns
                for (user, 0..) |pattern, i| {
                    result[default_ignored.len + i] = try self.allocator.dupe(u8, pattern);
                }

                return result;
            },
            .custom => |custom_patterns| {
                // Use only custom patterns, no defaults
                const result = try self.allocator.alloc([]const u8, custom_patterns.len);
                for (custom_patterns, 0..) |pattern, i| {
                    result[i] = try self.allocator.dupe(u8, pattern);
                }
                return result;
            },
        }
    }

    pub fn resolveHiddenFiles(self: Self, user_hidden: ?[]const []const u8) ![]const []const u8 {
        const user = user_hidden orelse &[_][]const u8{};

        // Always extend defaults for hidden files
        const total_len = default_hidden.len + user.len;
        const result = try self.allocator.alloc([]const u8, total_len);

        // Copy defaults
        for (default_hidden, 0..) |file, i| {
            result[i] = try self.allocator.dupe(u8, file);
        }

        // Copy user hidden files
        for (user, 0..) |file, i| {
            result[default_hidden.len + i] = try self.allocator.dupe(u8, file);
        }

        return result;
    }
};

// DRY helper functions for common config operations
pub fn shouldIgnorePath(config: SharedConfig, path: []const u8) bool {
    // Built-in behavior: automatically ignore dot-prefixed directories/files
    const basename = std.fs.path.basename(path);
    if (basename.len > 0 and basename[0] == '.') {
        return true;
    }
    
    // Check user-configured patterns
    for (config.ignored_patterns) |pattern| {
        if (hasGlobChars(pattern)) {
            // Extract filename for pattern matching
            const filename = std.fs.path.basename(path);
            if (matchSimplePattern(filename, pattern)) {
                return true;
            }
        } else {
            // Check for exact component match (not leaky substring)
            // Inline fast/slow path decision for better performance
            if (std.mem.indexOf(u8, pattern, "/") == null) {
                if (matchesSimpleComponentInline(path, pattern)) {
                    return true;
                }
            } else {
                if (matchesPathSegment(path, pattern)) {
                    return true;
                }
            }
        }
    }
    return false;
}

// Inline version of fast path for even better performance in hot loop
inline fn matchesSimpleComponentInline(path: []const u8, pattern: []const u8) bool {
    // Quick basename check first (most common case)
    const basename = std.fs.path.basename(path);
    if (std.mem.eql(u8, basename, pattern)) {
        return true;
    }
    
    // Only do component iteration if needed and path has separators
    if (std.mem.indexOf(u8, path, "/") == null) {
        return false; // Single component already checked
    }
    
    // Check each path component
    var parts = std.mem.splitScalar(u8, path, '/');
    while (parts.next()) |part| {
        if (std.mem.eql(u8, part, pattern)) {
            return true;
        }
    }
    
    return false;
}

// Safe path component matching - optimized with fast/slow paths
// Fast path for simple patterns (no slashes) - handles 90% of use cases efficiently
// Slow path for complex path segment patterns - handles remaining 10%
fn matchesPathComponent(path: []const u8, pattern: []const u8) bool {
    // Fast path: Simple patterns without slashes (90% of use cases)
    if (std.mem.indexOf(u8, pattern, "/") == null) {
        return matchesSimpleComponent(path, pattern);
    }
    
    // Slow path: Complex path segment patterns (10% of use cases)  
    return matchesPathSegment(path, pattern);
}

// Fast path: Optimized matching for simple component patterns (no slashes)
// This restores the original performance for the common case
inline fn matchesSimpleComponent(path: []const u8, pattern: []const u8) bool {
    // Quick basename check first (most common case)
    const basename = std.fs.path.basename(path);
    if (std.mem.eql(u8, basename, pattern)) {
        return true;
    }
    
    // Only do expensive component iteration if basename doesn't match
    // and the path contains separators (optimization for single-component paths)
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

// Slow path: Complex matching for path segment patterns (with slashes)
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

// Helper function for glob pattern detection
fn hasGlobChars(pattern: []const u8) bool {
    return std.mem.indexOf(u8, pattern, "*") != null or
        std.mem.indexOf(u8, pattern, "?") != null;
}

// Simple glob pattern matching (basic implementation)
fn matchSimplePattern(text: []const u8, pattern: []const u8) bool {
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

pub const ZonLoader = struct {
    allocator: std.mem.Allocator,
    config: ?ZonConfig,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .config = null,
        };
    }

    pub fn load(self: *Self) !void {
        if (self.config != null) return; // Already loaded

        const config_path = "zz.zon";
        const file_content = std.fs.cwd().readFileAlloc(self.allocator, config_path, 1024 * 1024) catch |err| switch (err) {
            error.FileNotFound => {
                self.config = ZonConfig{}; // Empty config
                return;
            },
            else => return err,
        };
        defer self.allocator.free(file_content);

        // Add null terminator for ZON parsing
        const null_terminated = try self.allocator.dupeZ(u8, file_content);
        defer self.allocator.free(null_terminated);

        // Parse the ZON content
        const parsed = std.zon.parse.fromSlice(ZonConfig, self.allocator, null_terminated, null, .{}) catch {
            self.config = ZonConfig{}; // Empty config on parse error
            return;
        };

        self.config = parsed;
    }

    pub fn getSharedConfig(self: *Self) !SharedConfig {
        try self.load();

        const config = self.config orelse ZonConfig{};

        // Resolve base patterns (default to "extend")
        const base_patterns = config.base_patterns orelse BasePatterns.extend;

        // Create pattern resolver
        const resolver = PatternResolver.init(self.allocator);

        // Resolve ignored patterns
        const ignored_patterns = try resolver.resolveIgnoredPatterns(base_patterns, config.ignored_patterns);

        // Resolve hidden files
        const hidden_files = try resolver.resolveHiddenFiles(config.hidden_files);

        // Resolve symlink behavior (default to skip - DISABLED by default)
        const symlink_behavior = config.symlink_behavior orelse SymlinkBehavior.skip;

        return SharedConfig{
            .ignored_patterns = ignored_patterns,
            .hidden_files = hidden_files,
            .symlink_behavior = symlink_behavior,
            .patterns_allocated = true,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.config) |config| {
            std.zon.parse.free(self.allocator, config);
        }
    }
};

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
        .symlink_behavior = .skip,
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
        .symlink_behavior = .skip,
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

test "matchesPathComponent edge cases" {
    // Test exact component matches
    try std.testing.expect(matchesPathComponent("node_modules", "node_modules"));
    try std.testing.expect(matchesPathComponent("path/node_modules", "node_modules"));
    try std.testing.expect(matchesPathComponent("node_modules/package", "node_modules"));
    try std.testing.expect(matchesPathComponent("a/node_modules/b", "node_modules"));

    // Test non-matches (leaky patterns)
    try std.testing.expect(!matchesPathComponent("my_node_modules", "node_modules"));
    try std.testing.expect(!matchesPathComponent("node_modules_backup", "node_modules"));
    try std.testing.expect(!matchesPathComponent("path/my_node_modules", "node_modules"));
    try std.testing.expect(!matchesPathComponent("path/node_modules_backup", "node_modules"));

    // Test empty and edge cases
    try std.testing.expect(!matchesPathComponent("", "test"));
    try std.testing.expect(!matchesPathComponent("test", ""));
    try std.testing.expect(matchesPathComponent("test", "test"));
}
