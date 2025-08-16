const std = @import("std");
const io = @import("../core/io.zig");
const FilesystemInterface = @import("../filesystem/interface.zig").FilesystemInterface;
const RealFilesystem = @import("../filesystem/real.zig").RealFilesystem;

/// Git operations wrapper for dependency management
pub const Git = struct {
    allocator: std.mem.Allocator,
    filesystem: FilesystemInterface,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self.initWithFilesystem(allocator, RealFilesystem.init());
    }

    pub fn initWithFilesystem(allocator: std.mem.Allocator, filesystem: FilesystemInterface) Self {
        return Self{
            .allocator = allocator,
            .filesystem = filesystem,
        };
    }

    /// Clone a git repository to the specified destination
    pub fn clone(self: *Self, url: []const u8, version: []const u8, dest: []const u8) !void {
        // Prepare git clone arguments
        var args = std.ArrayList([]const u8).init(self.allocator);
        defer args.deinit();

        try args.appendSlice(&.{ "git", "clone", "--quiet", "--depth", "1" });

        // Add branch argument if not main/master
        if (!std.mem.eql(u8, version, "main") and !std.mem.eql(u8, version, "master")) {
            try args.appendSlice(&.{ "--branch", version });
        }

        try args.appendSlice(&.{ url, dest });

        // Execute git clone
        var child = std.process.Child.init(args.items, self.allocator);
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Inherit;

        const result = try child.spawnAndWait();
        switch (result) {
            .Exited => |code| {
                if (code != 0) {
                    return error.GitCloneFailed;
                }
            },
            else => return error.GitCloneFailed,
        }
    }

    /// Get the commit hash of a git repository
    pub fn getCommitHash(self: *Self, dir: []const u8) ![]u8 {
        const args = &.{ "git", "-C", dir, "rev-parse", "HEAD" };

        var child = std.process.Child.init(args, self.allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Ignore;

        try child.spawn();

        var stdout_buf: [1024]u8 = undefined;
        const stdout_len = try child.stdout.?.read(&stdout_buf);
        
        const result = try child.wait();
        switch (result) {
            .Exited => |code| {
                if (code != 0) {
                    return error.GitHashFailed;
                }
            },
            else => return error.GitHashFailed,
        }

        const hash = std.mem.trim(u8, stdout_buf[0..stdout_len], " \t\r\n");
        return try self.allocator.dupe(u8, hash);
    }

    /// Check if a directory is a git repository
    pub fn isGitRepository(self: *Self, dir: []const u8) bool {
        const git_dir = std.fmt.allocPrint(self.allocator, "{s}/.git", .{dir}) catch return false;
        defer self.allocator.free(git_dir);

        return io.isDirectory(git_dir);
    }

    /// Remove .git directory from a cloned repository
    pub fn removeGitDirectory(self: *Self, dir: []const u8) !void {
        const git_dir = try std.fmt.allocPrint(self.allocator, "{s}/.git", .{dir});
        defer self.allocator.free(git_dir);

        io.deleteTree(git_dir) catch {};
    }
};