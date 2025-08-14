const std = @import("std");
const testing = std.testing;
const test_helpers = @import("../test_helpers.zig");

// Prompt module test runner
// Usage: zig test src/prompt/test.zig

// Import modules to test
const Config = @import("config.zig").Config;
const SharedConfig = @import("../config.zig").SharedConfig;
const PromptBuilder = @import("builder.zig").PromptBuilder;
const GlobExpander = @import("glob.zig").GlobExpander;

// Prompt module test tracking using TestRunner

// Initialize prompt module testing
test "prompt module initialization" {
    test_helpers.TestRunner.init();
    test_helpers.TestRunner.setModule("Prompt");
}

// Import comprehensive test modules - this includes all their test declarations
// Note: These imports make all tests from each module available when running this file
test {
    // Core functionality test modules
    std.testing.refAllDecls(@import("test/builder_test.zig"));
    std.testing.refAllDecls(@import("test/config_test.zig"));
    std.testing.refAllDecls(@import("test/glob_test.zig"));
    std.testing.refAllDecls(@import("test/edge_cases_test.zig"));
    std.testing.refAllDecls(@import("test/special_chars_test.zig"));
    std.testing.refAllDecls(@import("test/symlink_test.zig"));
    std.testing.refAllDecls(@import("test/large_files_test.zig"));
    std.testing.refAllDecls(@import("test/flag_combinations_test.zig"));
    std.testing.refAllDecls(@import("test/file_content_test.zig"));
    std.testing.refAllDecls(@import("test/security_test.zig"));
    std.testing.refAllDecls(@import("test/glob_edge_test.zig"));
    std.testing.refAllDecls(@import("test/nested_braces_integration_test.zig"));
    std.testing.refAllDecls(@import("test/explicit_ignore_test.zig"));
    std.testing.refAllDecls(@import("test/directory_support_test.zig"));
    // Extraction tests are now in lib/test/extraction_test.zig
}

// Basic functionality tests
test "config loading works" {
    var ctx = test_helpers.MockTestContext.init(testing.allocator);
    defer ctx.deinit();

    const args = [_][:0]const u8{ "prompt", "test.zig" };
    var config = try Config.fromArgs(testing.allocator, ctx.filesystem, @constCast(args[0..]));
    defer config.deinit();

    try testing.expect(config.shared_config.ignored_patterns.len > 0);
}

test "prompt builder initialization works" {
    var ctx = test_helpers.MockTestContext.init(testing.allocator);
    defer ctx.deinit();

    const extraction_flags = @import("../lib/language/flags.zig").ExtractionFlags{};
    var builder = PromptBuilder.init(testing.allocator, ctx.filesystem, extraction_flags);
    defer builder.deinit();

    try builder.addText("Test content");
    try testing.expect(builder.lines.items.len > 0);
}

test "glob expander initialization works" {
    var ctx = test_helpers.MockTestContext.init(testing.allocator);
    defer ctx.deinit();

    // Test pattern detection
    try testing.expect(GlobExpander.isGlobPattern("*.zig") == true);
    try testing.expect(GlobExpander.isGlobPattern("main.zig") == false);
}

test "prompt module test summary" {
    test_helpers.TestRunner.printSummary();
}
