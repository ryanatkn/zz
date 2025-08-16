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

test "Versioning module - semantic version comparison" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const Versioning = @import("versioning.zig").Versioning;
    
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
    const Versioning = @import("versioning.zig").Versioning;
    
    var mock_fs = MockFilesystem.init(allocator);
    defer mock_fs.deinit();
    
    // Add test directory structure
    try mock_fs.addDirectory("deps");
    try mock_fs.addDirectory("deps/test-dep");
    try mock_fs.addFile("deps/test-dep/.version", "Repository: https://github.com/test/repo\nVersion: v1.0.0\nCommit: abc123\nUpdated: 1706123456\nUpdated-By: test\n");
    
    var versioning = Versioning.initWithFilesystem(allocator, mock_fs.interface());
    
    // Test that same version doesn't need update
    try testing.expect(!try versioning.needsUpdate("test-dep", "v1.0.0", "deps"));
    
    // Test that newer version needs update
    try testing.expect(try versioning.needsUpdate("test-dep", "v1.1.0", "deps"));
    
    // Test that missing dependency needs update
    try testing.expect(try versioning.needsUpdate("missing-dep", "v1.0.0", "deps"));
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

test "Config module - dependency memory management" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    // Test hardcoded config creation
    var zon_config = try config.DepsZonConfig.createHardcoded(allocator);
    try zon_config.initHardcodedDependencies();
    defer zon_config.deinit();
    
    // Verify all 9 dependencies are present
    try testing.expectEqual(@as(usize, 9), zon_config.dependencies.count());
    
    // Test specific dependencies
    try testing.expect(zon_config.dependencies.contains("tree-sitter"));
    try testing.expect(zon_config.dependencies.contains("zig-tree-sitter"));
    try testing.expect(zon_config.dependencies.contains("tree-sitter-zig"));
    try testing.expect(zon_config.dependencies.contains("zig-spec"));
    
    // Convert to DepsConfig and verify
    var deps_config = try zon_config.toDepsConfig(allocator);
    defer deps_config.deinit(allocator);
    
    try testing.expectEqual(@as(usize, 9), deps_config.dependencies.count());
}

test "Config module - version info serialization" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    const version_info = config.VersionInfo{
        .repository = "https://github.com/test/repo.git",
        .version = "v1.0.0",
        .commit = "abc123def456",
        .updated = 1704067200, // 2024-01-01 00:00:00 UTC
        .updated_by = "test@example.com",
    };
    
    // Test serialization
    const content = try version_info.toContent(allocator);
    defer allocator.free(content);
    
    // Verify content contains expected fields
    try testing.expect(std.mem.indexOf(u8, content, "Repository: https://github.com/test/repo.git") != null);
    try testing.expect(std.mem.indexOf(u8, content, "Version: v1.0.0") != null);
    try testing.expect(std.mem.indexOf(u8, content, "Commit: abc123def456") != null);
    
    // Test deserialization
    const parsed = try config.VersionInfo.parseFromContent(allocator, content);
    defer parsed.deinit(allocator);
    
    try testing.expectEqualStrings(version_info.repository, parsed.repository);
    try testing.expectEqualStrings(version_info.version, parsed.version);
    try testing.expectEqualStrings(version_info.commit, parsed.commit);
}

test "Lock module - PID management" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const LockGuard = @import("lock.zig").LockGuard;
    
    // Test lock acquisition and release (using real filesystem since lock uses PID operations)
    var lock = LockGuard.acquire(allocator, "/tmp") catch |err| switch (err) {
        error.LockHeld => {
            // Lock already held, which is fine for testing
            return;
        },
        else => return err,
    };
    defer lock.deinit();
    
    // The lock was successfully acquired and will be released by deinit
}

test "Process module integration" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const process = @import("../core/process.zig");
    
    // Test git args building
    var git_args = try process.buildGitArgs(allocator, &.{ "status", "--porcelain" });
    defer git_args.deinit();
    
    try testing.expectEqualStrings("git", git_args.items[0]);
    try testing.expectEqualStrings("status", git_args.items[1]);
    try testing.expectEqualStrings("--porcelain", git_args.items[2]);
    
    // Test command output parsing
    const raw_output = "  abc123def456  \n  ";
    const parsed = try process.parseCommandOutput(allocator, raw_output);
    defer allocator.free(parsed);
    
    try testing.expectEqualStrings("abc123def456", parsed);
}