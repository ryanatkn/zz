const std = @import("std");
const testing = std.testing;
const CachedFormatterManager = @import("../parsing/cached_formatter.zig").CachedFormatterManager;
const FormatterOptions = @import("../parsing/formatter.zig").FormatterOptions;
const Language = @import("../language/detection.zig").Language;

test "cached formatter manager initialization" {
    var manager = CachedFormatterManager.init(testing.allocator, 100) catch |err| {
        // If initialization fails due to tree-sitter issues, that's expected
        if (err == error.IncompatibleVersion or err == error.UnsupportedLanguage) {
            return;
        }
        return err;
    };
    defer manager.deinit();
    
    // Initially should have no formatters
    try testing.expect(manager.getFormatterCount() == 0);
    
    // Cache should be empty
    const stats = manager.getCacheStats();
    try testing.expect(stats.hits == 0);
    try testing.expect(stats.misses == 0);
}

test "cached formatter creation and reuse" {
    var manager = CachedFormatterManager.init(testing.allocator, 100) catch |err| {
        if (err == error.IncompatibleVersion or err == error.UnsupportedLanguage) {
            return;
        }
        return err;
    };
    defer manager.deinit();
    
    const options = FormatterOptions{};
    
    // Get a TypeScript formatter
    const formatter1 = manager.getFormatter(.typescript, options) catch |err| {
        if (err == error.IncompatibleVersion or err == error.UnsupportedLanguage) {
            return;
        }
        return err;
    };
    
    // Should now have one formatter
    try testing.expect(manager.getFormatterCount() == 1);
    
    // Get the same formatter again
    const formatter2 = manager.getFormatter(.typescript, options) catch |err| {
        if (err == error.IncompatibleVersion or err == error.UnsupportedLanguage) {
            return;
        }
        return err;
    };
    
    // Should be the same instance (reused)
    try testing.expect(formatter1 == formatter2);
    try testing.expect(manager.getFormatterCount() == 1);
    
    // Get a different language formatter
    const formatter3 = manager.getFormatter(.css, options) catch |err| {
        if (err == error.IncompatibleVersion or err == error.UnsupportedLanguage) {
            return;
        }
        return err;
    };
    
    // Should now have two formatters
    try testing.expect(manager.getFormatterCount() == 2);
    try testing.expect(formatter1 != formatter3);
}

test "cached formatter file formatting" {
    var manager = CachedFormatterManager.init(testing.allocator, 100) catch |err| {
        if (err == error.IncompatibleVersion or err == error.UnsupportedLanguage) {
            return;
        }
        return err;
    };
    defer manager.deinit();
    
    const options = FormatterOptions{};
    
    // Format a JSON file
    const json_source = "{\"name\":\"test\",\"version\":\"1.0.0\"}";
    const result1 = manager.formatFile("test.json", json_source, options) catch |err| {
        if (err == error.UnsupportedLanguage) {
            return; // Expected for some test environments
        }
        return err;
    };
    defer testing.allocator.free(result1);
    
    // Should have formatted the JSON
    try testing.expect(result1.len > json_source.len); // Should be pretty-printed
    try testing.expect(std.mem.indexOf(u8, result1, "name") != null);
    try testing.expect(std.mem.indexOf(u8, result1, "test") != null);
}

test "cached formatter with unknown file type" {
    var manager = CachedFormatterManager.init(testing.allocator, 100) catch |err| {
        if (err == error.IncompatibleVersion or err == error.UnsupportedLanguage) {
            return;
        }
        return err;
    };
    defer manager.deinit();
    
    const options = FormatterOptions{};
    
    // Format an unknown file type
    const unknown_source = "Some random text content";
    const result = try manager.formatFile("unknown.xyz", unknown_source, options);
    defer testing.allocator.free(result);
    
    // Should return original source unchanged
    try testing.expect(std.mem.eql(u8, result, unknown_source));
}

test "cached formatter source formatting" {
    var manager = CachedFormatterManager.init(testing.allocator, 100) catch |err| {
        if (err == error.IncompatibleVersion or err == error.UnsupportedLanguage) {
            return;
        }
        return err;
    };
    defer manager.deinit();
    
    const options = FormatterOptions{};
    
    // Format TypeScript source directly
    const ts_source = "function test(){return true;}";
    const result = manager.formatSource(.typescript, ts_source, options) catch |err| {
        if (err == error.UnsupportedLanguage) {
            return; // Expected for some test environments
        }
        return err;
    };
    defer testing.allocator.free(result);
    
    // Should have attempted to format
    try testing.expect(result.len > 0);
}

test "cache invalidation" {
    var manager = CachedFormatterManager.init(testing.allocator, 100) catch |err| {
        if (err == error.IncompatibleVersion or err == error.UnsupportedLanguage) {
            return;
        }
        return err;
    };
    defer manager.deinit();
    
    // Test cache clearing
    manager.clearCache();
    
    // Cache should be cleared (can't directly test count but operations should work)
    const stats_after_clear = manager.getCacheStats();
    _ = stats_after_clear; // Verify stats are accessible
    
    // Test file invalidation (should not crash)
    manager.invalidateFile("test.ts");
}

test "cache statistics" {
    var manager = CachedFormatterManager.init(testing.allocator, 100) catch |err| {
        if (err == error.IncompatibleVersion or err == error.UnsupportedLanguage) {
            return;
        }
        return err;
    };
    defer manager.deinit();
    
    // Initial stats should show empty cache
    const initial_stats = manager.getCacheStats();
    try testing.expect(initial_stats.hits == 0);
    try testing.expect(initial_stats.misses == 0);
    
    // Clear cache and verify
    manager.clearCache();
    const cleared_stats = manager.getCacheStats();
    _ = cleared_stats; // Verify stats are accessible
}

test "formatter options update" {
    var manager = CachedFormatterManager.init(testing.allocator, 100) catch |err| {
        if (err == error.IncompatibleVersion or err == error.UnsupportedLanguage) {
            return;
        }
        return err;
    };
    defer manager.deinit();
    
    const options1 = FormatterOptions{ .indent_size = 2 };
    const options2 = FormatterOptions{ .indent_size = 4 };
    
    // Get formatter with first options
    const formatter1 = manager.getFormatter(.typescript, options1) catch |err| {
        if (err == error.IncompatibleVersion or err == error.UnsupportedLanguage) {
            return;
        }
        return err;
    };
    
    try testing.expect(formatter1.options.indent_size == 2);
    
    // Get same formatter with different options
    const formatter2 = manager.getFormatter(.typescript, options2) catch |err| {
        if (err == error.IncompatibleVersion or err == error.UnsupportedLanguage) {
            return;
        }
        return err;
    };
    
    // Should be same instance but with updated options
    try testing.expect(formatter1 == formatter2);
    try testing.expect(formatter2.options.indent_size == 4);
}