const std = @import("std");

pub const Filter = struct {
    const Self = @This();

    pub fn shouldIgnore(self: Self, name: []const u8) bool {
        _ = self;
        const ignored_dirs = [_][]const u8{
            "node_modules",
            "dist",
            "build",
            "target",
            "__pycache__",
            "venv",
            "env",
            "Thumbs.db",
            "tmp",
            "temp",
        };

        // Ignore all dot-prefixed directories and files
        if (name.len > 0 and name[0] == '.') {
            return true;
        }

        for (ignored_dirs) |ignored| {
            if (std.mem.eql(u8, name, ignored)) {
                return true;
            }
        }
        return false;
    }
};
