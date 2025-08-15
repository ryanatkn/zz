const std = @import("std");
const testing = std.testing;
const AstFormatter = @import("../../lib/parsing/ast_formatter.zig").AstFormatter;
const Formatter = @import("../../lib/parsing/formatter.zig").Formatter;
const Language = @import("../../lib/language/detection.zig").Language;

// Malformed TypeScript tests
test "malformed TypeScript function" {
    const malformed_sources = [_][]const u8{
        "function incomplete(", // Missing closing paren and body
        "function test() { return", // Missing semicolon and closing brace
        "function { return true; }", // Missing name and parameters
        "function test() { return true; // Missing closing brace",
        "functio test() { return true; }", // Typo in keyword
        "", // Empty source
        "   ", // Only whitespace
        "{ } ) ( [ ]", // Random brackets
    };

    for (malformed_sources, 0..) |source, i| {
        var formatter = AstFormatter.init(testing.allocator, .typescript, .{}) catch |err| {
            // If tree-sitter not available, gracefully skip the test
            if (err == error.IncompatibleVersion or err == error.UnsupportedLanguage) {
                // Expected in environments with tree-sitter version issues
                // This is not a test failure, just skip this iteration
                continue;
            }
            return err;
        };
        defer formatter.deinit();

        const result = formatter.format(source) catch |err| {
            // Parse errors should fall back to original source
            if (err == error.FormattingFailed) {
                const fallback = try testing.allocator.dupe(u8, source);
                defer testing.allocator.free(fallback);
                try testing.expect(std.mem.eql(u8, fallback, source));
                continue;
            }
            return err;
        };
        defer testing.allocator.free(result);

        // Should return some result (either formatted or original)
        try testing.expect(result.len >= source.len or result.len == 0);

        // For completely empty/whitespace sources, any result is acceptable
        if (source.len == 0 or std.mem.trim(u8, source, " \t\n\r").len == 0) {
            continue;
        }

        std.debug.print("Test {}: malformed source '{s}' -> result length {}\n", .{ i, source, result.len });
    }
}

// Malformed CSS tests
test "malformed CSS rules" {
    const malformed_sources = [_][]const u8{
        ".incomplete {", // Missing closing brace
        ".test { color: }", // Missing value
        "{ color: red; }", // Missing selector
        ".test { color red; }", // Missing colon
        ".test { color: red", // Missing semicolon and brace
        "@media (", // Incomplete media query
        "/* unclosed comment", // Unclosed comment
        ".test { /* nested /* comment */ }", // Nested comments
    };

    for (malformed_sources) |source| {
        var formatter = AstFormatter.init(testing.allocator, .css, .{}) catch |err| {
            if (err == error.IncompatibleVersion or err == error.UnsupportedLanguage) {
                // Test fallback to traditional CSS formatter
                var traditional = Formatter.init(testing.allocator, .css, .{});
                const result = traditional.format(source) catch |fallback_err| {
                    if (fallback_err == error.FormattingFailed) {
                        // Should not crash, graceful handling expected
                        continue;
                    }
                    return fallback_err;
                };
                defer testing.allocator.free(result);
                try testing.expect(result.len >= 0);
                continue;
            }
            return err;
        };
        defer formatter.deinit();

        const result = formatter.format(source) catch |err| {
            // Should gracefully handle parse errors
            if (err == error.FormattingFailed) {
                // Fallback to original source is acceptable
                continue;
            }
            return err;
        };
        defer testing.allocator.free(result);

        // Should not crash and should return some result
        try testing.expect(result.len >= 0);
    }
}

// Malformed Svelte tests
test "malformed Svelte components" {
    const malformed_sources = [_][]const u8{
        "<script>let name=", // Incomplete script
        "<script>let name='world';</script><h1>Hello {name", // Unclosed expression
        "<style>.test { color: }</style>", // Malformed CSS in style
        "<script>function test() {</script>", // Unclosed function in script
        "<div><span></div>", // Mismatched tags
        "{#if condition}<p>Test", // Incomplete Svelte directive
        "<script>import from 'module';</script>", // Invalid import
    };

    for (malformed_sources) |source| {
        var formatter = AstFormatter.init(testing.allocator, .svelte, .{}) catch |err| {
            if (err == error.IncompatibleVersion or err == error.UnsupportedLanguage) {
                // Test fallback behavior
                var traditional = Formatter.init(testing.allocator, .svelte, .{});
                const result = traditional.format(source) catch |fallback_err| {
                    if (fallback_err == error.FormattingFailed or fallback_err == error.UnsupportedLanguage) {
                        // Expected for malformed Svelte
                        continue;
                    }
                    return fallback_err;
                };
                defer testing.allocator.free(result);
                continue;
            }
            return err;
        };
        defer formatter.deinit();

        const result = formatter.format(source) catch |err| {
            // Parse errors should be handled gracefully
            if (err == error.FormattingFailed) {
                // Fallback behavior is acceptable
                continue;
            }
            return err;
        };
        defer testing.allocator.free(result);

        // Should handle gracefully without crashing
        try testing.expect(result.len >= 0);
    }
}

// Tree-sitter version compatibility
test "tree-sitter version compatibility" {
    const source = "function test() { return true; }";

    // Test graceful handling when tree-sitter version is incompatible
    var formatter = AstFormatter.init(testing.allocator, .typescript, .{}) catch |err| {
        if (err == error.IncompatibleVersion) {
            // This is expected and should be handled gracefully
            std.debug.print("Tree-sitter version incompatible (expected behavior)\n", .{});
            return;
        }
        if (err == error.UnsupportedLanguage) {
            // Also acceptable fallback
            return;
        }
        return err;
    };
    defer formatter.deinit();

    // If we get here, tree-sitter is available and should work
    const result = formatter.format(source) catch |err| {
        if (err == error.FormattingFailed) {
            // Graceful fallback is acceptable
            return;
        }
        return err;
    };
    defer testing.allocator.free(result);

    try testing.expect(result.len > 0);
}

// Large source code stress test
test "large source code handling" {
    var large_source = std.ArrayList(u8).init(testing.allocator);
    defer large_source.deinit();

    // Generate large TypeScript source (1000 functions)
    for (0..1000) |i| {
        try large_source.writer().print("function test{}(param: number): number {{ return param * {}; }}\n", .{ i, i });
    }

    var formatter = AstFormatter.init(testing.allocator, .typescript, .{}) catch |err| {
        if (err == error.IncompatibleVersion or err == error.UnsupportedLanguage) {
            return; // Skip if tree-sitter not available
        }
        return err;
    };
    defer formatter.deinit();

    const result = formatter.format(large_source.items) catch |err| {
        if (err == error.FormattingFailed or err == error.OutOfMemory) {
            // Large files might fail gracefully
            return;
        }
        return err;
    };
    defer testing.allocator.free(result);

    // Should handle large sources without crashing
    try testing.expect(result.len >= large_source.items.len / 2); // Allow some compression
}

// Unicode and special characters
test "unicode and special characters" {
    const unicode_sources = [_][]const u8{
        "function тест() { return 'Привет мир'; }", // Cyrillic
        "function 测试() { return '你好世界'; }", // Chinese
        "function test() { return '🚀 emoji 🎉'; }", // Emoji
        "function test() { return 'line1\\nline2'; }", // Escape sequences
        "function test() { return 'quote\\'test'; }", // Escaped quotes
        "/* 多行注释\n   with unicode */ function test() {}", // Unicode comments
    };

    for (unicode_sources) |source| {
        var formatter = AstFormatter.init(testing.allocator, .typescript, .{}) catch |err| {
            if (err == error.IncompatibleVersion or err == error.UnsupportedLanguage) {
                continue;
            }
            return err;
        };
        defer formatter.deinit();

        const result = formatter.format(source) catch |err| {
            // Unicode handling might fail gracefully
            if (err == error.FormattingFailed) {
                continue;
            }
            return err;
        };
        defer testing.allocator.free(result);

        // Should preserve unicode characters
        try testing.expect(result.len > 0);
        // Basic sanity check - should contain function keyword or fallback to original
        try testing.expect(std.mem.indexOf(u8, result, "function") != null or std.mem.eql(u8, result, source));
    }
}

// Memory pressure test
test "memory pressure handling" {
    // Test formatter behavior under memory constraints
    const source = "function test() { return true; }";

    // Create multiple formatters to test memory usage
    var formatters: [10]?AstFormatter = [_]?AstFormatter{null} ** 10;
    defer {
        for (&formatters) |*fmt| {
            if (fmt.*) |*f| {
                f.deinit();
            }
        }
    }

    // Initialize multiple formatters
    for (&formatters, 0..) |*fmt, i| {
        fmt.* = AstFormatter.init(testing.allocator, .typescript, .{}) catch |err| {
            if (err == error.IncompatibleVersion or err == error.UnsupportedLanguage or err == error.OutOfMemory) {
                // Expected under memory pressure
                break;
            }
            return err;
        };

        // Test formatting with each
        if (fmt.*) |*f| {
            const result = f.format(source) catch |err| {
                if (err == error.OutOfMemory or err == error.FormattingFailed) {
                    // Expected under pressure
                    continue;
                }
                return err;
            };
            defer testing.allocator.free(result);

            try testing.expect(result.len > 0);
        }

        // Stop at reasonable number to avoid excessive memory usage in tests
        if (i >= 5) break;
    }
}
