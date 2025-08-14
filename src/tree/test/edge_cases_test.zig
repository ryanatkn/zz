const std = @import("std");
const testing = std.testing;

const Walker = @import("../walker.zig").Walker;
const WalkerOptions = @import("../walker.zig").WalkerOptions;
const Config = @import("../config.zig").Config;
const SharedConfig = @import("../../config.zig").SharedConfig;
const test_helpers = @import("../../lib/test/helpers.zig");

// Test handling of various filesystem edge cases
test "symlink handling" {
    var ctx = try test_helpers.TmpDirTestContext.init(testing.allocator);
    defer ctx.deinit();

    // Create a regular directory
    try ctx.makeDir("regular");
    try ctx.writeFile("regular/file.txt", "content");

    // Try to create a symlink (might fail on some systems/permissions)
    ctx.tmp_dir.dir.symLink("regular", "symlink", .{}) catch |err| switch (err) {
        error.AccessDenied, error.FileNotFound => {
            std.debug.print("Symlink test skipped (no permission/support)\n", .{});
            return;
        },
        else => return err,
    };

    // Test that walker handles symlinks gracefully
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
    const walker_options = WalkerOptions{
        .filesystem = ctx.filesystem,
        .quiet = true,
    };
    const walker = Walker.initWithOptions(testing.allocator, config, walker_options);

    // Should not crash on symlinks
    walker.walk(".") catch |err| switch (err) {
        error.SymLinkLoop => {}, // Expected for some symlink scenarios
        else => return err,
    };

}

// Test null byte injection protection
test "null byte injection protection" {
    const ignored = [_][]const u8{"test\x00injection"};
    const hidden = [_][]const u8{};

    const shared_config = SharedConfig{
        .ignored_patterns = &ignored,
        .hidden_files = &hidden,
        .gitignore_patterns = &[_][]const u8{},
        .symlink_behavior = .skip,
        .respect_gitignore = false,
        .patterns_allocated = false,
    };

    const filter = @import("../filter.zig").Filter.init(shared_config);

    // Should handle null bytes safely
    try testing.expect(filter.shouldIgnore("test\x00injection"));
    try testing.expect(!filter.shouldIgnore("test"));
    try testing.expect(!filter.shouldIgnore("injection"));

}

// Test circular directory references (if possible to create)
test "circular reference handling" {
    // This is hard to test without actually creating circular references
    // But we can test that the walker doesn't crash on complex structures
    var ctx = try test_helpers.TmpDirTestContext.init(testing.allocator);
    defer ctx.deinit();

    // Create a deep structure that might cause issues
    var current_path = std.ArrayList(u8).init(testing.allocator);
    defer current_path.deinit();

    try current_path.appendSlice(".");

    var depth: u32 = 0;
    while (depth < 50) : (depth += 1) {
        try current_path.appendSlice("/level");
        const depth_str = std.fmt.allocPrint(testing.allocator, "{d}", .{depth}) catch "X";
        defer testing.allocator.free(depth_str);
        try current_path.appendSlice(depth_str);

        ctx.tmp_dir.dir.makePath(current_path.items) catch break;
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

    const config = Config{
        .max_depth = 10, // Limit depth to prevent infinite traversal
        .shared_config = shared_config,
    };

    const walker_options = WalkerOptions{
        .filesystem = ctx.filesystem,
        .quiet = true,
    };
    const walker = Walker.initWithOptions(testing.allocator, config, walker_options);

    try walker.walk(".");

}

// Test filesystem encoding issues
test "filesystem encoding edge cases" {
    const problematic_names = [_][]const u8{
        "normal_file.txt",
        "file with spaces.txt",
        "file-with-hyphens.txt",
        "file_with_underscores.txt",
        "UPPERCASE.TXT",
        "MiXeDcAsE.TxT",
        "123numbers.txt",
        "file.with.many.dots.txt",
        "file,with,commas.txt",
        "file;with;semicolons.txt",
        "file(with)parentheses.txt",
        "file[with]brackets.txt",
        "file{with}braces.txt",
        "file@with@at.txt",
        "file#with#hash.txt",
        "file$with$dollar.txt",
        "file%with%percent.txt",
        "file^with^caret.txt",
        "file&with&ampersand.txt",
        "file*with*asterisk.txt",
        "file+with+plus.txt",
        "file=with=equals.txt",
    };

    const ignored = [_][]const u8{ "file with spaces.txt", "UPPERCASE.TXT" };
    const hidden = [_][]const u8{};

    const shared_config = SharedConfig{
        .ignored_patterns = &ignored,
        .hidden_files = &hidden,
        .gitignore_patterns = &[_][]const u8{},
        .symlink_behavior = .skip,
        .respect_gitignore = false,
        .patterns_allocated = false,
    };

    const filter = @import("../filter.zig").Filter.init(shared_config);

    // Test that various encodings are handled correctly
    for (problematic_names) |name| {
        const should_ignore = std.mem.eql(u8, name, "file with spaces.txt") or
            std.mem.eql(u8, name, "UPPERCASE.TXT");
        try testing.expect(filter.shouldIgnore(name) == should_ignore);
    }

}
