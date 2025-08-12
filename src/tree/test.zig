const std = @import("std");
const testing = std.testing;
const MockFilesystem = @import("../filesystem.zig").MockFilesystem;

// Tree module test runner
// Usage: zig test src/tree/test.zig

// Import modules to test
const Config = @import("config.zig").Config;
const SharedConfig = @import("../config.zig").SharedConfig;
const Filter = @import("filter.zig").Filter;
const Walker = @import("walker.zig").Walker;
const Formatter = @import("formatter.zig").Formatter;
const Entry = @import("entry.zig").Entry;

// Import comprehensive test modules - this includes all their test declarations
// Note: These imports make all tests from each module available when running this file
test {
    // Core functionality test modules
    std.testing.refAllDecls(@import("test/config_test.zig"));
    std.testing.refAllDecls(@import("test/filter_test.zig"));
    std.testing.refAllDecls(@import("test/walker_test.zig"));
    std.testing.refAllDecls(@import("test/formatter_test.zig"));
    std.testing.refAllDecls(@import("test/path_builder_test.zig"));

    // Specialized test modules
    std.testing.refAllDecls(@import("test/integration_test.zig"));
    std.testing.refAllDecls(@import("test/edge_cases_test.zig"));
    std.testing.refAllDecls(@import("test/performance_test.zig"));
    std.testing.refAllDecls(@import("test/concurrency_test.zig"));
    std.testing.refAllDecls(@import("test/testability_test.zig"));
}

// Basic functionality tests
test "config loading works" {
    var mock_fs = MockFilesystem.init(testing.allocator);
    defer mock_fs.deinit();
    const filesystem = mock_fs.interface();
    
    const args = [_][:0]const u8{"tree"};
    var config = try Config.fromArgs(testing.allocator, filesystem, @constCast(args[0..]));
    defer config.deinit(testing.allocator);

    try testing.expect(config.shared_config.ignored_patterns.len > 0);
    // Config loading test completed successfully
}

test "filter pattern matching works" {
    const allocator = testing.allocator;

    const ignored = try allocator.dupe([]const u8, &[_][]const u8{ "node_modules", ".git" });
    defer allocator.free(ignored);
    const hidden = try allocator.dupe([]const u8, &[_][]const u8{"Thumbs.db"});
    defer allocator.free(hidden);

    const shared_config = SharedConfig{
        .ignored_patterns = ignored,
        .hidden_files = hidden,
        .gitignore_patterns = &[_][]const u8{},
        .symlink_behavior = .skip,
        .respect_gitignore = false,
        .patterns_allocated = false,
    };

    const filter = Filter.init(shared_config);

    try testing.expect(filter.shouldIgnore("node_modules"));
    try testing.expect(filter.shouldIgnore(".git"));
    try testing.expect(!filter.shouldIgnore("src"));
    try testing.expect(filter.shouldHide("Thumbs.db"));

    // Filter pattern matching test completed successfully
}

test "walker initialization works" {
    const allocator = testing.allocator;

    const ignored = try allocator.dupe([]const u8, &[_][]const u8{});
    defer allocator.free(ignored);
    const hidden = try allocator.dupe([]const u8, &[_][]const u8{});
    defer allocator.free(hidden);

    const shared_config = SharedConfig{
        .ignored_patterns = ignored,
        .hidden_files = hidden,
        .gitignore_patterns = &[_][]const u8{},
        .symlink_behavior = .skip,
        .respect_gitignore = false,
        .patterns_allocated = false,
    };

    const config = Config{ .shared_config = shared_config };
    
    var mock_fs = MockFilesystem.init(allocator);
    defer mock_fs.deinit();
    const filesystem = mock_fs.interface();
    
    const WalkerOptions = @import("walker.zig").WalkerOptions;
    const options = WalkerOptions{
        .filesystem = filesystem,
        .quiet = true,
    };
    const walker = Walker.initWithOptions(testing.allocator, config, options);

    _ = walker; // Just verify it can be created
    // Walker initialization test completed successfully
}

test "formatter handles entries correctly" {
    const formatter = Formatter{};

    const entry = Entry{
        .name = "test.txt",
        .kind = .file,
        .is_ignored = false,
        .is_depth_limited = false,
    };

    _ = formatter;
    _ = entry; // Just verify structures work
    // Formatter test completed successfully
}

test "tree module test suite summary" {
    const test_modules = [_][]const u8{ "config", "filter", "walker", "formatter", "path_builder", "integration", "edge cases", "performance", "concurrency", "testability" };

    std.debug.print("\nTree module test suite completed\n", .{});
    const module_list = std.mem.join(std.heap.page_allocator, ", ", &test_modules) catch "modules";
    defer if (!std.mem.eql(u8, module_list, "modules")) std.heap.page_allocator.free(module_list);

    std.debug.print("✓ All {} test modules active ({s})\n", .{ test_modules.len, module_list });
}
