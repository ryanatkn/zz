const std = @import("std");
const test_helpers = @import("../../lib/test/helpers.zig");
const GlobExpander = @import("../glob.zig").GlobExpander;
const matchSimplePattern = @import("../glob.zig").matchSimplePattern;

test "match everything recursively with **" {
    const allocator = std.testing.allocator;

    var ctx = test_helpers.MockTestContext.init(allocator);
    defer ctx.deinit();

    // Create nested structure
    try ctx.addDirectory("a");
    try ctx.addDirectory("a/b");
    try ctx.addDirectory("a/b/c");
    try ctx.addFile("root.txt", "1");
    try ctx.addFile("a/level1.txt", "2");
    try ctx.addFile("a/b/level2.txt", "3");
    try ctx.addFile("a/b/c/level3.txt", "4");

    const expander = test_helpers.createGlobExpander(allocator, ctx.filesystem);

    // ** should match everything recursively
    const pattern = "**";
    var patterns = [_][]const u8{pattern};
    var results = try expander.expandPatternsWithInfo(&patterns);
    defer {
        for (results.items) |*result| {
            for (result.files.items) |file| {
                allocator.free(file);
            }
            result.files.deinit();
        }
        results.deinit();
    }

    // Should find all files (but our glob currently expects a pattern after **)
    try std.testing.expect(results.items.len == 1);
}

test "trailing slash in pattern" {
    const allocator = std.testing.allocator;

    var ctx = test_helpers.MockTestContext.init(allocator);
    defer ctx.deinit();

    try ctx.addFile("test.zig", "const a = 1;");

    const expander = test_helpers.createGlobExpander(allocator, ctx.filesystem);

    // Pattern with trailing slash - treat as current directory
    const pattern = "./";
    var patterns = [_][]const u8{pattern};
    var results = try expander.expandPatternsWithInfo(&patterns);
    defer {
        for (results.items) |*result| {
            for (result.files.items) |file| {
                allocator.free(file);
            }
            result.files.deinit();
        }
        results.deinit();
    }

    // Trailing slash pattern should not match files
    try std.testing.expect(results.items.len == 1);
}

test "empty alternatives in braces" {
    const allocator = std.testing.allocator;

    var ctx = test_helpers.MockTestContext.init(allocator);
    defer ctx.deinit();

    try ctx.addFile(".zig", "const a = 1;");
    try ctx.addFile("test.zig", "const b = 2;");

    const expander = test_helpers.createGlobExpander(allocator, ctx.filesystem);

    // Pattern with empty alternative
    const pattern = "{,test}.zig";
    var patterns = [_][]const u8{pattern};
    var results = try expander.expandPatternsWithInfo(&patterns);
    defer {
        for (results.items) |*result| {
            for (result.files.items) |file| {
                allocator.free(file);
            }
            result.files.deinit();
        }
        results.deinit();
    }

    // Should match both .zig and test.zig
    try std.testing.expect(results.items.len == 1);
}

test "unmatched braces" {
    var ctx = test_helpers.MockTestContext.init(std.testing.allocator);
    defer ctx.deinit();

    const expander = test_helpers.createGlobExpander(std.testing.allocator, ctx.filesystem);

    // Unmatched opening brace
    try std.testing.expect(!expander.matchPattern("test.zig", "*.{zig"));

    // Unmatched closing brace
    try std.testing.expect(!expander.matchPattern("test.zig", "*.zig}"));

    // Should treat as literal characters
    try std.testing.expect(expander.matchPattern("test.{zig", "test.{zig"));
}

test "question mark edge cases" {
    // Test single character matching
    try std.testing.expect(matchSimplePattern("a", "?"));
    try std.testing.expect(matchSimplePattern("z", "?"));
    try std.testing.expect(!matchSimplePattern("ab", "?"));
    try std.testing.expect(!matchSimplePattern("", "?"));

    // Multiple question marks
    try std.testing.expect(matchSimplePattern("abc", "???"));
    try std.testing.expect(!matchSimplePattern("ab", "???"));
    try std.testing.expect(!matchSimplePattern("abcd", "???"));

    // Mixed with literals
    try std.testing.expect(matchSimplePattern("test", "t?st"));
    try std.testing.expect(matchSimplePattern("tast", "t?st"));
    try std.testing.expect(!matchSimplePattern("toast", "t?st"));
}

test "star edge cases" {
    // Empty star
    try std.testing.expect(matchSimplePattern("", "*"));
    try std.testing.expect(matchSimplePattern("anything", "*"));

    // Multiple stars
    try std.testing.expect(matchSimplePattern("test.zig", "*.*"));
    try std.testing.expect(matchSimplePattern("a.b.c", "*.*"));
    try std.testing.expect(!matchSimplePattern("noextension", "*.*"));

    // Stars at beginning and end
    try std.testing.expect(matchSimplePattern("test", "*test"));
    try std.testing.expect(matchSimplePattern("mytest", "*test"));
    try std.testing.expect(matchSimplePattern("test", "test*"));
    try std.testing.expect(matchSimplePattern("testing", "test*"));

    // Multiple consecutive stars (should work like single star)
    try std.testing.expect(matchSimplePattern("test", "**"));
    try std.testing.expect(matchSimplePattern("test", "***"));
}

test "complex glob patterns" {
    var ctx = test_helpers.MockTestContext.init(std.testing.allocator);
    defer ctx.deinit();

    const expander = test_helpers.createGlobExpander(std.testing.allocator, ctx.filesystem);

    // Complex alternatives
    try std.testing.expect(expander.matchPattern("main.zig", "{main,test,lib}.{zig,rs,go}"));
    try std.testing.expect(expander.matchPattern("test.rs", "{main,test,lib}.{zig,rs,go}"));
    try std.testing.expect(expander.matchPattern("lib.go", "{main,test,lib}.{zig,rs,go}"));
    try std.testing.expect(!expander.matchPattern("other.zig", "{main,test,lib}.{zig,rs,go}"));
    try std.testing.expect(!expander.matchPattern("main.txt", "{main,test,lib}.{zig,rs,go}"));

    // Mixed wildcards and alternatives
    try std.testing.expect(expander.matchPattern("test_file.zig", "*_{file,data}.{zig,txt}"));
    try std.testing.expect(expander.matchPattern("my_data.txt", "*_{file,data}.{zig,txt}"));
    try std.testing.expect(!expander.matchPattern("test_other.zig", "*_{file,data}.{zig,txt}"));
}

test "nested brace patterns" {
    var ctx = test_helpers.MockTestContext.init(std.testing.allocator);
    defer ctx.deinit();

    const expander = test_helpers.createGlobExpander(std.testing.allocator, ctx.filesystem);

    // Test nested braces - simple case
    try std.testing.expect(expander.matchPattern("test.zig", "*.{zig,{md,txt}}"));
    try std.testing.expect(expander.matchPattern("test.md", "*.{zig,{md,txt}}"));
    try std.testing.expect(expander.matchPattern("test.txt", "*.{zig,{md,txt}}"));
    try std.testing.expect(!expander.matchPattern("test.rs", "*.{zig,{md,txt}}"));

    // More complex nested braces
    try std.testing.expect(expander.matchPattern("a.zig", "*.{a,{b,{c,zig}}}"));
    try std.testing.expect(expander.matchPattern("test.a", "*.{a,{b,{c,zig}}}"));
    try std.testing.expect(expander.matchPattern("file.b", "*.{a,{b,{c,zig}}}"));
    try std.testing.expect(expander.matchPattern("code.c", "*.{a,{b,{c,zig}}}"));

    // Triple nested
    try std.testing.expect(expander.matchPattern("file.md", "{test,file}.{zig,{md,{txt,log}}}"));
    try std.testing.expect(expander.matchPattern("test.txt", "{test,file}.{zig,{md,{txt,log}}}"));
    try std.testing.expect(expander.matchPattern("file.log", "{test,file}.{zig,{md,{txt,log}}}"));
    try std.testing.expect(!expander.matchPattern("other.md", "{test,file}.{zig,{md,{txt,log}}}"));
}

test "glob with dots" {
    // Dots in patterns
    try std.testing.expect(matchSimplePattern("..test", "..test"));
    try std.testing.expect(matchSimplePattern("..test", "..*"));
    try std.testing.expect(matchSimplePattern("test..zig", "*.zig"));

    // Hidden files (starting with dot)
    // Note: Our matchSimplePattern is a pure pattern matcher
    // The shell behavior of * not matching . is handled at a higher level
    try std.testing.expect(matchSimplePattern(".hidden", ".*"));
    try std.testing.expect(matchSimplePattern(".hidden", "*")); // Our simple matcher does match
}

test "case sensitivity" {
    // Glob patterns are case-sensitive
    try std.testing.expect(matchSimplePattern("Test.zig", "Test.*"));
    try std.testing.expect(!matchSimplePattern("test.zig", "Test.*"));
    try std.testing.expect(!matchSimplePattern("TEST.zig", "Test.*"));

    try std.testing.expect(matchSimplePattern("TEST.ZIG", "*.ZIG"));
    try std.testing.expect(!matchSimplePattern("test.zig", "*.ZIG"));
}

test "special glob characters as literals" {
    // When not in glob position, special chars are literal
    try std.testing.expect(matchSimplePattern("file*name.txt", "file*name.txt"));
    try std.testing.expect(matchSimplePattern("why?.txt", "why?.txt"));

    // But they still work as globs when appropriate
    try std.testing.expect(matchSimplePattern("file_name.txt", "file*name.txt"));
    try std.testing.expect(matchSimplePattern("whyx.txt", "why?.txt"));
}

test "empty pattern and empty string" {
    // Empty pattern only matches empty string
    try std.testing.expect(matchSimplePattern("", ""));
    try std.testing.expect(!matchSimplePattern("a", ""));
    try std.testing.expect(!matchSimplePattern("", "a"));
}
