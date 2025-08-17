const std = @import("std");
const testing = std.testing;

// Import all ZON modules for testing
const ZonParser = @import("parser.zig").ZonParser;
const DependencyInfo = @import("parser.zig").DependencyInfo;
const extractor = @import("extractor.zig");
const formatter = @import("formatter.zig");
const patterns = @import("patterns.zig");

// Comprehensive ZON module test suite
// Tests all functionality including parser, extractor, formatter, and patterns

test "ZON patterns are correctly defined" {
    try testing.expect(patterns.patterns.functions == null);
    try testing.expect(patterns.patterns.imports == null);
    try testing.expect(patterns.patterns.tests == null);
    try testing.expect(patterns.patterns.types != null);
    try testing.expect(patterns.patterns.docs != null);
    try testing.expect(patterns.patterns.structure != null);
}

test "ZonParser field extraction comprehensive" {
    const allocator = testing.allocator;
    
    const complex_zon =
        \\// Test ZON file with complex structure
        \\.{
        \\    .name = "complex-project",
        \\    .version = "2.1.0",
        \\    .@"quoted-field" = "special-value",
        \\    .@"another-quoted" = "another-value",
        \\    .settings = .{
        \\        .debug = true,
        \\        .optimization = "fast",
        \\    },
        \\    .dependencies = .{
        \\        .@"zig-tree-sitter" = .{
        \\            .url = "https://github.com/tree-sitter/zig-tree-sitter.git",
        \\            .version = "v0.25.0",
        \\            .include = .{},
        \\        },
        \\        .@"tree-sitter" = .{
        \\            .url = "https://github.com/tree-sitter/tree-sitter.git",
        \\            .version = "v0.25.0",
        \\            .exclude = .{ "test/", "*.md" },
        \\        },
        \\    },
        \\}
    ;
    
    var parser = ZonParser.init(allocator);
    
    // Test basic field extraction
    const name = try parser.extractField(complex_zon, "name");
    defer if (name) |n| allocator.free(n);
    try testing.expectEqualStrings("complex-project", name.?);
    
    const version = try parser.extractField(complex_zon, "version");
    defer if (version) |v| allocator.free(v);
    try testing.expectEqualStrings("2.1.0", version.?);
    
    // Test quoted field extraction
    const quoted = try parser.extractQuotedField(complex_zon, "quoted-field");
    defer if (quoted) |q| allocator.free(q);
    try testing.expectEqualStrings("special-value", quoted.?);
    
    // Test any field extraction
    const any_quoted = try parser.extractAnyField(complex_zon, "another-quoted");
    defer if (any_quoted) |aq| allocator.free(aq);
    try testing.expectEqualStrings("another-value", any_quoted.?);
    
    // Test missing field
    const missing = try parser.extractAnyField(complex_zon, "nonexistent");
    try testing.expectEqual(@as(?[]u8, null), missing);
}

test "ZonParser dependency parsing comprehensive" {
    const allocator = testing.allocator;
    
    const deps_zon =
        \\// Dependencies configuration
        \\.{
        \\    .dependencies = .{
        \\        .@"zig-tree-sitter" = .{
        \\            .url = "https://github.com/tree-sitter/zig-tree-sitter.git",
        \\            .version = "v0.25.0",
        \\        },
        \\        .@"tree-sitter" = .{
        \\            .url = "https://github.com/tree-sitter/tree-sitter.git",
        \\            .version = "v0.25.0",
        \\        },
        \\        .@"webref" = .{
        \\            .url = "https://github.com/w3c/webref.git",
        \\            .version = "main",
        \\        },
        \\    },
        \\    .settings = .{
        \\        .deps_dir = "deps",
        \\    },
        \\}
    ;
    
    var parser = ZonParser.init(allocator);
    var dependencies = try parser.parseDependencies(deps_zon);
    defer parser.freeDependencies(&dependencies);
    
    // Verify all dependencies were parsed
    try testing.expectEqual(@as(usize, 3), dependencies.count());
    
    // Check zig-tree-sitter
    const zig_ts = dependencies.get("zig-tree-sitter").?;
    try testing.expectEqualStrings("v0.25.0", zig_ts.version.?);
    try testing.expectEqualStrings("https://github.com/tree-sitter/zig-tree-sitter.git", zig_ts.url.?);
    
    // Check tree-sitter
    const ts = dependencies.get("tree-sitter").?;
    try testing.expectEqualStrings("v0.25.0", ts.version.?);
    try testing.expectEqualStrings("https://github.com/tree-sitter/tree-sitter.git", ts.url.?);
    
    // Check webref (main branch)
    const webref = dependencies.get("webref").?;
    try testing.expectEqualStrings("main", webref.version.?);
    try testing.expectEqualStrings("https://github.com/w3c/webref.git", webref.url.?);
}

test "extractor extractAllFields" {
    const allocator = testing.allocator;
    
    const test_zon =
        \\.{
        \\    .name = "test-extract",
        \\    .version = "1.2.3",
        \\    .@"quoted-name" = "quoted-value",
        \\    .author = "Test Author",
        \\}
    ;
    
    var fields = try extractor.extractAllFields(allocator, test_zon);
    defer {
        var iterator = fields.iterator();
        while (iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        fields.deinit();
    }
    
    try testing.expectEqual(@as(usize, 4), fields.count());
    try testing.expectEqualStrings("test-extract", fields.get("name").?);
    try testing.expectEqualStrings("1.2.3", fields.get("version").?);
    try testing.expectEqualStrings("quoted-value", fields.get("quoted-name").?);
    try testing.expectEqualStrings("Test Author", fields.get("author").?);
}

test "extractor extractConfigSections" {
    const allocator = testing.allocator;
    
    const full_config =
        \\.{
        \\    .dependencies = .{
        \\        .@"test-dep" = .{
        \\            .url = "https://example.com/repo.git",
        \\            .version = "v1.0.0",
        \\        },
        \\    },
        \\    .format = .{
        \\        .indent_size = 4,
        \\        .use_tabs = false,
        \\    },
        \\    .prompt = .{
        \\        .max_files = 100,
        \\        .include_docs = true,
        \\    },
        \\    .tree = .{
        \\        .max_depth = 10,
        \\        .show_hidden = false,
        \\    },
        \\}
    ;
    
    var sections = try extractor.extractConfigSections(allocator, full_config);
    defer extractor.freeConfigSections(allocator, &sections);
    
    // Check dependencies
    try testing.expectEqual(@as(usize, 1), sections.dependencies.count());
    const test_dep = sections.dependencies.get("test-dep").?;
    try testing.expectEqualStrings("v1.0.0", test_dep.version.?);
    
    // Check other sections exist
    try testing.expect(sections.format_config != null);
    try testing.expect(sections.prompt_config != null);
    try testing.expect(sections.tree_config != null);
    
    // Verify section content
    try testing.expect(std.mem.indexOf(u8, sections.format_config.?, "indent_size") != null);
    try testing.expect(std.mem.indexOf(u8, sections.prompt_config.?, "max_files") != null);
    try testing.expect(std.mem.indexOf(u8, sections.tree_config.?, "max_depth") != null);
}

test "extractor extractDependencyInfo" {
    const allocator = testing.allocator;
    
    const deps_content =
        \\.{
        \\    .dependencies = .{
        \\        .@"target-dep" = .{
        \\            .url = "https://github.com/user/repo.git",
        \\            .version = "v2.1.0",
        \\        },
        \\        .@"other-dep" = .{
        \\            .url = "https://github.com/other/repo.git",
        \\            .version = "main",
        \\        },
        \\    },
        \\}
    ;
    
    const dep_info = try extractor.extractDependencyInfo(allocator, deps_content, "target-dep");
    defer if (dep_info) |info| {
        if (info.version) |v| allocator.free(v);
        if (info.url) |u| allocator.free(u);
    };
    
    try testing.expect(dep_info != null);
    try testing.expectEqualStrings("v2.1.0", dep_info.?.version.?);
    try testing.expectEqualStrings("https://github.com/user/repo.git", dep_info.?.url.?);
    
    // Test missing dependency
    const missing_dep = try extractor.extractDependencyInfo(allocator, deps_content, "nonexistent");
    try testing.expectEqual(@as(?DependencyInfo, null), missing_dep);
}

test "extractor analyzeZonContent" {
    const test_content =
        \\// Main configuration file
        \\// Contains project settings
        \\.{
        \\    .name = "test-project",
        \\    .version = "1.0.0",
        \\    .settings = .{
        \\        .debug = true,
        \\    },
        \\    .dependencies = .{
        \\        .@"test-dep" = .{
        \\            .url = "https://example.com",
        \\        },
        \\    },
        \\}
        \\
    ;
    
    const analysis = extractor.analyzeZonContent(test_content);
    
    try testing.expectEqual(@as(u32, 2), analysis.comment_lines);
    try testing.expectEqual(@as(u32, 11), analysis.content_lines);
    try testing.expectEqual(@as(u32, 1), analysis.empty_lines);
    try testing.expectEqual(@as(u32, 5), analysis.field_count);
    try testing.expectEqual(@as(u32, 3), analysis.struct_count);
}

test "formatter isValidZon" {
    const valid_examples = [_][]const u8{
        \\.{ .name = "test" }
        ,
        \\.{
        \\    .field = "value",
        \\    .nested = .{
        \\        .inner = "data",
        \\    },
        \\}
        ,
        \\.{ }
        ,
    };
    
    const invalid_examples = [_][]const u8{
        \\.{ .name = "test"
        , // Missing closing brace
        \\.{
        \\    .field = "unclosed string,
        \\}
        , // Unclosed string
        \\.{
        \\    .field = "value",
        \\    .nested = .{
        \\        .inner = "data",
        \\    // Missing closing brace
        \\}
        ,
    };
    
    for (valid_examples) |example| {
        try testing.expect(formatter.isValidZon(example));
    }
    
    for (invalid_examples) |example| {
        try testing.expect(!formatter.isValidZon(example));
    }
}

test "formatter formatZon basic formatting" {
    const allocator = testing.allocator;
    
    const input =
        \\.{
        \\.name="unformatted",
        \\.version   =   "1.0.0"   ,
        \\.nested=.{
        \\.value="test",
        \\},
        \\}
    ;
    
    const options = @import("../../parsing/formatter.zig").FormatterOptions{};
    const formatted = try formatter.formatZon(allocator, input, options);
    defer allocator.free(formatted);
    
    // Check that spacing is corrected
    try testing.expect(std.mem.indexOf(u8, formatted, " = ") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "name=\"unformatted\"") == null); // Should have spaces
}

test "formatter formatZonMinimal preserves comments" {
    const allocator = testing.allocator;
    
    const input =
        \\// Important comment
        \\.{
        \\    .name="test",  // Inline comment
        \\    .version="1.0.0",
        \\}
    ;
    
    const options = @import("../../parsing/formatter.zig").FormatterOptions{};
    const formatted = try formatter.formatZonMinimal(allocator, input, options);
    defer allocator.free(formatted);
    
    // Comments should be preserved
    try testing.expect(std.mem.indexOf(u8, formatted, "// Important comment") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "// Inline comment") != null);
    
    // Spacing should be fixed
    try testing.expect(std.mem.indexOf(u8, formatted, " = ") != null);
}

test "integration test: parse deps.zon format" {
    const allocator = testing.allocator;
    
    // Test with the actual deps.zon format used in the project
    const deps_zon_content =
        \\// Dependency configuration for zz CLI utilities
        \\.{
        \\    .dependencies = .{
        \\        .@"tree-sitter" = .{
        \\            .url = "https://github.com/tree-sitter/tree-sitter.git",
        \\            .version = "v0.25.0",
        \\            .include = .{},
        \\            .exclude = .{ "build.zig", "*.md" },
        \\        },
        \\        .@"zig-tree-sitter" = .{
        \\            .url = "https://github.com/tree-sitter/zig-tree-sitter.git",
        \\            .version = "v0.25.0",
        \\        },
        \\    },
        \\}
    ;
    
    // Test parsing
    var parser = ZonParser.init(allocator);
    var dependencies = try parser.parseDependencies(deps_zon_content);
    defer parser.freeDependencies(&dependencies);
    
    try testing.expectEqual(@as(usize, 2), dependencies.count());
    
    const tree_sitter = dependencies.get("tree-sitter").?;
    try testing.expectEqualStrings("v0.25.0", tree_sitter.version.?);
    try testing.expectEqualStrings("https://github.com/tree-sitter/tree-sitter.git", tree_sitter.url.?);
    
    // Test formatting
    const options = @import("../../parsing/formatter.zig").FormatterOptions{};
    const formatted = try formatter.formatZonPretty(allocator, deps_zon_content, options);
    defer allocator.free(formatted);
    
    // Should preserve structure and comments
    try testing.expect(std.mem.indexOf(u8, formatted, "// Dependency configuration") != null);
    try testing.expect(formatter.isValidZon(formatted));
}

test "memory management: no leaks in parser" {
    const allocator = testing.allocator;
    
    const test_content =
        \\.{
        \\    .dependencies = .{
        \\        .@"test-dep-1" = .{
        \\            .url = "https://example.com/repo1.git",
        \\            .version = "v1.0.0",
        \\        },
        \\        .@"test-dep-2" = .{
        \\            .url = "https://example.com/repo2.git",
        \\            .version = "v2.0.0",
        \\        },
        \\    },
        \\}
    ;
    
    // Parse and free multiple times to test for leaks
    for (0..10) |_| {
        var parser = ZonParser.init(allocator);
        var deps = try parser.parseDependencies(test_content);
        parser.freeDependencies(&deps);
        
        // Also test individual field extraction
        const name = try parser.extractAnyField(test_content, "nonexistent");
        try testing.expectEqual(@as(?[]u8, null), name);
    }
}

test "edge cases: malformed ZON handling" {
    const allocator = testing.allocator;
    
    const malformed_cases = [_][]const u8{
        "", // Empty content
        "// Only comments", // Only comments
        \\.{ // Incomplete
        ,
        \\.{
        \\    .field_without_value = 
        \\}
        , // Incomplete field
        \\.{
        \\    .@"unclosed-quote = "value",
        \\}
        , // Unclosed quoted field name
    };
    
    var parser = ZonParser.init(allocator);
    
    for (malformed_cases) |case| {
        // Parser should handle malformed input gracefully
        const deps = parser.parseDependencies(case) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => continue, // Other errors are acceptable for malformed input
        };
        
        // If parsing succeeds, should return empty results
        try testing.expectEqual(@as(usize, 0), deps.count());
        parser.freeDependencies(&deps);
    }
}