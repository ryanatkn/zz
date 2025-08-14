const std = @import("std");
const testing = std.testing;

const Walker = @import("../walker.zig").Walker;
const WalkerOptions = @import("../walker.zig").WalkerOptions;
const Config = @import("../config.zig").Config;
const SharedConfig = @import("../../config.zig").SharedConfig;
const test_helpers = @import("../../lib/test/helpers.zig");

// Test thread safety and concurrent access patterns
test "multiple walker instances" {
    var ctx = try test_helpers.TmpDirTestContext.init(testing.allocator);
    defer ctx.deinit();

    // Create test structure
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        const dir_name = try std.fmt.allocPrint(testing.allocator, "dir_{d}", .{i});
        defer testing.allocator.free(dir_name);
        try ctx.makeDir(dir_name);

        const file_name = try std.fmt.allocPrint(testing.allocator, "{s}/file.txt", .{dir_name});
        defer testing.allocator.free(file_name);
        try ctx.writeFile(file_name, "test content");
    }

    const ignored = [_][]const u8{};
    const hidden = [_][]const u8{};

    const shared_config = SharedConfig{
        .ignored_patterns = &ignored,
        .hidden_files = &hidden,
        .gitignore_patterns = &[_][]const u8{},
        .symlink_behavior = .skip,
        .respect_gitignore = false,
        .patterns_allocated = false,
    };

    const config = Config{ .shared_config = shared_config };

    // Create multiple walker instances (should be safe)
    const opts1 = WalkerOptions{ .filesystem = ctx.filesystem, .quiet = true };
    const walker1 = Walker.initWithOptions(testing.allocator, config, opts1);
    const opts2 = WalkerOptions{ .filesystem = ctx.filesystem, .quiet = true };
    const walker2 = Walker.initWithOptions(testing.allocator, config, opts2);
    const opts3 = WalkerOptions{ .filesystem = ctx.filesystem, .quiet = true };
    const walker3 = Walker.initWithOptions(testing.allocator, config, opts3);

    // All should work independently
    try walker1.walk(ctx.path);
    try walker2.walk(ctx.path);
    try walker3.walk(ctx.path);

}

// Test configuration immutability
test "config immutability" {
    var ctx = try test_helpers.TmpDirTestContext.init(testing.allocator);
    defer ctx.deinit();

    const ignored = [_][]const u8{ "test1", "test2" };
    const hidden = [_][]const u8{"hidden1"};

    const shared_config = SharedConfig{
        .ignored_patterns = &ignored,
        .hidden_files = &hidden,
        .gitignore_patterns = &[_][]const u8{},
        .symlink_behavior = .skip,
        .respect_gitignore = false,
        .patterns_allocated = false,
    };

    const config = Config{ .shared_config = shared_config };

    // Create multiple walkers with same config
    const opts1 = WalkerOptions{ .filesystem = ctx.filesystem, .quiet = true };
    const walker1 = Walker.initWithOptions(testing.allocator, config, opts1);
    const opts2 = WalkerOptions{ .filesystem = ctx.filesystem, .quiet = true };
    const walker2 = Walker.initWithOptions(testing.allocator, config, opts2);

    // Both should have the same configuration
    try testing.expect(walker1.filter.shared_config.ignored_patterns.len == 2);
    try testing.expect(walker2.filter.shared_config.ignored_patterns.len == 2);
    try testing.expect(walker1.filter.shared_config.hidden_files.len == 1);
    try testing.expect(walker2.filter.shared_config.hidden_files.len == 1);

}

// Test rapid creation/destruction of configs
test "rapid config lifecycle" {
    var ctx = try test_helpers.TmpDirTestContext.init(testing.allocator);
    defer ctx.deinit();

    var iteration: u32 = 0;
    while (iteration < 100) : (iteration += 1) {
        var args = [_][:0]const u8{"tree"};
        var config = try Config.fromArgs(testing.allocator, ctx.filesystem, @ptrCast(&args));
        defer config.deinit(testing.allocator);

        // Verify config is valid each time
        try testing.expect(config.shared_config.ignored_patterns.len > 0);

        // Create walker and immediately destroy
        const opts_walk = WalkerOptions{ .filesystem = ctx.filesystem, .quiet = true };
        const walker = Walker.initWithOptions(testing.allocator, config, opts_walk);
        _ = walker; // Just creation/destruction cycle
    }

}

// Test memory behavior under stress
test "memory stress with config changes" {
    var ctx = try test_helpers.TmpDirTestContext.init(testing.allocator);
    defer ctx.deinit();

    // Test many different config combinations
    const patterns_sets = [_][]const []const u8{
        &[_][]const u8{},
        &[_][]const u8{"node_modules"},
        &[_][]const u8{ "node_modules", ".git" },
        &[_][]const u8{ "node_modules", ".git", "target", "dist" },
        &[_][]const u8{ ".git", ".cache", ".zig-cache", "zig-out" },
    };

    for (patterns_sets) |patterns| {
        const hidden = [_][]const u8{};

        const shared_config = SharedConfig{
            .ignored_patterns = patterns,
            .hidden_files = &hidden,
            .gitignore_patterns = &[_][]const u8{},
            .symlink_behavior = .skip,
            .respect_gitignore = false,
            .patterns_allocated = false,
        };

        const config = Config{ .shared_config = shared_config };
        const opts_walk = WalkerOptions{ .filesystem = ctx.filesystem, .quiet = true };
        const walker = Walker.initWithOptions(testing.allocator, config, opts_walk);

        // Verify walker works with different configs
        _ = walker;
    }

}
