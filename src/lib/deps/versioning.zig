const std = @import("std");
const config = @import("config.zig");
const utils = @import("utils.zig");
const io = @import("../core/io.zig");
const FilesystemInterface = @import("../filesystem/interface.zig").FilesystemInterface;
const RealFilesystem = @import("../filesystem/real.zig").RealFilesystem;

/// Semantic version structure
const SemanticVersion = struct {
    major: u32,
    minor: u32,
    patch: u32,
};

/// Version comparison and parsing utilities
pub const Versioning = struct {
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

    /// Check if a dependency needs to be updated
    pub fn needsUpdate(self: *Self, dep_name: []const u8, expected_version: []const u8, deps_dir: []const u8) !bool {
        const target_dir = try utils.Utils.buildPath(self.allocator, &.{ deps_dir, dep_name });
        defer self.allocator.free(target_dir);

        // Check if directory exists
        if (!utils.Utils.directoryExists(target_dir)) {
            return true; // Needs update if missing
        }

        // Check if .git directory exists (not properly vendored)
        const git_dir = try utils.Utils.buildPath(self.allocator, &.{ target_dir, ".git" });
        defer self.allocator.free(git_dir);

        if (utils.Utils.directoryExists(git_dir)) {
            return true; // .git directory exists, needs cleanup
        }

        // Check version file
        const version_file = try utils.Utils.buildPath(self.allocator, &.{ target_dir, ".version" });
        defer self.allocator.free(version_file);

        const version_content = (try utils.Utils.readFileOptional(self.allocator, version_file, 1024)) orelse {
            return true; // No version file, needs update
        };
        defer self.allocator.free(version_content);

        const version_info = try config.VersionInfo.parseFromContent(self.allocator, version_content);
        defer version_info.deinit(self.allocator);

        // Compare versions
        return !std.mem.eql(u8, version_info.version, expected_version);
    }

    /// Load version information from a dependency directory
    pub fn loadVersionInfo(self: *Self, dep_dir: []const u8) !?config.VersionInfo {
        const version_file = try utils.Utils.buildPath(self.allocator, &.{ dep_dir, ".version" });
        defer self.allocator.free(version_file);

        const content = (try utils.Utils.readFileOptional(self.allocator, version_file, 1024)) orelse return null;
        defer self.allocator.free(content);

        return try config.VersionInfo.parseFromContent(self.allocator, content);
    }

    /// Save version information to a dependency directory
    pub fn saveVersionInfo(self: *Self, dep_dir: []const u8, version_info: *const config.VersionInfo) !void {
        const version_file = try utils.Utils.buildPath(self.allocator, &.{ dep_dir, ".version" });
        defer self.allocator.free(version_file);

        const content = try version_info.toContent(self.allocator);
        defer self.allocator.free(content);

        try io.writeFile(version_file, content);
    }

    /// Compare semantic versions (proper implementation)
    pub fn compareVersions(self: *Self, version1: []const u8, version2: []const u8) !std.math.Order {
        _ = self;
        
        if (std.mem.eql(u8, version1, version2)) {
            return .eq;
        }
        
        // Parse both versions
        const parsed1 = parseSemanticVersion(version1) catch {
            // If parsing fails, fall back to string comparison
            return std.mem.order(u8, version1, version2);
        };
        const parsed2 = parseSemanticVersion(version2) catch {
            return std.mem.order(u8, version1, version2);
        };
        
        // Compare major version
        if (parsed1.major != parsed2.major) {
            return std.math.order(parsed1.major, parsed2.major);
        }
        
        // Compare minor version
        if (parsed1.minor != parsed2.minor) {
            return std.math.order(parsed1.minor, parsed2.minor);
        }
        
        // Compare patch version
        return std.math.order(parsed1.patch, parsed2.patch);
    }

    /// Parse version string to detect major version changes
    pub fn detectMajorVersionChange(self: *Self, old_version: []const u8, new_version: []const u8) !bool {
        _ = self;
        
        // Extract major version numbers
        const old_major = extractMajorVersion(old_version) catch return false;
        const new_major = extractMajorVersion(new_version) catch return false;
        
        return old_major != new_major;
    }

    pub fn extractMajorVersion(version: []const u8) !u32 {
        const clean_version = utils.Utils.cleanVersionString(version);

        // Find first dot or end of string
        var end_idx: usize = 0;
        for (clean_version, 0..) |char, idx| {
            if (char == '.') {
                end_idx = idx;
                break;
            }
            if (!std.ascii.isDigit(char)) {
                break;
            }
            end_idx = idx + 1;
        }

        if (end_idx == 0) return error.InvalidVersion;

        return try std.fmt.parseInt(u32, clean_version[0..end_idx], 10);
    }
    
    /// Parse semantic version string (e.g., "v1.2.3" or "1.2.3")
    pub fn parseSemanticVersion(version: []const u8) !SemanticVersion {
        const clean_version = utils.Utils.cleanVersionString(version);

        // Split by dots
        var parts = std.mem.splitSequence(u8, clean_version, ".");
        
        const major_str = parts.next() orelse return error.InvalidVersion;
        const minor_str = parts.next() orelse return error.InvalidVersion;
        const patch_str = parts.next() orelse return error.InvalidVersion;
        
        return SemanticVersion{
            .major = try std.fmt.parseInt(u32, major_str, 10),
            .minor = try std.fmt.parseInt(u32, minor_str, 10),
            .patch = try std.fmt.parseInt(u32, patch_str, 10),
        };
    }
};

test "extractMajorVersion" {
    const testing = std.testing;
    
    try testing.expectEqual(@as(u32, 1), try Versioning.extractMajorVersion("1.2.3"));
    try testing.expectEqual(@as(u32, 2), try Versioning.extractMajorVersion("v2.0.0"));
    try testing.expectEqual(@as(u32, 10), try Versioning.extractMajorVersion("10.5"));
    try testing.expectEqual(@as(u32, 0), try Versioning.extractMajorVersion("0.25.0"));
    
    try testing.expectError(error.InvalidVersion, Versioning.extractMajorVersion("main"));
    try testing.expectError(error.InvalidVersion, Versioning.extractMajorVersion("v"));
}

test "detectMajorVersionChange" {
    const testing = std.testing;
    var versioning = Versioning.init(testing.allocator);
    
    try testing.expect(try versioning.detectMajorVersionChange("v1.0.0", "v2.0.0"));
    try testing.expect(!(try versioning.detectMajorVersionChange("v1.0.0", "v1.1.0")));
    try testing.expect(!(try versioning.detectMajorVersionChange("v0.25.0", "v0.26.0")));
    try testing.expect(try versioning.detectMajorVersionChange("v0.25.0", "v1.0.0"));
}

test "parseSemanticVersion" {
    const testing = std.testing;
    
    const v1 = try Versioning.parseSemanticVersion("1.2.3");
    try testing.expectEqual(@as(u32, 1), v1.major);
    try testing.expectEqual(@as(u32, 2), v1.minor);
    try testing.expectEqual(@as(u32, 3), v1.patch);
    
    const v2 = try Versioning.parseSemanticVersion("v0.25.0");
    try testing.expectEqual(@as(u32, 0), v2.major);
    try testing.expectEqual(@as(u32, 25), v2.minor);
    try testing.expectEqual(@as(u32, 0), v2.patch);
    
    try testing.expectError(error.InvalidVersion, Versioning.parseSemanticVersion("main"));
    try testing.expectError(error.InvalidVersion, Versioning.parseSemanticVersion("1.2"));
    try testing.expectError(error.InvalidVersion, Versioning.parseSemanticVersion(""));
}

test "compareVersions" {
    const testing = std.testing;
    var versioning = Versioning.init(testing.allocator);
    
    try testing.expectEqual(std.math.Order.eq, try versioning.compareVersions("1.2.3", "1.2.3"));
    try testing.expectEqual(std.math.Order.lt, try versioning.compareVersions("1.2.3", "1.2.4"));
    try testing.expectEqual(std.math.Order.gt, try versioning.compareVersions("1.3.0", "1.2.9"));
    try testing.expectEqual(std.math.Order.lt, try versioning.compareVersions("0.25.0", "1.0.0"));
    
    // Test with v prefix
    try testing.expectEqual(std.math.Order.eq, try versioning.compareVersions("v1.2.3", "v1.2.3"));
    try testing.expectEqual(std.math.Order.lt, try versioning.compareVersions("v1.2.3", "v2.0.0"));
}