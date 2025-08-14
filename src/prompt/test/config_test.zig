const std = @import("std");
const testing = std.testing;
const test_helpers = @import("../../lib/test/helpers.zig");
const Config = @import("../config.zig").Config;

test "config parsing" {
    // Enhanced test pattern: setup + immediate defer for guaranteed cleanup
    var ctx = try test_helpers.TmpDirTestContext.init(testing.allocator);
    defer ctx.deinit();

    // Test with --prepend flag
    var args1 = [_][:0]const u8{ "zz", "prompt", "--prepend=Instructions here", "file.zig" };
    var config1 = try Config.fromArgs(testing.allocator, ctx.filesystem, &args1);
    defer config1.deinit();

    try testing.expect(config1.prepend_text != null);
    try testing.expectEqualStrings("Instructions here", config1.prepend_text.?);

    var patterns1 = try config1.getFilePatterns(&args1);
    defer patterns1.deinit();
    try testing.expect(patterns1.items.len == 1);
    try testing.expectEqualStrings("file.zig", patterns1.items[0]);

    // Test with --append flag
    var args2 = [_][:0]const u8{ "zz", "prompt", "--append=Follow-up text", "file.zig" };
    var config2 = try Config.fromArgs(testing.allocator, ctx.filesystem, &args2);
    defer config2.deinit();

    try testing.expect(config2.append_text != null);
    try testing.expectEqualStrings("Follow-up text", config2.append_text.?);

    // Test without text flags
    var args3 = [_][:0]const u8{ "zz", "prompt", "file1.zig", "file2.zig" };
    var config3 = try Config.fromArgs(testing.allocator, ctx.filesystem, &args3);
    defer config3.deinit();

    try testing.expect(config3.prepend_text == null);
    try testing.expect(config3.append_text == null);

    var patterns3 = try config3.getFilePatterns(&args3);
    defer patterns3.deinit();
    try testing.expect(patterns3.items.len == 2);
    try testing.expectEqualStrings("file1.zig", patterns3.items[0]);
    try testing.expectEqualStrings("file2.zig", patterns3.items[1]);

    // Test error when no files provided and no text flags
    var args4 = [_][:0]const u8{ "zz", "prompt" };
    var config4 = try Config.fromArgs(testing.allocator, ctx.filesystem, &args4);
    defer config4.deinit();

    const result = config4.getFilePatterns(&args4);
    try testing.expectError(error.NoInputFiles, result);
}

test "ignore patterns" {
    var ctx = try test_helpers.TmpDirTestContext.init(testing.allocator);
    defer ctx.deinit();

    var args = [_][:0]const u8{ "zz", "prompt" };
    var config = try Config.fromArgs(testing.allocator, ctx.filesystem, &args);
    defer config.deinit();

    // Test default ignore patterns
    try testing.expect(config.shouldIgnore(".git/config"));
    try testing.expect(config.shouldIgnore("path/to/.zig-cache/file"));
    try testing.expect(config.shouldIgnore("zig-out/bin/test"));
    try testing.expect(config.shouldIgnore("node_modules/package/index.js"));

    // Test non-ignored paths
    try testing.expect(!config.shouldIgnore("README.md"));
    try testing.expect(!config.shouldIgnore("docs/example.md"));
    try testing.expect(!config.shouldIgnore("build.zig"));
}

test "config flag parsing" {
    var ctx = try test_helpers.TmpDirTestContext.init(testing.allocator);
    defer ctx.deinit();

    // Test allow-empty-glob flag
    var args1 = [_][:0]const u8{ "zz", "prompt", "--allow-empty-glob", "file.zig" };
    var config1 = try Config.fromArgs(testing.allocator, ctx.filesystem, &args1);
    defer config1.deinit();

    try testing.expect(config1.allow_empty_glob == true);
    try testing.expect(config1.allow_missing == false);
    try testing.expect(config1.prepend_text == null);
    try testing.expect(config1.append_text == null);

    // Test allow-missing flag
    var args2 = [_][:0]const u8{ "zz", "prompt", "--allow-missing", "file.zig" };
    var config2 = try Config.fromArgs(testing.allocator, ctx.filesystem, &args2);
    defer config2.deinit();

    try testing.expect(config2.allow_empty_glob == false);
    try testing.expect(config2.allow_missing == true);

    // Test both flags
    var args3 = [_][:0]const u8{ "zz", "prompt", "--allow-empty-glob", "--allow-missing", "file.zig" };
    var config3 = try Config.fromArgs(testing.allocator, ctx.filesystem, &args3);
    defer config3.deinit();

    try testing.expect(config3.allow_empty_glob == true);
    try testing.expect(config3.allow_missing == true);

    // Test default (no flags)
    var args4 = [_][:0]const u8{ "zz", "prompt", "file.zig" };
    var config4 = try Config.fromArgs(testing.allocator, ctx.filesystem, &args4);
    defer config4.deinit();

    try testing.expect(config4.allow_empty_glob == false);
    try testing.expect(config4.allow_missing == false);
}
