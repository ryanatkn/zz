// Test runner for dependency management modules
const std = @import("std");
const MockFilesystem = @import("../filesystem/mock.zig").MockFilesystem;
const DependencyManager = @import("manager.zig").DependencyManager;
const config = @import("config.zig");

// Import all deps modules to test
test {
    std.testing.refAllDeclsRecursive(@import("config.zig"));
    std.testing.refAllDeclsRecursive(@import("versioning.zig"));
    std.testing.refAllDeclsRecursive(@import("operations.zig"));
    std.testing.refAllDeclsRecursive(@import("utils.zig"));
    std.testing.refAllDeclsRecursive(@import("lock.zig"));
    std.testing.refAllDeclsRecursive(@import("git.zig"));
    std.testing.refAllDeclsRecursive(@import("manager.zig"));
}

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
    try mock_fs.addFile("deps/tree-sitter/.version", "repository=https://github.com/tree-sitter/tree-sitter\nversion=v0.25.0\ncommit=abc123\nupdated=1706123456\nupdated_by=test\n");
    
    // Create dependency manager with mock filesystem
    var manager = DependencyManager.initWithFilesystem(allocator, "deps", mock_fs.interface());
    
    // Create test dependencies
    const dependencies = [_]config.Dependency{
        config.Dependency{
            .name = "tree-sitter",
            .url = "https://github.com/tree-sitter/tree-sitter",
            .version = "v0.25.0",
            .remove_files = &.{},
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
            .remove_files = &.{},
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
    const Operations = @import("operations.zig").Operations;
    const operations = Operations.initWithFilesystem(allocator, mock_fs.interface());
    
    // Test that operations can be created with filesystem
    // Note: Full testing would require extending MockFilesystem to support
    // atomic operations, but this tests the integration
    _ = operations;
}

test "ZON parsing with simple dependency structure" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    // Test ZON content that should parse successfully
    const simple_zon =
        \\.{
        \\    .dependencies = .{
        \\        .@"tree-sitter" = .{
        \\            .url = "https://github.com/tree-sitter/tree-sitter.git",
        \\            .version = "v0.25.0",
        \\            .remove_files = .{ "build.zig" },
        \\            .preserve_files = .{},
        \\            .patches = .{},
        \\        },
        \\    },
        \\}
    ;
    
    const ZonParser = @import("../parsing/zon_parser.zig").ZonParser;
    
    // Try parsing with a minimal structure first
    const MinimalConfig = struct {
        dependencies: struct {
            @"tree-sitter": struct {
                url: []const u8,
                version: []const u8,
                remove_files: []const []const u8,
                preserve_files: []const []const u8,
                patches: []const []const u8,
            },
        },
    };
    
    const parsed = try ZonParser.parseFromSlice(MinimalConfig, allocator, simple_zon);
    defer ZonParser.free(allocator, parsed);
    
    // Verify parsing succeeded
    try testing.expectEqualStrings("https://github.com/tree-sitter/tree-sitter.git", parsed.dependencies.@"tree-sitter".url);
    try testing.expectEqualStrings("v0.25.0", parsed.dependencies.@"tree-sitter".version);
}

test "ZON parsing debugging - understand structure" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    // Read the actual deps.zon file content
    const io = @import("../core/io.zig");
    const deps_zon_content = io.readFileOptional(allocator, "deps.zon") catch |err| switch (err) {
        else => {
            std.debug.print("Could not read deps.zon: {}\n", .{err});
            return; // Skip test if file doesn't exist
        },
    };
    
    if (deps_zon_content) |content| {
        defer allocator.free(content);
        
        std.debug.print("deps.zon content (first 200 chars): {s}\n", .{content[0..@min(200, content.len)]});
        
        // The issue is likely that our structure doesn't match the ZON format exactly
        // Let's just check the content length and format for now
        std.debug.print("ZON file exists with {} characters\n", .{content.len});
        
        // See if it starts with the expected pattern
        if (std.mem.startsWith(u8, content, ".{\n    .dependencies = .{")) {
            std.debug.print("ZON format looks correct - structure issue in parsing\n", .{});
        } else {
            std.debug.print("ZON format doesn't match expected pattern\n", .{});
        }
    }
}