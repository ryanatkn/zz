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
    gitignore_patterns: []const []const u8,
    symlink_behavior: SymlinkBehavior,
    respect_gitignore: bool,
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
            for (self.gitignore_patterns) |pattern| {
                allocator.free(pattern);
            }
            allocator.free(self.ignored_patterns);
            allocator.free(self.hidden_files);
            allocator.free(self.gitignore_patterns);
        }
    }
};
