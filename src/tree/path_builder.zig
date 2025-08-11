const std = @import("std");

pub const PathBuilder = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    /// Build a relative path by joining base and name
    /// Caller owns the returned string and must free it
    pub fn buildPath(self: Self, base: []const u8, name: []const u8) ![]u8 {
        if (std.mem.eql(u8, base, ".")) {
            return self.allocator.dupe(u8, name);
        }
        return try std.fs.path.join(self.allocator, &.{ base, name });
    }

    /// Create tree prefix for the next level of indentation
    /// Caller owns the returned string and must free it
    pub fn buildTreePrefix(self: Self, current_prefix: []const u8, is_last: bool) ![]u8 {
        const prefix_addition = if (is_last) "    " else "│   ";
        return try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ current_prefix, prefix_addition });
    }

    /// Get the basename of a path (convenience wrapper)
    pub fn basename(path: []const u8) []const u8 {
        return std.fs.path.basename(path);
    }
};
