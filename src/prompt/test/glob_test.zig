const std = @import("std");
const testing = std.testing;
const test_helpers = @import("../../test_helpers.zig");
const GlobExpander = @import("../glob.zig").GlobExpander;
const matchSimplePattern = @import("../glob.zig").matchSimplePattern;

test "glob pattern matching" {
    try testing.expect(matchSimplePattern("test.zig", "*.zig"));
    try testing.expect(matchSimplePattern("main.zig", "*.zig"));
    try testing.expect(!matchSimplePattern("test.txt", "*.zig"));

    try testing.expect(matchSimplePattern("test.zig", "test.*"));
    try testing.expect(matchSimplePattern("a.txt", "?.txt"));
    try testing.expect(!matchSimplePattern("ab.txt", "?.txt"));
}

test "glob alternatives" {
    // Brace expansion requires filesystem context for the expander
    var ctx = test_helpers.MockTestContext.init(testing.allocator);
    defer ctx.deinit();

    const expander = test_helpers.createGlobExpander(testing.allocator, ctx.filesystem);

    try testing.expect(expander.matchPattern("test.zig", "*.{zig,txt}"));
    try testing.expect(expander.matchPattern("test.txt", "*.{zig,txt}"));
    try testing.expect(!expander.matchPattern("test.md", "*.{zig,txt}"));

    // Test nested braces
    try testing.expect(expander.matchPattern("test.zig", "*.{zig,{md,txt}}"));
    try testing.expect(expander.matchPattern("test.md", "*.{zig,{md,txt}}"));
    try testing.expect(expander.matchPattern("test.txt", "*.{zig,{md,txt}}"));
    try testing.expect(!expander.matchPattern("test.rs", "*.{zig,{md,txt}}"));
}

test "character classes" {
    // Single characters
    try testing.expect(matchSimplePattern("a", "[abc]"));
    try testing.expect(matchSimplePattern("b", "[abc]"));
    try testing.expect(matchSimplePattern("c", "[abc]"));
    try testing.expect(!matchSimplePattern("d", "[abc]"));

    // Ranges
    try testing.expect(matchSimplePattern("a", "[a-z]"));
    try testing.expect(matchSimplePattern("m", "[a-z]"));
    try testing.expect(matchSimplePattern("z", "[a-z]"));
    try testing.expect(!matchSimplePattern("A", "[a-z]"));
    try testing.expect(!matchSimplePattern("0", "[a-z]"));

    // Multiple ranges
    try testing.expect(matchSimplePattern("a", "[a-zA-Z]"));
    try testing.expect(matchSimplePattern("Z", "[a-zA-Z]"));
    try testing.expect(matchSimplePattern("m", "[a-zA-Z]"));
    try testing.expect(!matchSimplePattern("0", "[a-zA-Z]"));

    // Negation with !
    try testing.expect(!matchSimplePattern("a", "[!abc]"));
    try testing.expect(matchSimplePattern("d", "[!abc]"));
    try testing.expect(matchSimplePattern("z", "[!abc]"));

    // Negation with ^
    try testing.expect(!matchSimplePattern("a", "[^abc]"));
    try testing.expect(matchSimplePattern("d", "[^abc]"));

    // In patterns
    try testing.expect(matchSimplePattern("log1.txt", "log[0-9].txt"));
    try testing.expect(matchSimplePattern("log5.txt", "log[0-9].txt"));
    try testing.expect(!matchSimplePattern("loga.txt", "log[0-9].txt"));
    try testing.expect(!matchSimplePattern("log10.txt", "log[0-9].txt"));

    // Combined with wildcards
    try testing.expect(matchSimplePattern("test1.zig", "test[0-9]*.zig"));
    try testing.expect(matchSimplePattern("test123.zig", "test[0-9]*.zig"));
    try testing.expect(!matchSimplePattern("testa.zig", "test[0-9]*.zig"));
}

test "escape sequences" {
    // Escape special characters
    try testing.expect(matchSimplePattern("*.txt", "\\*.txt"));
    try testing.expect(!matchSimplePattern("a.txt", "\\*.txt"));

    try testing.expect(matchSimplePattern("?.txt", "\\?.txt"));
    try testing.expect(!matchSimplePattern("a.txt", "\\?.txt"));

    try testing.expect(matchSimplePattern("[abc].txt", "\\[abc\\].txt"));
    try testing.expect(!matchSimplePattern("a.txt", "\\[abc\\].txt"));

    // Escape backslash itself
    try testing.expect(matchSimplePattern("\\test", "\\\\test"));
    try testing.expect(matchSimplePattern("file\\name", "file\\\\name"));

    // Mixed escapes and wildcards
    try testing.expect(matchSimplePattern("file*.txt", "file\\*.txt"));
    try testing.expect(matchSimplePattern("test[1].log", "test\\[1\\].log"));
    try testing.expect(matchSimplePattern("a*b", "a\\*b"));

    // Wildcards still work when not escaped
    try testing.expect(matchSimplePattern("file123.txt", "file*.txt"));
    try testing.expect(matchSimplePattern("file*.txt", "file*.txt")); // Pattern matches itself
}

test "glob pattern expansion" {
    // Mixed test - simple patterns can be pure, but braces need expander
    var ctx = test_helpers.MockTestContext.init(testing.allocator);
    defer ctx.deinit();

    const expander = test_helpers.createGlobExpander(testing.allocator, ctx.filesystem);

    // Test simple wildcard matching (could be pure but keeping consistent)
    try testing.expect(expander.matchPattern("test.zig", "*.zig"));
    try testing.expect(expander.matchPattern("main.zig", "*.zig"));
    try testing.expect(!expander.matchPattern("test.txt", "*.zig"));

    // Test alternatives (needs brace expansion)
    try testing.expect(expander.matchPattern("test.zig", "*.{zig,txt}"));
    try testing.expect(expander.matchPattern("test.txt", "*.{zig,txt}"));
    try testing.expect(!expander.matchPattern("test.md", "*.{zig,txt}"));

    // Test question mark (could be pure but keeping consistent)
    try testing.expect(expander.matchPattern("a.txt", "?.txt"));
    try testing.expect(!expander.matchPattern("ab.txt", "?.txt"));
}

test "glob pattern detection" {
    // Test glob patterns
    try testing.expect(GlobExpander.isGlobPattern("*.zig") == true);
    try testing.expect(GlobExpander.isGlobPattern("src/**/*.zig") == true);
    try testing.expect(GlobExpander.isGlobPattern("test?.zig") == true);
    try testing.expect(GlobExpander.isGlobPattern("*.{zig,txt}") == true);

    // Test non-glob patterns
    try testing.expect(GlobExpander.isGlobPattern("file.zig") == false);
    try testing.expect(GlobExpander.isGlobPattern("src/main.zig") == false);
    try testing.expect(GlobExpander.isGlobPattern("/absolute/path.txt") == false);
}

test "error on non-matching glob patterns" {
    // Use MockTestContext for controlled filesystem state (empty directory)
    var ctx = test_helpers.MockTestContext.init(testing.allocator);
    defer ctx.deinit();

    const expander = test_helpers.createGlobExpander(testing.allocator, ctx.filesystem);

    // Test that glob pattern with no matches returns empty
    var patterns = [_][]const u8{"*.nonexistent_extension_xyz"};
    var results = try expander.expandPatternsWithInfo(&patterns);
    defer {
        for (results.items) |*result| {
            for (result.files.items) |path| {
                testing.allocator.free(path);
            }
            result.files.deinit();
        }
        results.deinit();
    }

    try testing.expect(results.items.len == 1);
    try testing.expect(results.items[0].files.items.len == 0);
    try testing.expect(results.items[0].is_glob == true);
}

test "error on explicit missing files" {
    // Use MockTestContext for controlled filesystem state (test missing files)
    var ctx = test_helpers.MockTestContext.init(testing.allocator);
    defer ctx.deinit();

    const expander = test_helpers.createGlobExpander(testing.allocator, ctx.filesystem);

    // Test that explicit file path with no file returns empty
    var patterns = [_][]const u8{"/nonexistent/path/to/file.zig"};
    var results = try expander.expandPatternsWithInfo(&patterns);
    defer {
        for (results.items) |*result| {
            for (result.files.items) |path| {
                testing.allocator.free(path);
            }
            result.files.deinit();
        }
        results.deinit();
    }

    try testing.expect(results.items.len == 1);
    try testing.expect(results.items[0].files.items.len == 0);
    try testing.expect(results.items[0].is_glob == false);
}
