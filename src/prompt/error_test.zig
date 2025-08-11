const std = @import("std");
const Config = @import("config.zig").Config;
const GlobExpander = @import("glob.zig").GlobExpander;

test "error on non-matching glob patterns" {
    const allocator = std.testing.allocator;
    var expander = GlobExpander.init(allocator);
    
    // Test that glob pattern with no matches returns empty
    var patterns = [_][]const u8{"*.nonexistent_extension_xyz"};
    var results = try expander.expandPatternsWithInfo(&patterns);
    defer {
        for (results.items) |*result| {
            for (result.files.items) |path| {
                allocator.free(path);
            }
            result.files.deinit();
        }
        results.deinit();
    }
    
    try std.testing.expect(results.items.len == 1);
    try std.testing.expect(results.items[0].files.items.len == 0);
    try std.testing.expect(results.items[0].is_glob == true);
}

test "error on explicit missing files" {
    const allocator = std.testing.allocator;
    var expander = GlobExpander.init(allocator);
    
    // Test that explicit file path with no file returns empty
    var patterns = [_][]const u8{"/nonexistent/path/to/file.zig"};
    var results = try expander.expandPatternsWithInfo(&patterns);
    defer {
        for (results.items) |*result| {
            for (result.files.items) |path| {
                allocator.free(path);
            }
            result.files.deinit();
        }
        results.deinit();
    }
    
    try std.testing.expect(results.items.len == 1);
    try std.testing.expect(results.items[0].files.items.len == 0);
    try std.testing.expect(results.items[0].is_glob == false);
}

test "config flag parsing" {
    const allocator = std.testing.allocator;
    
    // Test allow-empty-glob flag
    var args1 = [_][:0]const u8{ "zz", "prompt", "--allow-empty-glob", "file.zig" };
    var config1 = try Config.fromArgs(allocator, &args1);
    defer config1.deinit();
    
    try std.testing.expect(config1.allow_empty_glob == true);
    try std.testing.expect(config1.allow_missing == false);
    try std.testing.expect(config1.prepend_text == null);
    try std.testing.expect(config1.append_text == null);
    
    // Test allow-missing flag
    var args2 = [_][:0]const u8{ "zz", "prompt", "--allow-missing", "file.zig" };
    var config2 = try Config.fromArgs(allocator, &args2);
    defer config2.deinit();
    
    try std.testing.expect(config2.allow_empty_glob == false);
    try std.testing.expect(config2.allow_missing == true);
    
    // Test both flags
    var args3 = [_][:0]const u8{ "zz", "prompt", "--allow-empty-glob", "--allow-missing", "file.zig" };
    var config3 = try Config.fromArgs(allocator, &args3);
    defer config3.deinit();
    
    try std.testing.expect(config3.allow_empty_glob == true);
    try std.testing.expect(config3.allow_missing == true);
    
    // Test default (no flags)
    var args4 = [_][:0]const u8{ "zz", "prompt", "file.zig" };
    var config4 = try Config.fromArgs(allocator, &args4);
    defer config4.deinit();
    
    try std.testing.expect(config4.allow_empty_glob == false);
    try std.testing.expect(config4.allow_missing == false);
}

test "glob pattern detection" {
    // Test glob patterns
    try std.testing.expect(GlobExpander.isGlobPattern("*.zig") == true);
    try std.testing.expect(GlobExpander.isGlobPattern("src/**/*.zig") == true);
    try std.testing.expect(GlobExpander.isGlobPattern("test?.zig") == true);
    try std.testing.expect(GlobExpander.isGlobPattern("*.{zig,txt}") == true);
    
    // Test non-glob patterns
    try std.testing.expect(GlobExpander.isGlobPattern("file.zig") == false);
    try std.testing.expect(GlobExpander.isGlobPattern("src/main.zig") == false);
    try std.testing.expect(GlobExpander.isGlobPattern("/absolute/path.txt") == false);
}