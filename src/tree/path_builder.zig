const std = @import("std");
const FilesystemInterface = @import("../filesystem.zig").FilesystemInterface;

pub const PathBuilder = struct {
    allocator: std.mem.Allocator,
    filesystem: FilesystemInterface,

    const Self = @This();

    /// Build a relative path by joining base and name
    /// Caller owns the returned string and must free it
    pub fn buildPath(self: Self, base: []const u8, name: []const u8) ![]u8 {
        if (std.mem.eql(u8, base, ".")) {
            return self.allocator.dupe(u8, name);
        }
        return try self.filesystem.pathJoin(self.allocator, &.{ base, name });
    }

    /// Create tree prefix for the next level of indentation
    /// Caller owns the returned string and must free it
    pub fn buildTreePrefix(self: Self, current_prefix: []const u8, is_last: bool) ![]u8 {
        const prefix_addition = if (is_last) "    " else "│   ";
        return try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ current_prefix, prefix_addition });
    }

    /// Get the basename of a path (convenience wrapper)
    pub fn basename(self: Self, path: []const u8) []const u8 {
        return self.filesystem.pathBasename(path);
    }
};
