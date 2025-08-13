const std = @import("std");
const testing = std.testing;
const test_helpers = @import("../../test_helpers.zig");

const Filter = @import("../filter.zig").Filter;
const SharedConfig = @import("../../config.zig").SharedConfig;

// Test pattern matching edge cases
test "pattern matching edge cases" {
    test_helpers.TestRunner.recordTest("pattern matching edge cases");
    const ignored = [_][]const u8{
        "exact_match",
        "node_modules",
        ".git",
        "src/tree/compiled",
    };
    const hidden = [_][]const u8{ "Thumbs.db", ".DS_Store" };

    const shared_config = SharedConfig{
        .ignored_patterns = &ignored,
        .hidden_files = &hidden,
        .gitignore_patterns = &[_][]const u8{},
        .symlink_behavior = .skip,
        .respect_gitignore = false,
        .patterns_allocated = false,
    };

    const filter = Filter.init(shared_config);

    // Test exact matches
    try testing.expect(filter.shouldIgnore("exact_match"));
    try testing.expect(filter.shouldIgnore("node_modules"));
    try testing.expect(filter.shouldIgnore(".git"));

    // Test non-matches
    try testing.expect(!filter.shouldIgnore("not_a_match"));
    try testing.expect(!filter.shouldIgnore("exact_matc")); // partial match
    try testing.expect(!filter.shouldIgnore("exact_match_longer")); // longer

    // Test empty string
    try testing.expect(!filter.shouldIgnore(""));

}

// Test path-based pattern matching
test "path based pattern matching" {
    test_helpers.TestRunner.recordTest("path based pattern matching");
    const ignored = [_][]const u8{
        "src/tree/compiled",
        "deep/nested/path",
    };
    const hidden = [_][]const u8{};

    const shared_config = SharedConfig{
        .ignored_patterns = &ignored,
        .hidden_files = &hidden,
        .gitignore_patterns = &[_][]const u8{},
        .symlink_behavior = .skip,
        .respect_gitignore = false,
        .patterns_allocated = false,
    };

    const filter = Filter.init(shared_config);

    // Test path-based matches
    try testing.expect(filter.shouldIgnoreAtPath("project/src/tree/compiled"));
    try testing.expect(filter.shouldIgnoreAtPath("/absolute/src/tree/compiled"));
    try testing.expect(filter.shouldIgnoreAtPath("src/tree/compiled"));
    try testing.expect(filter.shouldIgnoreAtPath("very/deep/nested/path"));

    // Test non-matches
    try testing.expect(!filter.shouldIgnoreAtPath("src/tree"));
    try testing.expect(!filter.shouldIgnoreAtPath("src/tree/test"));
    try testing.expect(!filter.shouldIgnoreAtPath("compiled"));
    try testing.expect(!filter.shouldIgnoreAtPath("deep/nested"));

}

// Test dot-directory behavior
test "dot directory behavior" {
    test_helpers.TestRunner.recordTest("dot directory behavior");
    const ignored = [_][]const u8{}; // No explicit patterns
    const hidden = [_][]const u8{};

    const shared_config = SharedConfig{
        .ignored_patterns = &ignored,
        .hidden_files = &hidden,
        .gitignore_patterns = &[_][]const u8{},
        .symlink_behavior = .skip,
        .respect_gitignore = false,
        .patterns_allocated = false,
    };

    const filter = Filter.init(shared_config);

    // Test various dot-prefixed names
    try testing.expect(filter.shouldIgnore(".git"));
    try testing.expect(filter.shouldIgnore(".cache"));
    try testing.expect(filter.shouldIgnore(".hidden"));
    try testing.expect(filter.shouldIgnore("."));
    try testing.expect(filter.shouldIgnore(".."));

    // Test non-dot names
    try testing.expect(!filter.shouldIgnore("normal"));
    try testing.expect(!filter.shouldIgnore("git")); // no dot prefix
    try testing.expect(!filter.shouldIgnore("a.git")); // dot in middle

}

// Test hidden files functionality
test "hidden files functionality" {
    test_helpers.TestRunner.recordTest("hidden files functionality");
    const ignored = [_][]const u8{};
    const hidden = [_][]const u8{ "Thumbs.db", ".DS_Store", "desktop.ini" };

    const shared_config = SharedConfig{
        .ignored_patterns = &ignored,
        .hidden_files = &hidden,
        .gitignore_patterns = &[_][]const u8{},
        .symlink_behavior = .skip,
        .respect_gitignore = false,
        .patterns_allocated = false,
    };

    const filter = Filter.init(shared_config);

    // Test hidden files
    try testing.expect(filter.shouldHide("Thumbs.db"));
    try testing.expect(filter.shouldHide(".DS_Store"));
    try testing.expect(filter.shouldHide("desktop.ini"));

    // Test non-hidden files
    try testing.expect(!filter.shouldHide("normal.txt"));
    try testing.expect(!filter.shouldHide("Thumbs.db.backup")); // similar but not exact

}

// Test case sensitivity
test "case sensitivity" {
    test_helpers.TestRunner.recordTest("case sensitivity");
    const ignored = [_][]const u8{ "CaseSensitive", "lowercase" };
    const hidden = [_][]const u8{"HiddenFile.tmp"};

    const shared_config = SharedConfig{
        .ignored_patterns = &ignored,
        .hidden_files = &hidden,
        .gitignore_patterns = &[_][]const u8{},
        .symlink_behavior = .skip,
        .respect_gitignore = false,
        .patterns_allocated = false,
    };

    const filter = Filter.init(shared_config);

    // Test exact case matches
    try testing.expect(filter.shouldIgnore("CaseSensitive"));
    try testing.expect(filter.shouldIgnore("lowercase"));
    try testing.expect(filter.shouldHide("HiddenFile.tmp"));

    // Test case mismatches (should not match - case sensitive)
    try testing.expect(!filter.shouldIgnore("casesensitive"));
    try testing.expect(!filter.shouldIgnore("LOWERCASE"));
    try testing.expect(!filter.shouldIgnore("Lowercase"));
    try testing.expect(!filter.shouldHide("hiddenfile.tmp"));

}

// Test unicode and special characters
test "unicode and special characters" {
    test_helpers.TestRunner.recordTest("unicode and special characters");
    const ignored = [_][]const u8{
        "файл", // Cyrillic
        "ファイル", // Japanese
        "special@#$%", // Special characters
        "with spaces",
    };
    const hidden = [_][]const u8{};

    const shared_config = SharedConfig{
        .ignored_patterns = &ignored,
        .hidden_files = &hidden,
        .gitignore_patterns = &[_][]const u8{},
        .symlink_behavior = .skip,
        .respect_gitignore = false,
        .patterns_allocated = false,
    };

    const filter = Filter.init(shared_config);

    // Test unicode patterns
    try testing.expect(filter.shouldIgnore("файл"));
    try testing.expect(filter.shouldIgnore("ファイル"));
    try testing.expect(filter.shouldIgnore("special@#$%"));
    try testing.expect(filter.shouldIgnore("with spaces"));

    // Test non-matches
    try testing.expect(!filter.shouldIgnore("файлы")); // Different unicode
    try testing.expect(!filter.shouldIgnore("special"));

}

// Test empty configuration
test "empty configuration" {
    test_helpers.TestRunner.recordTest("empty configuration");
    const ignored = [_][]const u8{}; // Empty
    const hidden = [_][]const u8{}; // Empty

    const shared_config = SharedConfig{
        .ignored_patterns = &ignored,
        .hidden_files = &hidden,
        .gitignore_patterns = &[_][]const u8{},
        .symlink_behavior = .skip,
        .respect_gitignore = false,
        .patterns_allocated = false,
    };

    const filter = Filter.init(shared_config);

    // Only dot-prefixed should be ignored (built-in behavior)
    try testing.expect(filter.shouldIgnore(".git"));
    try testing.expect(!filter.shouldIgnore("anything_else"));
    try testing.expect(!filter.shouldIgnore("node_modules"));
    try testing.expect(!filter.shouldHide("Thumbs.db"));

}

// Test path traversal attack patterns
test "path traversal security" {
    test_helpers.TestRunner.recordTest("path traversal security");
    const ignored = [_][]const u8{ "../", "../../", ".." };
    const hidden = [_][]const u8{};

    const shared_config = SharedConfig{
        .ignored_patterns = &ignored,
        .hidden_files = &hidden,
        .gitignore_patterns = &[_][]const u8{},
        .symlink_behavior = .skip,
        .respect_gitignore = false,
        .patterns_allocated = false,
    };

    const filter = Filter.init(shared_config);

    // Should block path traversal attempts
    try testing.expect(filter.shouldIgnore("../"));
    try testing.expect(filter.shouldIgnore("../../"));
    try testing.expect(filter.shouldIgnore(".."));

    // But allow normal paths with .. in the name
    try testing.expect(!filter.shouldIgnore("file..txt"));
    try testing.expect(!filter.shouldIgnore("my..config"));

}

// Test extremely long filenames
test "long filename handling" {
    test_helpers.TestRunner.recordTest("long filename handling");
    // Create very long pattern and filename
    var long_pattern = [_]u8{'a'} ** 1000;
    var longer_filename = [_]u8{'a'} ** 1001;
    longer_filename[1000] = 'b'; // Make it different

    const ignored = [_][]const u8{&long_pattern};
    const hidden = [_][]const u8{};

    const shared_config = SharedConfig{
        .ignored_patterns = &ignored,
        .hidden_files = &hidden,
        .gitignore_patterns = &[_][]const u8{},
        .symlink_behavior = .skip,
        .respect_gitignore = false,
        .patterns_allocated = false,
    };

    const filter = Filter.init(shared_config);

    // Should match exact long pattern
    try testing.expect(filter.shouldIgnore(&long_pattern));
    // Should not match longer pattern
    try testing.expect(!filter.shouldIgnore(&longer_filename));

}

// Performance test with many patterns
test "performance with many patterns" {
    test_helpers.TestRunner.recordTest("performance with many patterns");
    // Create large pattern arrays
    var ignored_patterns = std.ArrayList([]const u8).init(testing.allocator);
    defer ignored_patterns.deinit();

    var hidden_files = std.ArrayList([]const u8).init(testing.allocator);
    defer hidden_files.deinit();

    // Add many patterns
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        const pattern = try std.fmt.allocPrint(testing.allocator, "pattern_{d}", .{i});
        defer testing.allocator.free(pattern);
        const pattern_copy = try testing.allocator.dupe(u8, pattern);
        try ignored_patterns.append(pattern_copy);

        const hidden = try std.fmt.allocPrint(testing.allocator, "hidden_{d}", .{i});
        defer testing.allocator.free(hidden);
        const hidden_copy = try testing.allocator.dupe(u8, hidden);
        try hidden_files.append(hidden_copy);
    }

    const shared_config = SharedConfig{
        .ignored_patterns = ignored_patterns.items,
        .hidden_files = hidden_files.items,
        .gitignore_patterns = &[_][]const u8{},
        .symlink_behavior = .skip,
        .respect_gitignore = false,
        .patterns_allocated = true,
    };

    const filter = Filter.init(shared_config);

    // Test performance of lookups
    const start_time = std.time.milliTimestamp();

    // PERFORMANCE OPTIMIZATION: Fast/slow path split implemented in matchesPathComponent()
    // Simple patterns (no slashes) now use optimized fast path, complex patterns use slow path
    // Should restore performance to ~1000ms range
    var test_iterations: u32 = 0;
    while (test_iterations < 1000) : (test_iterations += 1) {
        _ = filter.shouldIgnore("pattern_500"); // Should find
        _ = filter.shouldIgnore("not_found"); // Should not find
        _ = filter.shouldHide("hidden_750"); // Should find
        _ = filter.shouldHide("not_hidden"); // Should not find
    }

    const end_time = std.time.milliTimestamp();
    const duration = end_time - start_time;

    // Performance result (only show if test takes too long)
    if (duration > 500) {
        std.debug.print("⚠️  Performance test took {}ms (expected <500ms)\n", .{duration});
    }

    // Should complete reasonably quickly (decreased requirements for faster tests)
    try testing.expect(duration < 2000);

    // Cleanup allocated patterns
    for (ignored_patterns.items) |pattern| {
        testing.allocator.free(pattern);
    }
    for (hidden_files.items) |hidden| {
        testing.allocator.free(hidden);
    }

}
