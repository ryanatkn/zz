// Tests for documentation generation modules
const std = @import("std");
const docs = @import("docs/mod.zig");
const config = @import("config.zig");
const MockFilesystem = @import("../filesystem/mock.zig").MockFilesystem;

test "DependencyCategory - toString and displayName" {
    const testing = std.testing;

    // Test enum string representations
    try testing.expectEqualStrings("core", docs.DependencyCategory.core.toString());
    try testing.expectEqualStrings("grammar", docs.DependencyCategory.grammar.toString());
    try testing.expectEqualStrings("reference", docs.DependencyCategory.reference.toString());

    // Test display names
    try testing.expectEqualStrings("Core Libraries", docs.DependencyCategory.core.displayName());
    try testing.expectEqualStrings("Language Grammars", docs.DependencyCategory.grammar.displayName());
    try testing.expectEqualStrings("Reference Documentation", docs.DependencyCategory.reference.displayName());
}

test "BuildParser - can be initialized" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test that BuildParser can be initialized
    const parser = docs.BuildParser.init(allocator);
    _ = parser; // Just verify it compiles and can be created
}

test "DocumentationGenerator - can be initialized" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var mock_fs = MockFilesystem.init(allocator);
    defer mock_fs.deinit();

    // Test that DocumentationGenerator can be initialized
    const generator = docs.DocumentationGenerator.initWithFilesystem(allocator, mock_fs.interface(), "deps");
    _ = generator; // Just verify it compiles and can be created
}

test "ManifestGenerator - basic structure" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test that ManifestGenerator can be initialized
    const generator = docs.ManifestGenerator.init(allocator, "test_deps");
    _ = generator; // Just verify it compiles and can be created
}

test "BuildConfig - memory management" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test that BuildConfig properly manages memory
    var config_obj = docs.BuildConfig{
        .type = try allocator.dupe(u8, "static_library"),
        .source_files = try allocator.alloc([]const u8, 2),
        .include_paths = try allocator.alloc([]const u8, 1),
        .flags = try allocator.alloc([]const u8, 1),
        .parser_function = try allocator.dupe(u8, "tree_sitter_css"),
    };

    config_obj.source_files[0] = try allocator.dupe(u8, "src/parser.c");
    config_obj.source_files[1] = try allocator.dupe(u8, "src/scanner.c");
    config_obj.include_paths[0] = try allocator.dupe(u8, "src");
    config_obj.flags[0] = try allocator.dupe(u8, "-std=c11");

    // Verify deinit doesn't crash (memory management test)
    config_obj.deinit(allocator);
}

test "DependencyDoc - memory management" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test that DependencyDoc properly manages memory
    var doc = docs.DependencyDoc{
        .name = try allocator.dupe(u8, "test-dep"),
        .category = docs.DependencyCategory.core,
        .version_info = config.VersionInfo{
            .repository = try allocator.dupe(u8, "https://github.com/test/repo"),
            .version = try allocator.dupe(u8, "v1.0.0"),
            .commit = try allocator.dupe(u8, "abc123"),
            .updated = 1704067200,
            .updated_by = try allocator.dupe(u8, "test"),
        },
        .build_config = docs.BuildConfig{
            .type = try allocator.dupe(u8, "static_library"),
            .source_files = try allocator.alloc([]const u8, 0),
            .include_paths = try allocator.alloc([]const u8, 0),
            .flags = try allocator.alloc([]const u8, 0),
            .parser_function = null,
        },
        .language = try allocator.dupe(u8, "css"),
        .purpose = try allocator.dupe(u8, "Test dependency"),
    };

    // Verify deinit doesn't crash (memory management test)
    doc.deinit(allocator);
}
