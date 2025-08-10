const std = @import("std");
const TreeConfig = @import("config.zig").TreeConfig;

pub const Filter = struct {
    tree_config: TreeConfig,

    const Self = @This();

    pub fn init(tree_config: TreeConfig) Self {
        return Self{
            .tree_config = tree_config,
        };
    }

    pub fn shouldIgnore(self: Self, name: []const u8) bool {
        // Check ignored patterns (these show as [...] and stop crawling)
        for (self.tree_config.ignored_patterns) |pattern| {
            if (std.mem.eql(u8, name, pattern)) {
                return true;
            }
        }

        // Ignore all dot-prefixed directories and files (unless specifically configured)
        if (name.len > 0 and name[0] == '.') {
            return true;
        }

        return false;
    }

    pub fn shouldIgnoreAtPath(self: Self, full_path: []const u8) bool {
        // Check if the full path matches any ignored patterns
        for (self.tree_config.ignored_patterns) |pattern| {
            if (std.mem.endsWith(u8, full_path, pattern)) {
                return true;
            }
        }
        return false;
    }

    pub fn shouldHide(self: Self, name: []const u8) bool {
        // Check if it's a completely hidden file (not displayed at all)
        for (self.tree_config.hidden_files) |hidden| {
            if (std.mem.eql(u8, name, hidden)) {
                return true;
            }
        }
        return false;
    }
};
