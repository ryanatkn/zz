const std = @import("std");
const testing = std.testing;
const test_helpers = @import("../../test_helpers.zig");
const PatternMatcher = @import("../matcher.zig").PatternMatcher;

// Initialize Patterns module testing
test "Patterns module initialization" {
    test_helpers.TestRunner.setModule("Patterns");
}

test "PatternMatcher.matchesPattern unified behavior" {
    // Test exact component matches
    try testing.expect(PatternMatcher.matchesPattern("node_modules", "node_modules"));
    try testing.expect(PatternMatcher.matchesPattern("path/node_modules", "node_modules"));
    try testing.expect(PatternMatcher.matchesPattern("node_modules/package", "node_modules"));
    try testing.expect(PatternMatcher.matchesPattern("a/node_modules/b", "node_modules"));

    // Test non-matches (leaky patterns)
    try testing.expect(!PatternMatcher.matchesPattern("my_node_modules", "node_modules"));
    try testing.expect(!PatternMatcher.matchesPattern("node_modules_backup", "node_modules"));
    try testing.expect(!PatternMatcher.matchesPattern("path/my_node_modules", "node_modules"));
    try testing.expect(!PatternMatcher.matchesPattern("path/node_modules_backup", "node_modules"));

    // Test empty and edge cases
    try testing.expect(!PatternMatcher.matchesPattern("", "test"));
    try testing.expect(!PatternMatcher.matchesPattern("test", ""));
    try testing.expect(PatternMatcher.matchesPattern("test", "test"));
}

test "PatternMatcher.hasGlobChars detection" {
    try testing.expect(PatternMatcher.hasGlobChars("*.zig"));
    try testing.expect(PatternMatcher.hasGlobChars("test?.txt"));
    try testing.expect(PatternMatcher.hasGlobChars("a*b?c"));
    try testing.expect(!PatternMatcher.hasGlobChars("normal.txt"));
    try testing.expect(!PatternMatcher.hasGlobChars("node_modules"));
}

test "PatternMatcher.matchSimplePattern glob functionality" {
    try testing.expect(PatternMatcher.matchSimplePattern("test.zig", "*.zig"));
    try testing.expect(PatternMatcher.matchSimplePattern("anything", "*"));
    try testing.expect(!PatternMatcher.matchSimplePattern("test.md", "*.zig"));
    try testing.expect(PatternMatcher.matchSimplePattern("exact", "exact"));
}

// Patterns module test summary
test "Patterns module test summary" {
    test_helpers.TestRunner.printSummary();
}
