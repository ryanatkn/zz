// Main test runner for the entire zz project
// Usage: zig test src/test.zig

const std = @import("std");
const test_helpers = @import("test_helpers.zig");

// Initialize test runner with summary
test "zz test suite initialization" {
    test_helpers.setTestModule("ZZ Project");
    test_helpers.TestRunner.resetStats();
}

// Import all test modules - this ensures their test blocks are included
test {
    // Reference main modules to include their test blocks
    std.testing.refAllDeclsRecursive(@import("main.zig"));
    std.testing.refAllDeclsRecursive(@import("config.zig"));
}

// Import tree tests
test {
    std.testing.refAllDeclsRecursive(@import("tree/test.zig"));
}

// Import prompt tests
test {
    std.testing.refAllDeclsRecursive(@import("prompt/test.zig"));
}

// Import patterns tests
test {
    std.testing.refAllDeclsRecursive(@import("patterns/test.zig"));
}

// Import CLI tests
test {
    std.testing.refAllDeclsRecursive(@import("cli/test.zig"));
}

// Import benchmark tests
test {
    std.testing.refAllDeclsRecursive(@import("benchmark/test.zig"));
}

// Print final test summary
test "zz test suite summary" {
    test_helpers.TestRunner.printSummary();
}
