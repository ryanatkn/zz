const std = @import("std");
const BasePatterns = @import("shared.zig").BasePatterns;

pub const PatternResolver = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{ .allocator = allocator };
    }

    // Move these constants to dedicated section for better organization
    const default_ignored = [_][]const u8{
        ".git",        ".svn", ".hg", "node_modules", "dist", "build",      "target",
        "__pycache__", "venv", "env", "tmp",          "temp", ".zig-cache", "zig-out",
        "deps",        "archive",
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
