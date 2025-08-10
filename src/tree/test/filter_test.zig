const std = @import("std");
const testing = std.testing;
const Filter = @import("../filter.zig").Filter;
const TreeConfig = @import("../config.zig").TreeConfig;

// Test pattern matching edge cases
test "pattern matching edge cases" {
    const tree_config = TreeConfig{
        .ignored_patterns = &[_][]const u8{
            "exact_match",
            "node_modules",
            ".git",
            "src/hex/shaders/compiled",
        },
        .hidden_files = &[_][]const u8{ "Thumbs.db", ".DS_Store" },
    };

    const filter = Filter.init(tree_config);

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

    std.debug.print("✅ Pattern matching edge cases test passed!\n", .{});
}

// Test path-based pattern matching
test "path based pattern matching" {
    const tree_config = TreeConfig{
        .ignored_patterns = &[_][]const u8{
            "src/hex/shaders/compiled",
            "deep/nested/path",
        },
        .hidden_files = &[_][]const u8{},
    };

    const filter = Filter.init(tree_config);

    // Test path-based matches
    try testing.expect(filter.shouldIgnoreAtPath("project/src/hex/shaders/compiled"));
    try testing.expect(filter.shouldIgnoreAtPath("/absolute/src/hex/shaders/compiled"));
    try testing.expect(filter.shouldIgnoreAtPath("src/hex/shaders/compiled"));
    try testing.expect(filter.shouldIgnoreAtPath("very/deep/nested/path"));

    // Test non-matches
    try testing.expect(!filter.shouldIgnoreAtPath("src/hex/shaders"));
    try testing.expect(!filter.shouldIgnoreAtPath("src/hex/shaders/source"));
    try testing.expect(!filter.shouldIgnoreAtPath("compiled"));
    try testing.expect(!filter.shouldIgnoreAtPath("deep/nested"));

    std.debug.print("✅ Path-based pattern matching test passed!\n", .{});
}

// Test dot-directory behavior
test "dot directory behavior" {
    const tree_config = TreeConfig{
        .ignored_patterns = &[_][]const u8{}, // No explicit patterns
        .hidden_files = &[_][]const u8{},
    };

    const filter = Filter.init(tree_config);

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

    std.debug.print("✅ Dot directory behavior test passed!\n", .{});
}

// Test hidden files functionality
test "hidden files functionality" {
    const tree_config = TreeConfig{
        .ignored_patterns = &[_][]const u8{},
        .hidden_files = &[_][]const u8{ "Thumbs.db", ".DS_Store", "desktop.ini" },
    };

    const filter = Filter.init(tree_config);

    // Test hidden files
    try testing.expect(filter.shouldHide("Thumbs.db"));
    try testing.expect(filter.shouldHide(".DS_Store"));
    try testing.expect(filter.shouldHide("desktop.ini"));

    // Test non-hidden files
    try testing.expect(!filter.shouldHide("normal.txt"));
    try testing.expect(!filter.shouldHide("Thumbs.db.backup")); // similar but not exact

    std.debug.print("✅ Hidden files functionality test passed!\n", .{});
}

// Test case sensitivity
test "case sensitivity" {
    const tree_config = TreeConfig{
        .ignored_patterns = &[_][]const u8{ "CaseSensitive", "lowercase" },
        .hidden_files = &[_][]const u8{"HiddenFile.tmp"},
    };

    const filter = Filter.init(tree_config);

    // Test exact case matches
    try testing.expect(filter.shouldIgnore("CaseSensitive"));
    try testing.expect(filter.shouldIgnore("lowercase"));
    try testing.expect(filter.shouldHide("HiddenFile.tmp"));

    // Test case mismatches (should not match - case sensitive)
    try testing.expect(!filter.shouldIgnore("casesensitive"));
    try testing.expect(!filter.shouldIgnore("LOWERCASE"));
    try testing.expect(!filter.shouldIgnore("Lowercase"));
    try testing.expect(!filter.shouldHide("hiddenfile.tmp"));

    std.debug.print("✅ Case sensitivity test passed!\n", .{});
}

// Test unicode and special characters
test "unicode and special characters" {
    const tree_config = TreeConfig{
        .ignored_patterns = &[_][]const u8{
            "файл", // Cyrillic
            "ファイル", // Japanese
            "special@#$%", // Special characters
            "with spaces",
        },
        .hidden_files = &[_][]const u8{},
    };

    const filter = Filter.init(tree_config);

    // Test unicode patterns
    try testing.expect(filter.shouldIgnore("файл"));
    try testing.expect(filter.shouldIgnore("ファイル"));
    try testing.expect(filter.shouldIgnore("special@#$%"));
    try testing.expect(filter.shouldIgnore("with spaces"));

    // Test non-matches
    try testing.expect(!filter.shouldIgnore("файлы")); // Different unicode
    try testing.expect(!filter.shouldIgnore("special"));

    std.debug.print("✅ Unicode and special characters test passed!\n", .{});
}

// Test empty configuration
test "empty configuration" {
    const tree_config = TreeConfig{
        .ignored_patterns = &[_][]const u8{}, // Empty
        .hidden_files = &[_][]const u8{}, // Empty
    };

    const filter = Filter.init(tree_config);

    // Only dot-prefixed should be ignored (built-in behavior)
    try testing.expect(filter.shouldIgnore(".git"));
    try testing.expect(!filter.shouldIgnore("anything_else"));
    try testing.expect(!filter.shouldIgnore("node_modules"));
    try testing.expect(!filter.shouldHide("Thumbs.db"));

    std.debug.print("✅ Empty configuration test passed!\n", .{});
}

// Test path traversal attack patterns
test "path traversal security" {
    const tree_config = TreeConfig{
        .ignored_patterns = &[_][]const u8{ "../", "../../", ".." },
        .hidden_files = &[_][]const u8{},
    };

    const filter = Filter.init(tree_config);

    // Should block path traversal attempts
    try testing.expect(filter.shouldIgnore("../"));
    try testing.expect(filter.shouldIgnore("../../"));
    try testing.expect(filter.shouldIgnore(".."));

    // But allow normal paths with .. in the name
    try testing.expect(!filter.shouldIgnore("file..txt"));
    try testing.expect(!filter.shouldIgnore("my..config"));

    std.debug.print("✅ Path traversal security test passed!\n", .{});
}

// Test extremely long filenames
test "long filename handling" {
    // Create very long pattern and filename
    var long_pattern = [_]u8{'a'} ** 1000;
    var longer_filename = [_]u8{'a'} ** 1001;
    longer_filename[1000] = 'b'; // Make it different

    const tree_config = TreeConfig{
        .ignored_patterns = &[_][]const u8{&long_pattern},
        .hidden_files = &[_][]const u8{},
    };

    const filter = Filter.init(tree_config);

    // Should match exact long pattern
    try testing.expect(filter.shouldIgnore(&long_pattern));
    // Should not match longer pattern
    try testing.expect(!filter.shouldIgnore(&longer_filename));

    std.debug.print("✅ Long filename handling test passed!\n", .{});
}

// Performance test with many patterns
test "performance with many patterns" {
    // Create large pattern arrays
    var ignored_patterns = std.ArrayList([]const u8).init(testing.allocator);
    defer ignored_patterns.deinit();

    var hidden_files = std.ArrayList([]const u8).init(testing.allocator);
    defer hidden_files.deinit();

    // Add many patterns
    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        const pattern = try std.fmt.allocPrint(testing.allocator, "pattern_{d}", .{i});
        defer testing.allocator.free(pattern);
        const pattern_copy = try testing.allocator.dupe(u8, pattern);
        try ignored_patterns.append(pattern_copy);

        const hidden = try std.fmt.allocPrint(testing.allocator, "hidden_{d}", .{i});
        defer testing.allocator.free(hidden);
        const hidden_copy = try testing.allocator.dupe(u8, hidden);
        try hidden_files.append(hidden_copy);
    }

    const tree_config = TreeConfig{
        .ignored_patterns = ignored_patterns.items,
        .hidden_files = hidden_files.items,
    };

    const filter = Filter.init(tree_config);

    // Test performance of lookups
    const start_time = std.time.milliTimestamp();

    var test_iterations: u32 = 0;
    while (test_iterations < 10000) : (test_iterations += 1) {
        _ = filter.shouldIgnore("pattern_500"); // Should find
        _ = filter.shouldIgnore("not_found"); // Should not find
        _ = filter.shouldHide("hidden_750"); // Should find
        _ = filter.shouldHide("not_hidden"); // Should not find
    }

    const end_time = std.time.milliTimestamp();
    const duration = end_time - start_time;

    // Should complete reasonably quickly (less than 1 second for 10k iterations)
    try testing.expect(duration < 1000);

    // Cleanup allocated patterns
    for (ignored_patterns.items) |pattern| {
        testing.allocator.free(pattern);
    }
    for (hidden_files.items) |hidden| {
        testing.allocator.free(hidden);
    }

    std.debug.print("✅ Performance with many patterns test passed! ({d}ms)\n", .{duration});
}
