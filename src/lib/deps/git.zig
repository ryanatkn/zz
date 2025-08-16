const std = @import("std");
const io = @import("../core/io.zig");
const process = @import("../core/process.zig");
const FilesystemInterface = @import("../filesystem/interface.zig").FilesystemInterface;
const RealFilesystem = @import("../filesystem/real.zig").RealFilesystem;
const ProgressIndicator = @import("../terminal/progress.zig").ProgressIndicator;

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

        try args.appendSlice(&.{ "clone", "--quiet", "--depth", "1" });

        // Add branch argument if not main/master
        if (!std.mem.eql(u8, version, "main") and !std.mem.eql(u8, version, "master")) {
            try args.appendSlice(&.{ "--branch", version });
        }

        try args.appendSlice(&.{ url, dest });

        // Execute git clone using process utilities
        var git_args = try process.buildGitArgs(self.allocator, args.items);
        defer git_args.deinit();
        
        var result = try process.executeCommandWithInheritedStderr(self.allocator, git_args.items);
        defer result.deinit();
        
        if (result.exit_code != 0) {
            return error.GitCloneFailed;
        }
    }

    /// Clone a git repository with progress indication
    pub fn cloneWithProgress(self: *Self, url: []const u8, version: []const u8, dest: []const u8, progress: *ProgressIndicator, frame_count: *u32) !void {
        _ = frame_count; // Suppress unused parameter warning
        
        // Prepare git clone arguments
        var args = std.ArrayList([]const u8).init(self.allocator);
        defer args.deinit();

        try args.appendSlice(&.{ "clone", "--quiet", "--depth", "1" });

        // Add branch argument if not main/master
        if (!std.mem.eql(u8, version, "main") and !std.mem.eql(u8, version, "master")) {
            try args.appendSlice(&.{ "--branch", version });
        }

        try args.appendSlice(&.{ url, dest });

        // Execute git clone using process utilities with progress updates
        var git_args = try process.buildGitArgs(self.allocator, args.items);
        defer git_args.deinit();
        
        // Simple approach: just run the command and show completion
        var result = try process.executeCommandWithInheritedStderr(self.allocator, git_args.items);
        defer result.deinit();
        
        if (result.exit_code != 0) {
            try progress.fail("Git clone failed");
            return error.GitCloneFailed;
        }
        
        try progress.complete("Fetched successfully");
    }

    /// Get the commit hash of a git repository
    pub fn getCommitHash(self: *Self, dir: []const u8) ![]u8 {
        const args = &.{ "-C", dir, "rev-parse", "HEAD" };

        var git_args = try process.buildGitArgs(self.allocator, args);
        defer git_args.deinit();
        
        const output = process.executeCommandForOutput(self.allocator, git_args.items) catch {
            return error.GitHashFailed;
        };
        defer self.allocator.free(output);
        
        return process.parseCommandOutput(self.allocator, output) catch {
            return error.GitHashFailed;
        };
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