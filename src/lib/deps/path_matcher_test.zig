// Tests for path matching functionality
const std = @import("std");
const PathMatcher = @import("path_matcher.zig").PathMatcher;
const config = @import("config.zig");

test "PathMatcher .git exclusion - always excluded" {
    const testing = std.testing;
    
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