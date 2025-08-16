const std = @import("std");

/// Semantic version structure
pub const SemanticVersion = struct {
    major: u32,
    minor: u32,
    patch: u32,
    prerelease: []const u8 = "",
    build: []const u8 = "",
    
    /// Compare two semantic versions
    pub fn compare(self: SemanticVersion, other: SemanticVersion) std.math.Order {
        // Compare major version
        if (self.major != other.major) {
            return std.math.order(self.major, other.major);
        }
        
        // Compare minor version
        if (self.minor != other.minor) {
            return std.math.order(self.minor, other.minor);
        }
        
        // Compare patch version
        if (self.patch != other.patch) {
            return std.math.order(self.patch, other.patch);
        }
        
        // If one has prerelease and other doesn't, non-prerelease is greater
        if (self.prerelease.len > 0 and other.prerelease.len == 0) {
            return .lt;
        }
        if (self.prerelease.len == 0 and other.prerelease.len > 0) {
            return .gt;
        }
        
        // Compare prerelease versions lexically
        if (self.prerelease.len > 0 and other.prerelease.len > 0) {
            return std.mem.order(u8, self.prerelease, other.prerelease);
        }
        
        return .eq;
    }
    
    /// Format version as string (for display)
    pub fn format(
        self: SemanticVersion,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        
        try writer.print("{d}.{d}.{d}", .{ self.major, self.minor, self.patch });
        
        if (self.prerelease.len > 0) {
            try writer.print("-{s}", .{self.prerelease});
        }
        
        if (self.build.len > 0) {
            try writer.print("+{s}", .{self.build});
        }
    }
};

/// Parse semantic version string (e.g., "v1.2.3", "1.2.3-alpha", "2.0.0+build123")
pub fn parseSemanticVersion(version: []const u8) !SemanticVersion {
    var clean_version = version;
    
    // Remove 'v' prefix if present
    if (std.mem.startsWith(u8, clean_version, "v")) {
        clean_version = clean_version[1..];
    }
    
    var result = SemanticVersion{
        .major = 0,
        .minor = 0,
        .patch = 0,
    };
    
    // Find build metadata (+ separator)
    if (std.mem.indexOf(u8, clean_version, "+")) |plus_idx| {
        result.build = clean_version[plus_idx + 1 ..];
        clean_version = clean_version[0..plus_idx];
    }
    
    // Find prerelease version (- separator)
    if (std.mem.indexOf(u8, clean_version, "-")) |dash_idx| {
        result.prerelease = clean_version[dash_idx + 1 ..];
        clean_version = clean_version[0..dash_idx];
    }
    
    // Parse major.minor.patch
    var parts = std.mem.splitSequence(u8, clean_version, ".");
    
    const major_str = parts.next() orelse return error.InvalidVersion;
    result.major = std.fmt.parseInt(u32, major_str, 10) catch return error.InvalidVersion;
    
    const minor_str = parts.next() orelse return error.InvalidVersion;
    result.minor = std.fmt.parseInt(u32, minor_str, 10) catch return error.InvalidVersion;
    
    const patch_str = parts.next() orelse return error.InvalidVersion;
    result.patch = std.fmt.parseInt(u32, patch_str, 10) catch return error.InvalidVersion;
    
    // Ensure no extra parts
    if (parts.next() != null) {
        return error.InvalidVersion;
    }
    
    return result;
}

/// Extract major version from a version string
pub fn extractMajorVersion(version: []const u8) !u32 {
    const semantic = try parseSemanticVersion(version);
    return semantic.major;
}

/// Check if a version string represents a major version change
pub fn isMajorVersionChange(old_version: []const u8, new_version: []const u8) !bool {
    const old_major = try extractMajorVersion(old_version);
    const new_major = try extractMajorVersion(new_version);
    return old_major != new_major;
}

/// Clean version string by removing 'v' prefix
pub fn cleanVersionString(version: []const u8) []const u8 {
    return if (std.mem.startsWith(u8, version, "v"))
        version[1..]
    else
        version;
}

// Tests
test "parseSemanticVersion basic" {
    const testing = std.testing;
    
    const v1 = try parseSemanticVersion("1.2.3");
    try testing.expectEqual(@as(u32, 1), v1.major);
    try testing.expectEqual(@as(u32, 2), v1.minor);
    try testing.expectEqual(@as(u32, 3), v1.patch);
    try testing.expectEqualStrings("", v1.prerelease);
    try testing.expectEqualStrings("", v1.build);
    
    const v2 = try parseSemanticVersion("v0.25.0");
    try testing.expectEqual(@as(u32, 0), v2.major);
    try testing.expectEqual(@as(u32, 25), v2.minor);
    try testing.expectEqual(@as(u32, 0), v2.patch);
}

test "parseSemanticVersion with prerelease and build" {
    const testing = std.testing;
    
    const v1 = try parseSemanticVersion("1.0.0-alpha");
    try testing.expectEqual(@as(u32, 1), v1.major);
    try testing.expectEqualStrings("alpha", v1.prerelease);
    
    const v2 = try parseSemanticVersion("2.1.0+build123");
    try testing.expectEqual(@as(u32, 2), v2.major);
    try testing.expectEqualStrings("build123", v2.build);
    
    const v3 = try parseSemanticVersion("3.0.0-beta.1+exp.sha.5114f85");
    try testing.expectEqual(@as(u32, 3), v3.major);
    try testing.expectEqualStrings("beta.1", v3.prerelease);
    try testing.expectEqualStrings("exp.sha.5114f85", v3.build);
}

test "parseSemanticVersion errors" {
    const testing = std.testing;
    
    try testing.expectError(error.InvalidVersion, parseSemanticVersion(""));
    try testing.expectError(error.InvalidVersion, parseSemanticVersion("main"));
    try testing.expectError(error.InvalidVersion, parseSemanticVersion("1"));
    try testing.expectError(error.InvalidVersion, parseSemanticVersion("1.2"));
    try testing.expectError(error.InvalidVersion, parseSemanticVersion("1.2.3.4"));
}

test "SemanticVersion compare" {
    const testing = std.testing;
    
    const v1_0_0 = SemanticVersion{ .major = 1, .minor = 0, .patch = 0 };
    const v1_0_1 = SemanticVersion{ .major = 1, .minor = 0, .patch = 1 };
    const v1_1_0 = SemanticVersion{ .major = 1, .minor = 1, .patch = 0 };
    const v2_0_0 = SemanticVersion{ .major = 2, .minor = 0, .patch = 0 };
    
    try testing.expectEqual(std.math.Order.eq, v1_0_0.compare(v1_0_0));
    try testing.expectEqual(std.math.Order.lt, v1_0_0.compare(v1_0_1));
    try testing.expectEqual(std.math.Order.lt, v1_0_1.compare(v1_1_0));
    try testing.expectEqual(std.math.Order.lt, v1_1_0.compare(v2_0_0));
    try testing.expectEqual(std.math.Order.gt, v2_0_0.compare(v1_0_0));
}

test "SemanticVersion compare with prerelease" {
    const testing = std.testing;
    
    const v1_0_0 = SemanticVersion{ .major = 1, .minor = 0, .patch = 0 };
    const v1_0_0_alpha = SemanticVersion{ .major = 1, .minor = 0, .patch = 0, .prerelease = "alpha" };
    const v1_0_0_beta = SemanticVersion{ .major = 1, .minor = 0, .patch = 0, .prerelease = "beta" };
    
    // Prerelease versions are less than release versions
    try testing.expectEqual(std.math.Order.lt, v1_0_0_alpha.compare(v1_0_0));
    try testing.expectEqual(std.math.Order.gt, v1_0_0.compare(v1_0_0_alpha));
    
    // Alpha < Beta lexically
    try testing.expectEqual(std.math.Order.lt, v1_0_0_alpha.compare(v1_0_0_beta));
}

test "extractMajorVersion" {
    const testing = std.testing;
    
    try testing.expectEqual(@as(u32, 1), try extractMajorVersion("1.2.3"));
    try testing.expectEqual(@as(u32, 2), try extractMajorVersion("v2.0.0"));
    try testing.expectEqual(@as(u32, 10), try extractMajorVersion("10.5.1"));
    try testing.expectEqual(@as(u32, 0), try extractMajorVersion("0.25.0"));
}

test "isMajorVersionChange" {
    const testing = std.testing;
    
    try testing.expect(try isMajorVersionChange("v1.0.0", "v2.0.0"));
    try testing.expect(!(try isMajorVersionChange("v1.0.0", "v1.1.0")));
    try testing.expect(!(try isMajorVersionChange("v0.25.0", "v0.26.0")));
    try testing.expect(try isMajorVersionChange("v0.25.0", "v1.0.0"));
}

test "cleanVersionString" {
    const testing = std.testing;
    
    try testing.expectEqualStrings("1.2.3", cleanVersionString("v1.2.3"));
    try testing.expectEqualStrings("1.2.3", cleanVersionString("1.2.3"));
    try testing.expectEqualStrings("", cleanVersionString("v"));
    try testing.expectEqualStrings("main", cleanVersionString("main"));
}

test "SemanticVersion format" {
    const testing = std.testing;
    
    const v1 = SemanticVersion{ .major = 1, .minor = 2, .patch = 3 };
    const str1 = try std.fmt.allocPrint(testing.allocator, "{}", .{v1});
    defer testing.allocator.free(str1);
    try testing.expectEqualStrings("1.2.3", str1);
    
    const v2 = SemanticVersion{ .major = 2, .minor = 0, .patch = 0, .prerelease = "alpha" };
    const str2 = try std.fmt.allocPrint(testing.allocator, "{}", .{v2});
    defer testing.allocator.free(str2);
    try testing.expectEqualStrings("2.0.0-alpha", str2);
    
    const v3 = SemanticVersion{ .major = 3, .minor = 1, .patch = 0, .build = "build123" };
    const str3 = try std.fmt.allocPrint(testing.allocator, "{}", .{v3});
    defer testing.allocator.free(str3);
    try testing.expectEqualStrings("3.1.0+build123", str3);
}