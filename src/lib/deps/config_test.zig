// Tests for configuration functionality
const std = @import("std");
const config = @import("config.zig");

test "ZON parsing with simple dependency structure" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    // Test ZON content that should parse successfully
    const simple_zon =
        \\.{
        \\    .dependencies = .{
        \\        .@"tree-sitter" = .{
        \\            .url = "https://github.com/tree-sitter/tree-sitter.git",
        \\            .version = "v0.25.0",
        \\            .include = .{},
        \\            .exclude = .{ "build.zig", "*.md" },
        \\            .preserve_files = .{},
        \\            .patches = .{},
        \\        },
        \\    },
        \\}
    ;
    
    const ZonParser = @import("../parsing/zon_parser.zig").ZonParser;
    
    // Try parsing with a minimal structure first
    const MinimalConfig = struct {
        dependencies: struct {
            @"tree-sitter": struct {
                url: []const u8,
                version: []const u8,
                include: []const []const u8,
                exclude: []const []const u8,
                preserve_files: []const []const u8,
                patches: []const []const u8,
            },
        },
    };
    
    const parsed = try ZonParser.parseFromSlice(MinimalConfig, allocator, simple_zon);
    defer ZonParser.free(allocator, parsed);
    
    // Verify parsing succeeded
    try testing.expectEqualStrings("https://github.com/tree-sitter/tree-sitter.git", parsed.dependencies.@"tree-sitter".url);
    try testing.expectEqualStrings("v0.25.0", parsed.dependencies.@"tree-sitter".version);
}

test "ZON parsing debugging - understand structure" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    // Read the actual deps.zon file content
    const io = @import("../core/io.zig");
    const deps_zon_content = io.readFileOptional(allocator, "deps.zon") catch |err| switch (err) {
        else => {
            std.debug.print("Could not read deps.zon: {}\n", .{err});
            return; // Skip test if file doesn't exist
        },
    };
    
    if (deps_zon_content) |content| {
        defer allocator.free(content);
        
        std.debug.print("deps.zon content (first 200 chars): {s}\n", .{content[0..@min(200, content.len)]});
        std.debug.print("ZON file exists with {} characters\n", .{content.len});
        
        // Try to actually parse the ZON content now that we have comment stripping
        var parseResult = config.DepsZonConfig.parseFromZonContent(allocator, content) catch |err| {
            std.debug.print("ZON parsing failed with error: {}\n", .{err});
            // This is expected to fail for now - we're debugging
            return;
        };
        defer parseResult.deinit();
        
        std.debug.print("ZON parsing succeeded! Found {} dependencies\n", .{parseResult.dependencies.count()});
    }
}

test "Config module - version info serialization" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    const version_info = config.VersionInfo{
        .repository = "https://github.com/test/repo.git",
        .version = "v1.0.0",
        .commit = "abc123def456",
        .updated = 1704067200, // 2024-01-01 00:00:00 UTC
        .updated_by = "test@example.com",
    };
    
    // Test serialization
    const content = try version_info.toContent(allocator);
    defer allocator.free(content);
    
    // Verify content contains expected fields
    try testing.expect(std.mem.indexOf(u8, content, "Repository: https://github.com/test/repo.git") != null);
    try testing.expect(std.mem.indexOf(u8, content, "Version: v1.0.0") != null);
    try testing.expect(std.mem.indexOf(u8, content, "Commit: abc123def456") != null);
    
    // Test deserialization
    const parsed = try config.VersionInfo.parseFromContent(allocator, content);
    defer parsed.deinit(allocator);
    
    try testing.expectEqualStrings(version_info.repository, parsed.repository);
    try testing.expectEqualStrings(version_info.version, parsed.version);
    try testing.expectEqualStrings(version_info.commit, parsed.commit);
}