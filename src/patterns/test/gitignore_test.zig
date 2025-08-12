const std = @import("std");
const testing = std.testing;
const GitignorePatterns = @import("../gitignore.zig").GitignorePatterns;

test "GitignorePatterns.parseContent basic parsing" {
    const allocator = testing.allocator;

    const content =
        \\# This is a comment
        \\node_modules
        \\*.log
        \\
        \\temp/
        \\!important.log
    ;

    const patterns = try GitignorePatterns.parseContent(allocator, content);
    defer {
        for (patterns) |pattern| {
            allocator.free(pattern);
        }
        allocator.free(patterns);
    }

    try testing.expect(patterns.len == 4);
    try testing.expectEqualStrings("node_modules", patterns[0]);
    try testing.expectEqualStrings("*.log", patterns[1]);
    try testing.expectEqualStrings("temp/", patterns[2]);
    try testing.expectEqualStrings("!important.log", patterns[3]);
}

test "GitignorePatterns.shouldIgnore pattern logic" {
    const patterns = [_][]const u8{ "node_modules", "*.log", "!important.log" };

    try testing.expect(GitignorePatterns.shouldIgnore(&patterns, "node_modules"));
    try testing.expect(GitignorePatterns.shouldIgnore(&patterns, "path/to/node_modules"));
    try testing.expect(GitignorePatterns.shouldIgnore(&patterns, "test.log"));
    try testing.expect(!GitignorePatterns.shouldIgnore(&patterns, "important.log")); // Negated
    try testing.expect(!GitignorePatterns.shouldIgnore(&patterns, "test.txt"));
}

test "GitignorePatterns.matchesPattern unified matching" {
    // Directory patterns
    try testing.expect(GitignorePatterns.matchesPattern("temp", "temp/"));

    // Absolute patterns
    try testing.expect(GitignorePatterns.matchesPattern("build/output", "/build"));
    try testing.expect(!GitignorePatterns.matchesPattern("src/build", "/build"));

    // Relative patterns
    try testing.expect(GitignorePatterns.matchesPattern("any/path/node_modules", "node_modules"));
    try testing.expect(GitignorePatterns.matchesPattern("test.log", "*.log"));
}