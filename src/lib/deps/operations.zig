const std = @import("std");
const path = @import("../core/path.zig");
const errors = @import("../core/errors.zig");
const io = @import("../core/io.zig");
const collections = @import("../core/collections.zig");
const FilesystemInterface = @import("../filesystem/interface.zig").FilesystemInterface;
const RealFilesystem = @import("../filesystem/real.zig").RealFilesystem;

/// Atomic file operations for dependency management
pub const Operations = struct {
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

    /// Create a backup of a directory
    pub fn createBackup(self: *Self, source_dir: []const u8) ![]u8 {
        const timestamp = std.time.timestamp();
        const backup_name = try std.fmt.allocPrint(self.allocator, "{s}-backup-{d}", .{ path.basename(source_dir), timestamp });
        defer self.allocator.free(backup_name);

        const parent_dir = path.dirname(source_dir);
        const backup_dir = try path.joinPath(self.allocator, parent_dir, ".backups");
        defer self.allocator.free(backup_dir);

        // Create backups directory using existing error handling
        try errors.makeDir(backup_dir);

        const full_backup_path = try path.joinPath(self.allocator, backup_dir, backup_name);

        // Copy directory recursively
        try self.copyDirectoryRecursive(source_dir, full_backup_path);

        return full_backup_path;
    }

    /// Restore from backup
    pub fn restoreFromBackup(self: *Self, backup_path: []const u8, target_dir: []const u8) !void {
        // Remove existing target directory using core/io.zig pattern
        try io.deleteTree(target_dir);

        // Copy backup to target
        try self.copyDirectoryRecursive(backup_path, target_dir);
    }

    /// Preserve files from a directory (copy to temp location)
    pub fn preserveFiles(self: *Self, dir: []const u8, files_to_preserve: []const []const u8) ![][]u8 {
        var preserved_files = collections.List([]u8).init(self.allocator);
        defer preserved_files.deinit();

        for (files_to_preserve) |file_pattern| {
            const source_path = try path.joinPath(self.allocator, dir, file_pattern);
            defer self.allocator.free(source_path);

            // Check if file exists
            if (!io.fileExists(source_path)) continue;
            if (io.isDirectory(source_path)) continue; // Skip directories

            // Read file content using core/io.zig
            const content = (try io.readFileOptional(self.allocator, source_path)) orelse continue;

            // Store content with file pattern as key
            const preserved_file = try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ file_pattern, content });
            try preserved_files.append(preserved_file);
        }

        return preserved_files.toOwnedSlice();
    }

    /// Restore preserved files to a directory
    pub fn restorePreservedFiles(self: *Self, dir: []const u8, preserved_files: [][]u8) !void {
        for (preserved_files) |preserved_file| {
            // Parse pattern:content format
            const colon_idx = std.mem.indexOf(u8, preserved_file, ":") orelse continue;
            const file_pattern = preserved_file[0..colon_idx];
            const content = preserved_file[colon_idx + 1 ..];

            const target_path = try path.joinPath(self.allocator, dir, file_pattern);
            defer self.allocator.free(target_path);

            // Write file using core/io.zig
            try io.writeFile(target_path, content);
        }
    }

    /// Free preserved files array
    pub fn freePreservedFiles(self: *Self, preserved_files: [][]u8) void {
        for (preserved_files) |file| {
            self.allocator.free(file);
        }
        self.allocator.free(preserved_files);
    }

    /// Atomic move operation (using temp directory)
    pub fn atomicMove(self: *Self, source: []const u8, destination: []const u8) !void {
        // Create temporary destination
        const temp_dest = try std.fmt.allocPrint(self.allocator, "{s}.tmp-{d}", .{ destination, std.time.timestamp() });
        defer self.allocator.free(temp_dest);

        // Move source to temp location first
        try io.rename(source, temp_dest);

        // Then move temp to final destination
        io.rename(temp_dest, destination) catch |err| {
            // If final move fails, try to restore from temp
            // Safe to ignore: If restore fails, original source is already gone - nothing we can do
            io.rename(temp_dest, source) catch {};
            return err;
        };
    }

    /// Copy directory recursively
    fn copyDirectoryRecursive(self: *Self, source: []const u8, destination: []const u8) !void {
        // Use core/io.zig's copyDirectory function
        try io.copyDirectory(self.allocator, source, destination);
    }
};
