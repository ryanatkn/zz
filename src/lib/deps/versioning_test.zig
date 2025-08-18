// Tests for versioning functionality
const std = @import("std");
const MockFilesystem = @import("../filesystem/mock.zig").MockFilesystem;
const Versioning = @import("versioning.zig").Versioning;

test "Versioning module - semantic version comparison" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var mock_fs = MockFilesystem.init(allocator);
    defer mock_fs.deinit();

    var versioning = Versioning.initWithFilesystem(allocator, mock_fs.interface());

    // Test version comparison using compareVersions
    try testing.expectEqual(std.math.Order.gt, try versioning.compareVersions("v1.2.3", "v1.2.2"));
    try testing.expectEqual(std.math.Order.gt, try versioning.compareVersions("v2.0.0", "v1.9.9"));
    try testing.expectEqual(std.math.Order.lt, try versioning.compareVersions("v1.2.2", "v1.2.3"));
    try testing.expectEqual(std.math.Order.eq, try versioning.compareVersions("v1.2.3", "v1.2.3"));

    // Test semantic version parsing
    const sem_ver = try Versioning.parseSemanticVersion("v1.2.3");
    try testing.expectEqual(@as(u32, 1), sem_ver.major);
    try testing.expectEqual(@as(u32, 2), sem_ver.minor);
    try testing.expectEqual(@as(u32, 3), sem_ver.patch);
}

test "Versioning module - needsUpdate with mock filesystem" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var mock_fs = MockFilesystem.init(allocator);
    defer mock_fs.deinit();

    // Add test directory structure
    try mock_fs.addDirectory("deps");
    try mock_fs.addDirectory("deps/test-dep");
    try mock_fs.addFile("deps/test-dep/.version", "Repository: https://github.com/test/repo\nVersion: v1.0.0\nCommit: abc123\nUpdated: 1706123456\nUpdated-By: test\n");

    var versioning = Versioning.initWithFilesystem(allocator, mock_fs.interface());

    // Test that same version doesn't need update
    const same_version_needs_update = try versioning.needsUpdate("test-dep", "v1.0.0", "deps");
    try testing.expect(!same_version_needs_update);

    // Test that newer version needs update
    try testing.expect(try versioning.needsUpdate("test-dep", "v1.1.0", "deps"));

    // Test that missing dependency needs update
    try testing.expect(try versioning.needsUpdate("missing-dep", "v1.0.0", "deps"));
}
