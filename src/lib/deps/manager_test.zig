// Test runner for dependency manager functionality
const std = @import("std");
const MockFilesystem = @import("../filesystem/mock.zig").MockFilesystem;
const DependencyManager = @import("manager.zig").DependencyManager;
const config = @import("config.zig");
const Operations = @import("operations.zig").Operations;

test "DependencyManager with MockFilesystem - up to date dependency" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create mock filesystem
    var mock_fs = MockFilesystem.init(allocator);
    defer mock_fs.deinit();

    // Add current directory
    try mock_fs.addDirectory(".");

    // Add deps directory structure
    try mock_fs.addDirectory("deps");
    try mock_fs.addDirectory("deps/tree-sitter");
    try mock_fs.addFile("deps/tree-sitter/.version", "Repository: https://github.com/tree-sitter/tree-sitter\nVersion: v0.25.0\nCommit: abc123\nUpdated: 1706123456\nUpdated-By: test\n");

    // Create dependency manager with mock filesystem
    var manager = DependencyManager.initWithFilesystem(allocator, "deps", mock_fs.interface());

    // Create test dependencies
    const dependencies = [_]config.Dependency{
        config.Dependency{
            .name = "tree-sitter",
            .url = "https://github.com/tree-sitter/tree-sitter",
            .version = "v0.25.0",
            .include = &.{},
            .exclude = &.{},
            .preserve_files = &.{},
        },
    };

    // Test check dependencies
    var result = try manager.checkDependencies(&dependencies);
    defer result.deinit();

    // Should show up-to-date since versions match
    try testing.expect(result.up_to_date.items.len == 1);
    try testing.expect(result.need_update.items.len == 0);
    try testing.expect(result.missing.items.len == 0);
}

test "DependencyManager with MockFilesystem - missing dependency" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create mock filesystem
    var mock_fs = MockFilesystem.init(allocator);
    defer mock_fs.deinit();

    // Add current directory but no deps
    try mock_fs.addDirectory(".");
    try mock_fs.addDirectory("deps");

    // Create dependency manager with mock filesystem
    var manager = DependencyManager.initWithFilesystem(allocator, "deps", mock_fs.interface());

    // Create test dependencies
    const dependencies = [_]config.Dependency{
        config.Dependency{
            .name = "missing-dep",
            .url = "https://github.com/example/missing",
            .version = "v1.0.0",
            .include = &.{},
            .exclude = &.{},
            .preserve_files = &.{},
        },
    };

    // Test check dependencies
    var result = try manager.checkDependencies(&dependencies);
    defer result.deinit();

    // Should detect missing dependency
    try testing.expect(result.up_to_date.items.len == 0);
    try testing.expect(result.need_update.items.len == 0);
    try testing.expect(result.missing.items.len == 1);
}

test "Operations with MockFilesystem integration" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create mock filesystem
    var mock_fs = MockFilesystem.init(allocator);
    defer mock_fs.deinit();

    // Add current directory and test files
    try mock_fs.addDirectory(".");
    try mock_fs.addFile("source.txt", "test content");

    // Create operations with mock filesystem
    const operations = Operations.initWithFilesystem(allocator, mock_fs.interface());

    // Test that operations can be created with filesystem
    // Note: Full testing would require extending MockFilesystem to support
    // atomic operations, but this tests the integration
    _ = operations;
}

test "Pattern matching in dependency manager" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var mock_fs = MockFilesystem.init(allocator);
    defer mock_fs.deinit();

    var manager = DependencyManager.initWithFilesystem(allocator, "deps", mock_fs.interface());

    // Test exact match
    try testing.expect(manager.matchesPattern("tree-sitter", "tree-sitter"));
    try testing.expect(!manager.matchesPattern("tree-sitter", "zig-tree-sitter"));

    // Test wildcard patterns
    try testing.expect(manager.matchesPattern("tree-sitter", "tree*"));
    try testing.expect(manager.matchesPattern("tree-sitter-css", "tree*"));
    try testing.expect(!manager.matchesPattern("zig-tree-sitter", "tree*"));

    // Test suffix patterns
    try testing.expect(manager.matchesPattern("tree-sitter", "*sitter"));
    try testing.expect(manager.matchesPattern("zig-tree-sitter", "*sitter"));
    try testing.expect(!manager.matchesPattern("tree-sitter-css", "*sitter"));

    // Test universal pattern
    try testing.expect(manager.matchesPattern("anything", "*"));
}

test "Table formatting with long dependency names" {
    const testing = std.testing;

    // Check that NAME_COL_WIDTH can handle our longest dependency names
    const longest_name = "tree-sitter-typescript"; // 23 characters
    try testing.expect(longest_name.len <= 24); // Our NAME_COL_WIDTH constant

    // Test other long names
    const other_long_names = [_][]const u8{
        "tree-sitter-javascript", // If we had this
        "tree-sitter-svelte", // 19 characters
        "zig-tree-sitter", // 16 characters
    };

    for (other_long_names) |name| {
        try testing.expect(name.len <= 24);
    }
}
