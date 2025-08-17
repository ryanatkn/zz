// Tests for pattern validation functionality
const std = @import("std");
const MockFilesystem = @import("../filesystem/mock.zig").MockFilesystem;
const PatternValidator = @import("pattern_validator.zig").PatternValidator;

test "Pattern validation - include pattern with no matches fails fast" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var mock_fs = MockFilesystem.init(allocator);
    defer mock_fs.deinit();
    
    // Set up a repository with no JavaScript files
    try mock_fs.addDirectory("/repo");
    try mock_fs.addFile("/repo/main.zig", "content");
    try mock_fs.addFile("/repo/README.md", "content");
    
    var validator = PatternValidator.init(allocator, mock_fs.interface());
    defer validator.deinit();
    
    // Test pattern validation directly
    var result = try validator.validateIncludePatterns("/repo", &.{"*.js"}, &.{});
    defer result.deinit();
    
    // Should have failed patterns
    try testing.expect(result.failed_patterns.items.len == 1);
    try testing.expectEqualStrings("*.js", result.failed_patterns.items[0]);
}

test "Pattern validation - include pattern with matches succeeds" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var mock_fs = MockFilesystem.init(allocator);
    defer mock_fs.deinit();
    
    // Set up a repository with Zig files
    try mock_fs.addDirectory("/repo");
    try mock_fs.addFile("/repo/main.zig", "content");
    try mock_fs.addFile("/repo/lib.zig", "content");
    try mock_fs.addFile("/repo/README.md", "content");
    
    var validator = PatternValidator.init(allocator, mock_fs.interface());
    defer validator.deinit();
    
    // Test pattern validation directly
    var result = try validator.validateIncludePatterns("/repo", &.{"*.zig"}, &.{});
    defer result.deinit();
    
    // Should have no failed patterns and some matched files
    try testing.expect(result.failed_patterns.items.len == 0);
    try testing.expect(result.matched_files > 0);
}

test "Pattern validation - empty include list allows all files" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var mock_fs = MockFilesystem.init(allocator);
    defer mock_fs.deinit();
    
    // Set up a repository
    try mock_fs.addDirectory("/repo");
    try mock_fs.addFile("/repo/any-file.txt", "content");
    
    var validator = PatternValidator.init(allocator, mock_fs.interface());
    defer validator.deinit();
    
    // Test empty include patterns (should always pass)
    var result = try validator.validateIncludePatterns("/repo", &.{}, &.{});
    defer result.deinit();
    
    // Empty include patterns should always pass
    try testing.expect(result.failed_patterns.items.len == 0);
}

test "Pattern validation - empty repository fails fast" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var mock_fs = MockFilesystem.init(allocator);
    defer mock_fs.deinit();
    
    // Set up an empty repository (no files)
    try mock_fs.addDirectory("/repo");
    // No files added
    
    var validator = PatternValidator.init(allocator, mock_fs.interface());
    defer validator.deinit();
    
    // Test hasFiles on empty repository
    try testing.expect(!try validator.hasFiles("/repo"));
    
    // Test pattern validation on empty repository
    var result = try validator.validateIncludePatterns("/repo", &.{"*.zig"}, &.{});
    defer result.deinit();
    
    // Should fail because no files exist to match patterns
    try testing.expect(result.failed_patterns.items.len == 1);
    try testing.expect(result.total_files == 0);
}

test "Pattern validation - complex patterns with nested directories" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var mock_fs = MockFilesystem.init(allocator);
    defer mock_fs.deinit();
    
    // Set up a repository with nested structure
    try mock_fs.addDirectory("/repo");
    try mock_fs.addDirectory("/repo/src");
    try mock_fs.addDirectory("/repo/test");
    try mock_fs.addFile("/repo/src/main.zig", "content");
    try mock_fs.addFile("/repo/test/test.zig", "content");
    try mock_fs.addFile("/repo/build.zig", "content");
    try mock_fs.addFile("/repo/README.md", "content");
    
    var validator = PatternValidator.init(allocator, mock_fs.interface());
    defer validator.deinit();
    
    // Test 1: Include src directory only (should match)
    var result1 = try validator.validateIncludePatterns("/repo", &.{"src/"}, &.{});
    defer result1.deinit();
    try testing.expect(result1.failed_patterns.items.len == 0);
    try testing.expect(result1.matched_files > 0);
    
    // Test 2: Include pattern that matches nothing
    var result2 = try validator.validateIncludePatterns("/repo", &.{"nonexistent/"}, &.{});
    defer result2.deinit();
    try testing.expect(result2.failed_patterns.items.len == 1);
    try testing.expectEqualStrings("nonexistent/", result2.failed_patterns.items[0]);
}

test "Pattern validation error - PatternValidator integration" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var mock_fs = MockFilesystem.init(allocator);
    defer mock_fs.deinit();
    
    // Set up repository
    try mock_fs.addDirectory("/repo");
    try mock_fs.addFile("/repo/main.zig", "content");
    try mock_fs.addFile("/repo/lib.zig", "content");
    
    var validator = PatternValidator.init(allocator, mock_fs.interface());
    defer validator.deinit();
    
    // Test successful validation
    var good_result = try validator.validateIncludePatterns("/repo", &.{"*.zig"}, &.{});
    defer good_result.deinit();
    try testing.expect(good_result.failed_patterns.items.len == 0);
    
    // Test failed validation
    var bad_result = try validator.validateIncludePatterns("/repo", &.{"*.js"}, &.{});
    defer bad_result.deinit();
    try testing.expect(bad_result.failed_patterns.items.len == 1);
    try testing.expectEqualStrings("*.js", bad_result.failed_patterns.items[0]);
    
    // Test error message formatting
    const error_msg = try bad_result.formatError(allocator);
    defer allocator.free(error_msg);
    try testing.expect(std.mem.indexOf(u8, error_msg, "*.js") != null);
    try testing.expect(std.mem.indexOf(u8, error_msg, "main.zig") != null);
}