const std = @import("std");

// Import all test modules
comptime {
    // Integration tests
    _ = @import("test/integration_test.zig");

    // Configuration loading tests
    _ = @import("test/config_test.zig");
}

// Test metadata for summary
pub const test_modules = [_][]const u8{
    "integration_test",
    "config_test",
};

test "format module test summary" {
    std.debug.print("\n=== Format Module Tests ===\n", .{});

    for (test_modules) |module| {
        std.debug.print("✅ {s}\n", .{module});
    }

    std.debug.print("\nTotal test modules: {}\n", .{test_modules.len});
}
