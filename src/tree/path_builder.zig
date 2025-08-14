const std = @import("std");
const FilesystemInterface = @import("../lib/core/filesystem.zig").FilesystemInterface;
const PathCache = @import("../lib/memory/pools.zig").PathCache;

pub const PathBuilder = struct {
    allocator: std.mem.Allocator,
    filesystem: FilesystemInterface,
    path_cache: ?*PathCache,

    const Self = @This();

    /// Initialize with optional path cache for performance
    pub fn initWithCache(allocator: std.mem.Allocator, filesystem: FilesystemInterface, path_cache: ?*PathCache) Self {
        return Self{
            .allocator = allocator,
            .filesystem = filesystem,
            .path_cache = path_cache,
        };
    }

    /// Initialize without cache (backward compatibility)
    pub fn init(allocator: std.mem.Allocator, filesystem: FilesystemInterface) Self {
        return Self.initWithCache(allocator, filesystem, null);
    }

    /// Build a relative path by joining base and name
    /// Caller owns the returned string and must free it
    pub fn buildPath(self: Self, base: []const u8, name: []const u8) ![]u8 {
        if (std.mem.eql(u8, base, ".")) {
            // Use cache for single component paths if available
            if (self.path_cache) |cache| {
                const cached = try cache.get(name);
                return try self.allocator.dupe(u8, cached);
            }
            return self.allocator.dupe(u8, name);
        }

        // Use cache for path building if available
        if (self.path_cache) |cache| {
            const cached = try cache.build(base, name);
            return try self.allocator.dupe(u8, cached);
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
