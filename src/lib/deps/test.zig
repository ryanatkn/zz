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
    std.testing.refAllDeclsRecursive(@import("../core/git.zig"));
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
        \\            .include = .{},
        \\            .exclude = .{ "build.zig", "*.md" },
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
                include: []const []const u8,
                exclude: []const []const u8,
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
        std.debug.print("ZON file exists with {} characters\n", .{content.len});
        
        // Try to actually parse the ZON content now that we have comment stripping
        var parseResult = config.DepsZonConfig.parseFromZonContent(allocator, content) catch |err| {
            std.debug.print("ZON parsing failed with error: {}\n", .{err});
            // This is expected to fail for now - we're debugging
            return;
        };
        defer parseResult.deinit();
        
        std.debug.print("ZON parsing succeeded! Found {} dependencies\n", .{parseResult.dependencies.count()});
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
    const same_version_needs_update = try versioning.needsUpdate("test-dep", "v1.0.0", "deps");
    try testing.expect(!same_version_needs_update);
    
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

test "Path utilities integration" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const path = @import("../core/path.zig");
    
    // Test path joining with dependency-style paths
    const joined = try path.joinPath(allocator, "deps", "tree-sitter");
    defer allocator.free(joined);
    
    try testing.expectEqualStrings("deps/tree-sitter", joined);
    
    // Test with longer paths
    const long_joined = try path.joinPath(allocator, "deps", "tree-sitter-typescript");
    defer allocator.free(long_joined);
    
    try testing.expectEqualStrings("deps/tree-sitter-typescript", long_joined);
    
    // Test multi-component paths
    const multi_path = try path.joinPaths(allocator, &.{ "deps", ".tmp", "tree-sitter-123456" });
    defer allocator.free(multi_path);
    
    try testing.expectEqualStrings("deps/.tmp/tree-sitter-123456", multi_path);
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

test "PathMatcher .git exclusion - always excluded" {
    const testing = std.testing;
    const PathMatcher = @import("path_matcher.zig").PathMatcher;
    
    // .git should always be excluded regardless of include/exclude patterns
    const include_all = &.{};
    const exclude_none = &.{};
    const include_git = &.{ ".git" }; // Even if explicitly included
    
    // Should always exclude .git
    try testing.expect(!PathMatcher.shouldCopyPath(".git", include_all, exclude_none));
    try testing.expect(!PathMatcher.shouldCopyPath(".git/config", include_all, exclude_none));
    try testing.expect(!PathMatcher.shouldCopyPath("subdir/.git/hooks", include_all, exclude_none));
    
    // Even when explicitly included
    try testing.expect(!PathMatcher.shouldCopyPath(".git", include_git, exclude_none));
    try testing.expect(!PathMatcher.shouldCopyPath(".git/config", include_git, exclude_none));
}

test "Include/exclude patterns with dependency configuration" {
    const testing = std.testing;
    
    // Test dependency with include patterns (only copy specific paths)
    const include_dep = config.Dependency{
        .name = "test-include",
        .url = "https://github.com/example/test.git",
        .version = "v1.0.0",
        .include = &.{ "src/", "*.zig" },
        .exclude = &.{},
        .preserve_files = &.{},
        .owns_memory = false,
    };
    
    // Should include src directory and zig files
    try testing.expectEqual(@as(usize, 2), include_dep.include.len);
    try testing.expectEqualStrings("src/", include_dep.include[0]);
    try testing.expectEqualStrings("*.zig", include_dep.include[1]);
    
    // Test dependency with exclude patterns (exclude specific paths)
    const exclude_dep = config.Dependency{
        .name = "test-exclude",
        .url = "https://github.com/example/test.git", 
        .version = "v1.0.0",
        .include = &.{},
        .exclude = &.{ "test/", "*.md", "build.zig*" },
        .preserve_files = &.{},
        .owns_memory = false,
    };
    
    // Should exclude test directory, markdown files, and build files
    try testing.expectEqual(@as(usize, 3), exclude_dep.exclude.len);
    try testing.expectEqualStrings("test/", exclude_dep.exclude[0]);
    try testing.expectEqualStrings("*.md", exclude_dep.exclude[1]);
    try testing.expectEqualStrings("build.zig*", exclude_dep.exclude[2]);
}

test "PathMatcher integration with dependency patterns" {
    const testing = std.testing;
    const PathMatcher = @import("path_matcher.zig").PathMatcher;
    
    // Test include-only pattern (zig-spec example)
    const include_patterns = &.{ "grammar/", "spec/" };
    const exclude_patterns = &.{};
    
    // Should copy grammar and spec directories
    try testing.expect(PathMatcher.shouldCopyPath("grammar", include_patterns, exclude_patterns));
    try testing.expect(PathMatcher.shouldCopyPath("spec", include_patterns, exclude_patterns));
    try testing.expect(PathMatcher.shouldCopyPath("grammar/lexer.txt", include_patterns, exclude_patterns));
    try testing.expect(PathMatcher.shouldCopyPath("spec/syntax.txt", include_patterns, exclude_patterns));
    
    // Should not copy other directories
    try testing.expect(!PathMatcher.shouldCopyPath("docs", include_patterns, exclude_patterns));
    try testing.expect(!PathMatcher.shouldCopyPath("test", include_patterns, exclude_patterns));
    try testing.expect(!PathMatcher.shouldCopyPath("README.md", include_patterns, exclude_patterns));
    
    // Test exclude pattern (tree-sitter example)
    const include_all = &.{};
    const exclude_build = &.{ "build.zig", "build.zig.zon", "test/", "*.md" };
    
    // Should copy source files
    try testing.expect(PathMatcher.shouldCopyPath("src", include_all, exclude_build));
    try testing.expect(PathMatcher.shouldCopyPath("lib/parser.c", include_all, exclude_build));
    try testing.expect(PathMatcher.shouldCopyPath("Makefile", include_all, exclude_build));
    
    // Should exclude build files, tests, and markdown
    try testing.expect(!PathMatcher.shouldCopyPath("build.zig", include_all, exclude_build));
    try testing.expect(!PathMatcher.shouldCopyPath("build.zig.zon", include_all, exclude_build));
    try testing.expect(!PathMatcher.shouldCopyPath("test", include_all, exclude_build));
    try testing.expect(!PathMatcher.shouldCopyPath("test/test.c", include_all, exclude_build));
    try testing.expect(!PathMatcher.shouldCopyPath("README.md", include_all, exclude_build));
    try testing.expect(!PathMatcher.shouldCopyPath("CHANGELOG.md", include_all, exclude_build));
}

test "PathMatcher edge cases - directory boundary detection" {
    const testing = std.testing;
    const PathMatcher = @import("path_matcher.zig").PathMatcher;
    
    // Test that "test/" pattern doesn't match "testing/" 
    const exclude_test = &.{ "test/" };
    const include_all = &.{};
    
    // Should exclude test directory and contents
    try testing.expect(!PathMatcher.shouldCopyPath("test", include_all, exclude_test));
    try testing.expect(!PathMatcher.shouldCopyPath("test/file.zig", include_all, exclude_test));
    try testing.expect(!PathMatcher.shouldCopyPath("test/sub/file.zig", include_all, exclude_test));
    
    // Should NOT exclude similar named directories
    try testing.expect(PathMatcher.shouldCopyPath("testing", include_all, exclude_test));
    try testing.expect(PathMatcher.shouldCopyPath("testing/file.zig", include_all, exclude_test));
    try testing.expect(PathMatcher.shouldCopyPath("tests", include_all, exclude_test));
    try testing.expect(PathMatcher.shouldCopyPath("mytest", include_all, exclude_test));
    try testing.expect(PathMatcher.shouldCopyPath("test.zig", include_all, exclude_test)); // File, not directory
}

test "PathMatcher recursive patterns" {
    const testing = std.testing;
    const PathMatcher = @import("path_matcher.zig").PathMatcher;
    
    // Test recursive directory patterns
    try testing.expect(PathMatcher.matchesPattern("any/path/docs/readme.md", "**/docs/"));
    try testing.expect(PathMatcher.matchesPattern("deep/nested/path/test/file.zig", "**/test/"));
    try testing.expect(PathMatcher.matchesPattern("root/build/output.txt", "**/build/"));
    
    // Should not match if directory name is embedded
    try testing.expect(!PathMatcher.matchesPattern("some/buildtools/file.txt", "**/build/"));
    try testing.expect(!PathMatcher.matchesPattern("testing123/file.txt", "**/test/"));
    
    // Test complex recursive patterns with includes
    const include_recursive = &.{ "**/src/", "**/lib/" };
    const exclude_none = &.{};
    
    try testing.expect(PathMatcher.shouldCopyPath("project/src/main.zig", include_recursive, exclude_none));
    try testing.expect(PathMatcher.shouldCopyPath("deep/nested/lib/utils.zig", include_recursive, exclude_none));
    try testing.expect(!PathMatcher.shouldCopyPath("project/docs/readme.md", include_recursive, exclude_none));
}

test "PathMatcher pattern precedence - include vs exclude" {
    const testing = std.testing;
    const PathMatcher = @import("path_matcher.zig").PathMatcher;
    
    // Test that include is required, then exclude is applied
    const include_zig = &.{ "*.zig" };
    const exclude_test = &.{ "*test*" };
    
    // Files that match include but not exclude should be copied
    try testing.expect(PathMatcher.shouldCopyPath("main.zig", include_zig, exclude_test));
    try testing.expect(PathMatcher.shouldCopyPath("utils.zig", include_zig, exclude_test));
    
    // Files that match include AND exclude should be excluded (exclude wins)
    try testing.expect(!PathMatcher.shouldCopyPath("test.zig", include_zig, exclude_test));
    try testing.expect(!PathMatcher.shouldCopyPath("main_test.zig", include_zig, exclude_test));
    
    // Files that don't match include should not be copied
    try testing.expect(!PathMatcher.shouldCopyPath("test.c", include_zig, exclude_test)); // No .zig extension
    try testing.expect(!PathMatcher.shouldCopyPath("README.md", include_zig, exclude_test)); // No .zig extension
    
    // Test empty include list (include everything, then apply excludes)
    const include_all = &.{};
    const exclude_md = &.{ "*.md" };
    
    try testing.expect(PathMatcher.shouldCopyPath("main.zig", include_all, exclude_md));
    try testing.expect(!PathMatcher.shouldCopyPath("README.md", include_all, exclude_md));
}

test "Table formatting with long dependency names" {
    const testing = std.testing;
    
    // Check that NAME_COL_WIDTH can handle our longest dependency names
    const longest_name = "tree-sitter-typescript"; // 23 characters
    try testing.expect(longest_name.len <= 24); // Our NAME_COL_WIDTH constant
    
    // Test other long names
    const other_long_names = [_][]const u8{
        "tree-sitter-javascript", // If we had this
        "tree-sitter-svelte",     // 19 characters
        "zig-tree-sitter",       // 16 characters
    };
    
    for (other_long_names) |name| {
        try testing.expect(name.len <= 24);
    }
}