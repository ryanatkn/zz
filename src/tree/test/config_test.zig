const std = @import("std");
const testing = std.testing;

const Config = @import("../config.zig").Config;
const SharedConfig = @import("../../config.zig").SharedConfig;
const test_helpers = @import("../../lib/test/helpers.zig");

// Helper functions to reduce duplication
fn expectConfigHasPattern(config: Config, pattern: []const u8) !void {
    for (config.shared_config.ignored_patterns) |p| {
        if (std.mem.eql(u8, p, pattern)) return;
    }
    try testing.expect(false); // Pattern not found
}

// Test configuration loading and fallback behavior  
test "configuration loading with missing file" {
    // Use simple call + defer pattern
    var ctx = test_helpers.MockTestContext.init(testing.allocator);
    defer ctx.deinit();

    const args = [_][:0]const u8{"tree"};
    var config = try Config.fromArgs(testing.allocator, ctx.filesystem, @constCast(args[0..]));
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
}

// Test configuration with malformed file
test "configuration loading with invalid file" {
    // Use simple call + defer pattern
    var ctx = try test_helpers.TmpDirTestContext.init(testing.allocator);
    defer ctx.deinit();

    // Create malformed zz.zon file
    const malformed_content = "this is not valid zig syntax {[}";
    try ctx.writeFile("test_invalid.zon", malformed_content);

    // Should gracefully fall back to defaults
    const args2 = [_][:0]const u8{"tree"};
    var config = try Config.fromArgs(testing.allocator, ctx.filesystem, @constCast(args2[0..]));
    defer config.deinit(testing.allocator);

    // Verify fallback worked
    try testing.expect(config.shared_config.ignored_patterns.len > 0);
}

// Test depth parameter parsing
test "max depth parameter parsing" {
    // Use simple call + defer pattern
    var ctx = try test_helpers.TmpDirTestContext.init(testing.allocator);
    defer ctx.deinit();

    // Test valid depth
    const args1 = [_][:0]const u8{ "tree", ".", "3" };
    var config = try Config.fromArgs(testing.allocator, ctx.filesystem, @constCast(args1[0..]));
    defer config.deinit(testing.allocator);

    try testing.expect(config.max_depth != null);
    try testing.expect(config.max_depth.? == 3);

    // Test invalid depth (should be ignored)
    const args2 = [_][:0]const u8{ "tree", ".", "invalid" };
    var config2 = try Config.fromArgs(testing.allocator, ctx.filesystem, @constCast(args2[0..]));
    defer config2.deinit(testing.allocator);

    try testing.expect(config2.max_depth == null);

    // Test no depth parameter
    const args3 = [_][:0]const u8{ "tree", "." };
    var config3 = try Config.fromArgs(testing.allocator, ctx.filesystem, @constCast(args3[0..]));
    defer config3.deinit(testing.allocator);

    try testing.expect(config3.max_depth == null);
}

// Test configuration memory management
test "configuration memory management" {
    var ctx = try test_helpers.TmpDirTestContext.init(testing.allocator);
    defer ctx.deinit();

    // Test multiple config creations and deletions
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        const args_loop = [_][:0]const u8{"tree"};
        var config = try Config.fromArgs(testing.allocator, ctx.filesystem, @constCast(args_loop[0..]));
        defer config.deinit(testing.allocator);

        // Verify config is valid each time
        try testing.expect(config.shared_config.ignored_patterns.len > 0);
    }

}

// Test ZON file custom patterns loading
test "ZON file custom patterns are loaded correctly" {
    const allocator = std.testing.allocator;
    var ctx = try test_helpers.TmpDirTestContext.init(allocator);
    defer ctx.deinit();

    // Create ZON content with custom patterns
    const test_zon_content =
        \\.{
        \\    .base_patterns = "extend",
        \\    .ignored_patterns = .{
        \\        "custom_dir",
        \\        "temp_files",
        \\    },
        \\    .hidden_files = .{
        \\        "custom.hidden",
        \\    },
        \\}
    ;

    // Write ZON file to temp directory
    try ctx.writeFile("test.zon", test_zon_content);

    // Load config from the temp directory
    const ZonLoader = @import("../../config.zig").ZonLoader;
    var zon_loader = ZonLoader.init(allocator, ctx.filesystem);
    try zon_loader.loadFromDir(ctx.tmp_dir.dir, "test.zon");
    var shared_config = try zon_loader.getSharedConfigFromDir(ctx.tmp_dir.dir);
    defer {
        shared_config.deinit(allocator);
        zon_loader.deinit();
    }

    // Verify default patterns are still present (because we use "extend" mode)
    var found_git = false;
    var found_node_modules = false;
    for (shared_config.ignored_patterns) |pattern| {
        if (std.mem.eql(u8, pattern, ".git")) found_git = true;
        if (std.mem.eql(u8, pattern, "node_modules")) found_node_modules = true;
    }
    try std.testing.expect(found_git);
    try std.testing.expect(found_node_modules);

    // Verify custom patterns are added
    var found_custom_dir = false;
    var found_temp_files = false;
    for (shared_config.ignored_patterns) |pattern| {
        if (std.mem.eql(u8, pattern, "custom_dir")) found_custom_dir = true;
        if (std.mem.eql(u8, pattern, "temp_files")) found_temp_files = true;
    }
    try std.testing.expect(found_custom_dir);
    try std.testing.expect(found_temp_files);

    // Verify custom hidden files are added
    var found_custom_hidden = false;
    for (shared_config.hidden_files) |pattern| {
        if (std.mem.eql(u8, pattern, "custom.hidden")) found_custom_hidden = true;
    }
    try std.testing.expect(found_custom_hidden);

}

// Test edge case command line arguments
test "edge case command line arguments" {
    var ctx = try test_helpers.TmpDirTestContext.init(testing.allocator);
    defer ctx.deinit();

    // Empty args (just program name would be index 0, but we start with command)
    const args1 = [_][:0]const u8{"tree"};
    var config = try Config.fromArgs(testing.allocator, ctx.filesystem, @constCast(args1[0..]));
    defer config.deinit(testing.allocator);

    // Very large depth number
    const args_large = [_][:0]const u8{ "tree", ".", "999999" };
    var config_large = try Config.fromArgs(testing.allocator, ctx.filesystem, @constCast(args_large[0..]));
    defer config_large.deinit(testing.allocator);
    try testing.expect(config_large.max_depth.? == 999999);

    // Zero depth
    const args_zero = [_][:0]const u8{ "tree", ".", "0" };
    var config_zero = try Config.fromArgs(testing.allocator, ctx.filesystem, @constCast(args_zero[0..]));
    defer config_zero.deinit(testing.allocator);
    try testing.expect(config_zero.max_depth.? == 0);

}
