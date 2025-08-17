// Integration tests for documentation generation with dependency injection
const std = @import("std");
const docs = @import("docs/mod.zig");
const config = @import("config.zig");
const MockFilesystem = @import("../filesystem/mock.zig").MockFilesystem;

test "DocumentationGenerator - full integration with mock filesystem" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    // Setup mock filesystem
    var mock_fs = MockFilesystem.init(allocator);
    defer mock_fs.deinit();
    
    // Add mock dependency structure
    try mock_fs.addDirectory("deps");
    try mock_fs.addDirectory("deps/tree-sitter");
    try mock_fs.addFile("deps/tree-sitter/.version", 
        "Repository: https://github.com/tree-sitter/tree-sitter\n" ++
        "Version: v0.25.0\n" ++
        "Commit: abc123def456\n" ++
        "Updated: 1704067200\n" ++
        "Updated-By: test@example.com\n"
    );
    
    // Create test dependencies
    const test_deps = [_]config.Dependency{
        config.Dependency{
            .name = "tree-sitter",
            .url = "https://github.com/tree-sitter/tree-sitter",
            .version = "v0.25.0",
            .include = &.{},
            .exclude = &.{},
            .preserve_files = &.{},
            .patches = &.{},
            .category = "core",
            .language = null,
            .purpose = null,
        },
    };
    
    // Initialize generator with mock filesystem
    var generator = docs.DocumentationGenerator.initWithFilesystem(allocator, mock_fs.interface(), "deps");
    
    // This should not crash and should handle the mock filesystem gracefully
    // Note: The docs generators write to real filesystem via io.writeFile, not through the mock
    // This test verifies the system works without crashing when version files are available
    try generator.generateDocumentation(&test_deps);
}

test "DocumentationGenerator - handles missing version files gracefully" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    // Setup mock filesystem with no version files
    var mock_fs = MockFilesystem.init(allocator);
    defer mock_fs.deinit();
    
    try mock_fs.addDirectory("deps");
    
    // Create test dependencies without version files
    const test_deps = [_]config.Dependency{
        config.Dependency{
            .name = "test-dep",
            .url = "https://github.com/test/repo",
            .version = "v1.0.0",
            .include = &.{},
            .exclude = &.{},
            .preserve_files = &.{},
            .patches = &.{},
            .category = null,
            .language = null,
            .purpose = null,
        },
    };
    
    var generator = docs.DocumentationGenerator.initWithFilesystem(allocator, mock_fs.interface(), "deps");
    
    // Should handle missing version files without crashing
    // This test verifies the system creates reasonable defaults when version files don't exist
    try generator.generateDocumentation(&test_deps);
}

test "BuildParser - integration with missing build.zig" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    // Test BuildParser when build.zig doesn't exist (should use fallback)
    var parser = docs.BuildParser.init(allocator);
    
    // This should use fallback configuration since build.zig doesn't exist in test environment
    const config_result = try parser.extractBuildInfo("tree-sitter");
    defer config_result.deinit(allocator);
    
    // Should have some reasonable type (might be "unknown" if build.zig can't be parsed)
    try testing.expect(config_result.type.len > 0);
    try testing.expect(std.mem.eql(u8, config_result.type, "static_library") or 
                      std.mem.eql(u8, config_result.type, "unknown"));
}

test "DateTimeModule - integration with docs generation" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const datetime = @import("../core/datetime.zig");
    
    // Test that datetime module produces valid dates for docs
    const current_date = datetime.getCurrentDate();
    
    // Should produce reasonable current date
    try testing.expect(current_date.year >= 2024);
    try testing.expect(current_date.year <= 2030); // Reasonable upper bound
    try testing.expect(current_date.month >= 1 and current_date.month <= 12);
    try testing.expect(current_date.day >= 1 and current_date.day <= 31);
    
    // Test formatting works for documentation
    const date_str = try current_date.formatDate(allocator);
    defer allocator.free(date_str);
    
    const datetime_str = try current_date.formatDateTime(allocator);
    defer allocator.free(datetime_str);
    
    // Should produce valid ISO format strings
    try testing.expect(date_str.len == 10); // YYYY-MM-DD
    try testing.expect(datetime_str.len == 20); // YYYY-MM-DDTHH:MM:SSZ
    try testing.expect(std.mem.indexOf(u8, datetime_str, "T") != null);
    try testing.expect(std.mem.indexOf(u8, datetime_str, "Z") != null);
}

test "Memory management - all docs structures clean up properly" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    // Test that complex doc structures don't leak memory
    var mock_fs = MockFilesystem.init(allocator);
    defer mock_fs.deinit();
    
    try mock_fs.addDirectory("deps");
    
    const test_deps = [_]config.Dependency{
        config.Dependency{
            .name = "tree-sitter-css",
            .url = "https://github.com/tree-sitter/tree-sitter-css",
            .version = "v0.21.0",
            .include = &.{},
            .exclude = &.{},
            .preserve_files = &.{},
            .patches = &.{},
            .category = "grammar",
            .language = "css",
            .purpose = "CSS parsing",
        },
    };
    
    var generator = docs.DocumentationGenerator.initWithFilesystem(allocator, mock_fs.interface(), "deps");
    
    // Multiple rounds to test for accumulating leaks
    for (0..3) |_| {
        try generator.generateDocumentation(&test_deps);
    }
    
    // If we get here without crashes, memory management is working
}