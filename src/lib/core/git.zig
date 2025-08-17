const std = @import("std");
const io = @import("../core/io.zig");
const process = @import("../core/process.zig");
const path = @import("../core/path.zig");
const errors = @import("../core/errors.zig");
const FilesystemInterface = @import("../filesystem/interface.zig").FilesystemInterface;
const RealFilesystem = @import("../filesystem/real.zig").RealFilesystem;
const ProgressIndicator = @import("../terminal/progress.zig").ProgressIndicator;
const PathMatcher = @import("../deps/path_matcher.zig").PathMatcher;
const PatternValidator = @import("../deps/pattern_validator.zig").PatternValidator;

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

    /// Clone a git repository to the specified destination with pattern filtering
    pub fn clone(self: *Self, url: []const u8, version: []const u8, dest: []const u8, include_patterns: []const []const u8, exclude_patterns: []const []const u8) !void {
        // Create temp directory for clone
        const temp_clone = try std.fmt.allocPrint(self.allocator, "/tmp/zz-deps-{d}", .{std.time.timestamp()});
        defer self.allocator.free(temp_clone);
        defer io.deleteTree(temp_clone) catch {};
        
        // Prepare git clone arguments with better options
        var args = std.ArrayList([]const u8).init(self.allocator);
        defer args.deinit();

        try args.appendSlice(&.{
            "clone",
            "--quiet",                          // Suppress progress output
            "-c", "advice.detachedHead=false",  // Suppress detached HEAD warning
            "--depth", "1",                     // Shallow clone
            "--single-branch",                  // Only fetch the branch we need
        });

        // Add branch argument if not main/master
        if (!std.mem.eql(u8, version, "main") and !std.mem.eql(u8, version, "master")) {
            try args.appendSlice(&.{ "--branch", version });
        }

        try args.appendSlice(&.{ url, temp_clone });

        // Execute git clone to temp directory
        var git_args = try process.buildGitArgs(self.allocator, args.items);
        defer git_args.deinit();
        
        var result = try process.executeCommandWithOptions(self.allocator, git_args.items, .{
            .capture_stdout = false,
            .capture_stderr = false,
            .inherit_stdout = false,
            .inherit_stderr = false,  // Suppress all stderr output including warnings
        });
        defer result.deinit();
        
        if (result.exit_code != 0) {
            return error.GitCloneFailed;
        }
        
        // Validate include patterns match files in the repository (without progress indicator)
        try self.validatePatternsQuiet(temp_clone, include_patterns, exclude_patterns);
        
        // Copy files from temp to dest with pattern filtering
        try self.copyDirectorySelective(temp_clone, dest, include_patterns, exclude_patterns);
    }

    /// Clone a git repository with progress indication and pattern filtering
    /// Returns the commit hash of the cloned repository
    pub fn cloneWithProgress(self: *Self, url: []const u8, version: []const u8, dest: []const u8, include_patterns: []const []const u8, exclude_patterns: []const []const u8, progress: *ProgressIndicator, frame_count: *u32) ![]u8 {
        _ = frame_count; // Suppress unused parameter warning
        
        // Create temp directory for clone
        const temp_clone = try std.fmt.allocPrint(self.allocator, "/tmp/zz-deps-{d}", .{std.time.timestamp()});
        defer self.allocator.free(temp_clone);
        defer io.deleteTree(temp_clone) catch {};
        
        // Prepare git clone arguments with better options
        var args = std.ArrayList([]const u8).init(self.allocator);
        defer args.deinit();

        try args.appendSlice(&.{
            "clone",
            "--quiet",                          // Suppress progress output
            "-c", "advice.detachedHead=false",  // Suppress detached HEAD warning
            "--depth", "1",                     // Shallow clone
            "--single-branch",                  // Only fetch the branch we need
        });

        // Add branch argument if not main/master
        if (!std.mem.eql(u8, version, "main") and !std.mem.eql(u8, version, "master")) {
            try args.appendSlice(&.{ "--branch", version });
        }

        try args.appendSlice(&.{ url, temp_clone });

        // Execute git clone to temp directory
        var git_args = try process.buildGitArgs(self.allocator, args.items);
        defer git_args.deinit();
        
        var result = try process.executeCommandWithOptions(self.allocator, git_args.items, .{
            .capture_stdout = false,
            .capture_stderr = false,
            .inherit_stdout = false,
            .inherit_stderr = false,  // Suppress all stderr output including warnings
        });
        defer result.deinit();
        
        if (result.exit_code != 0) {
            try progress.fail("Git clone failed");
            return error.GitCloneFailed;
        }
        
        // Get commit hash before copying files
        const commit_hash = try self.getCommitHash(temp_clone);
        
        // Validate include patterns match files in the repository
        try self.validatePatterns(temp_clone, include_patterns, exclude_patterns, progress);
        
        // Copy files from temp to dest with pattern filtering
        try self.copyDirectorySelective(temp_clone, dest, include_patterns, exclude_patterns);
        try progress.complete("Fetched successfully");
        
        return commit_hash;
    }

    /// Get the commit hash of a git repository
    pub fn getCommitHash(self: *Self, dir: []const u8) ![]u8 {
        const args = &.{ "-c", "advice.detachedHead=false", "-C", dir, "rev-parse", "HEAD" };

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
        const git_dir = path.joinPath(self.allocator, dir, ".git") catch return false;
        defer self.allocator.free(git_dir);

        return io.isDirectory(git_dir);
    }

    /// Remove .git directory from a cloned repository
    pub fn removeGitDirectory(self: *Self, dir: []const u8) !void {
        const git_dir = try path.joinPath(self.allocator, dir, ".git");
        defer self.allocator.free(git_dir);

        io.deleteTree(git_dir) catch {};
    }
    
    /// Copy directory contents with include/exclude pattern filtering
    fn copyDirectorySelective(self: *Self, src: []const u8, dest: []const u8, include_patterns: []const []const u8, exclude_patterns: []const []const u8) !void {
        // Ensure destination directory exists
        try io.ensureDir(dest);
        
        // Open source directory using filesystem interface
        var src_dir = try self.filesystem.openDir(self.allocator, src, .{});
        defer src_dir.close();
        
        // Get directory iterator
        var iterator = try src_dir.iterate(self.allocator);
        
        while (try iterator.next(self.allocator)) |entry| {
            // Use PathMatcher to determine if file should be copied
            if (!PathMatcher.shouldCopyPath(entry.name, include_patterns, exclude_patterns)) {
                continue;
            }
            
            const src_path = try path.joinPath(self.allocator, src, entry.name);
            defer self.allocator.free(src_path);
            
            const dest_path = try path.joinPath(self.allocator, dest, entry.name);
            defer self.allocator.free(dest_path);
            
            switch (entry.kind) {
                .file => {
                    try io.copyFile(src_path, dest_path);
                },
                .directory => {
                    try self.copyDirectorySelective(src_path, dest_path, include_patterns, exclude_patterns);
                },
                else => continue, // Skip symlinks, etc.
            }
        }
    }
    
    /// Validate include/exclude patterns against repository files
    fn validatePatterns(self: *Self, repo_dir: []const u8, include_patterns: []const []const u8, exclude_patterns: []const []const u8, progress: *ProgressIndicator) !void {
        // Only validate if include patterns are specified
        if (include_patterns.len == 0) return;
        
        var validator = PatternValidator.init(self.allocator, self.filesystem);
        
        // Check if repository has any files
        if (!try validator.hasFiles(repo_dir)) {
            try progress.fail("Repository is empty");
            return error.EmptyRepository;
        }
        
        var validation_result = validator.validateIncludePatterns(repo_dir, include_patterns, exclude_patterns) catch |err| {
            try progress.fail("Pattern validation failed");
            return err;
        };
        defer validation_result.deinit();
        
        // If any include patterns failed to match, provide detailed error
        if (validation_result.failed_patterns.items.len > 0) {
            const error_msg = try validation_result.formatError(self.allocator);
            defer self.allocator.free(error_msg);
            
            // Log detailed error to stderr
            const stderr = std.io.getStdErr().writer();
            try stderr.print("\n{s}\n", .{error_msg});
            
            try progress.fail("Include patterns did not match any files");
            return error.NoIncludeMatches;
        }
    }
    
    /// Validate patterns without progress indicator (for non-progress clone)
    fn validatePatternsQuiet(self: *Self, repo_dir: []const u8, include_patterns: []const []const u8, exclude_patterns: []const []const u8) !void {
        // Only validate if include patterns are specified
        if (include_patterns.len == 0) return;
        
        var validator = PatternValidator.init(self.allocator, self.filesystem);
        
        // Check if repository has any files
        if (!try validator.hasFiles(repo_dir)) {
            return error.EmptyRepository;
        }
        
        var validation_result = try validator.validateIncludePatterns(repo_dir, include_patterns, exclude_patterns);
        defer validation_result.deinit();
        
        // If any include patterns failed to match, provide detailed error
        if (validation_result.failed_patterns.items.len > 0) {
            const error_msg = try validation_result.formatError(self.allocator);
            defer self.allocator.free(error_msg);
            
            // Log detailed error to stderr
            const stderr = std.io.getStdErr().writer();
            try stderr.print("\n{s}\n", .{error_msg});
            
            return error.NoIncludeMatches;
        }
    }
};