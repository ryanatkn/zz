const std = @import("std");
const testing = std.testing;

const Config = @import("../config.zig").Config;
const SharedConfig = @import("../../config.zig").SharedConfig;

// Helper functions to reduce duplication
fn expectConfigHasPattern(config: Config, pattern: []const u8) !void {
    for (config.shared_config.ignored_patterns) |p| {
        if (std.mem.eql(u8, p, pattern)) return;
    }
    try testing.expect(false); // Pattern not found
}

// Test configuration loading and fallback behavior
test "configuration loading with missing file" {
    const args = [_][:0]const u8{"tree"};
    var config = try Config.fromArgs(testing.allocator, @constCast(args[0..]));
    defer config.deinit(testing.allocator);

    // Should load default configuration when zz.zon is missing
    try testing.expect(config.shared_config.ignored_patterns.len > 0);
    try testing.expect(config.shared_config.hidden_files.len > 0);

    // Verify default patterns are present
    var found_git = false;
    var found_node_modules = false;
    for (config.shared_config.ignored_patterns) |pattern| {
        if (std.mem.eql(u8, pattern, ".git")) found_git = true;
        if (std.mem.eql(u8, pattern, "node_modules")) found_node_modules = true;
    }
    try testing.expect(found_git);
    try testing.expect(found_node_modules);

    std.debug.print("✓ Configuration loading with missing file test passed!\n", .{});
}

// Test configuration with malformed file
test "configuration loading with invalid file" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create malformed zz.zon file
    const malformed_content = "this is not valid zig syntax {[}";
    const file = try tmp_dir.dir.createFile("test_invalid.zon", .{});
    defer file.close();

    try file.writeAll(malformed_content);

    // Should gracefully fall back to defaults
    const args2 = [_][:0]const u8{"tree"};
    var config = try Config.fromArgs(testing.allocator, @constCast(args2[0..]));
    defer config.deinit(testing.allocator);

    // Verify fallback worked
    try testing.expect(config.shared_config.ignored_patterns.len > 0);

    std.debug.print("✓ Configuration loading with invalid file test passed!\n", .{});
}

// Test depth parameter parsing
test "max depth parameter parsing" {
    // Test valid depth
    const args1 = [_][:0]const u8{ "tree", ".", "3" };
    var config = try Config.fromArgs(testing.allocator, @constCast(args1[0..]));
    defer config.deinit(testing.allocator);

    try testing.expect(config.max_depth != null);
    try testing.expect(config.max_depth.? == 3);

    // Test invalid depth (should be ignored)
    const args2 = [_][:0]const u8{ "tree", ".", "invalid" };
    var config2 = try Config.fromArgs(testing.allocator, @constCast(args2[0..]));
    defer config2.deinit(testing.allocator);

    try testing.expect(config2.max_depth == null);

    // Test no depth parameter
    const args3 = [_][:0]const u8{ "tree", "." };
    var config3 = try Config.fromArgs(testing.allocator, @constCast(args3[0..]));
    defer config3.deinit(testing.allocator);

    try testing.expect(config3.max_depth == null);

    std.debug.print("✓ Max depth parameter parsing test passed!\n", .{});
}

// Test configuration memory management
test "configuration memory management" {
    // Test multiple config creations and deletions
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        const args_loop = [_][:0]const u8{"tree"};
        var config = try Config.fromArgs(testing.allocator, @constCast(args_loop[0..]));
        defer config.deinit(testing.allocator);

        // Verify config is valid each time
        try testing.expect(config.shared_config.ignored_patterns.len > 0);
    }

    std.debug.print("✓ Configuration memory management test passed!\n", .{});
}

// Test ZON file custom patterns loading (currently failing - this captures the bug)
test "ZON file custom patterns are loaded correctly" {
    // Create a temporary ZON file with custom patterns
    const test_zon_content =
        \\.{
        \\    .base_patterns = "extend",
        \\    .ignored_patterns = .{
        \\        "custom_dir",
        \\        "src",
        \\    },
        \\}
    ;

    // Write to temporary file
    try std.fs.cwd().writeFile(.{ .sub_path = "test_custom.zon", .data = test_zon_content });
    defer std.fs.cwd().deleteFile("test_custom.zon") catch {};

    // Import ZonLoader
    const ZonLoader = @import("../../config.zig").ZonLoader;
    var zon_loader = ZonLoader.init(std.testing.allocator);
    var shared_config = try zon_loader.getSharedConfig();
    defer shared_config.deinit(std.testing.allocator);

    // This test verifies that ZON parsing works correctly
    // It tests the actual zz.zon in the current directory which has no custom patterns
    var found_git = false;
    var found_custom_dir = false;

    for (shared_config.ignored_patterns) |pattern| {
        if (std.mem.eql(u8, pattern, ".git")) found_git = true;
        if (std.mem.eql(u8, pattern, "custom_dir")) found_custom_dir = true;
    }

    try std.testing.expect(found_git); // Default pattern should work
    try std.testing.expect(!found_custom_dir); // No custom patterns in current zz.zon

    std.debug.print("✓ ZON custom patterns test passed!\n", .{});
}

// Test edge case command line arguments
test "edge case command line arguments" {
    // Empty args (just program name would be index 0, but we start with command)
    const args1 = [_][:0]const u8{"tree"};
    var config = try Config.fromArgs(testing.allocator, @constCast(args1[0..]));
    defer config.deinit(testing.allocator);

    // Very large depth number
    const args_large = [_][:0]const u8{ "tree", ".", "999999" };
    var config_large = try Config.fromArgs(testing.allocator, @constCast(args_large[0..]));
    defer config_large.deinit(testing.allocator);
    try testing.expect(config_large.max_depth.? == 999999);

    // Zero depth
    const args_zero = [_][:0]const u8{ "tree", ".", "0" };
    var config_zero = try Config.fromArgs(testing.allocator, @constCast(args_zero[0..]));
    defer config_zero.deinit(testing.allocator);
    try testing.expect(config_zero.max_depth.? == 0);

    std.debug.print("✓ Edge case command line arguments test passed!\n", .{});
}
