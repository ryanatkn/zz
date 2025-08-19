// Main test runner for the entire zz project
// Usage: zig test src/test.zig
//
// IMPORTANT: Zig requires manual test inclusion - there is no automatic test discovery.
// When adding new test files, you must explicitly import them in the appropriate test runner:
//   - Add module-level tests to src/lib/test.zig (for lib/ directory)
//   - Add top-level tests here (for other directories like cli/, tree/, prompt/, etc.)
//   - Use `_ = @import("path/to/test.zig");` syntax to include test blocks
// 
// To find missing tests: grep -r "^test " src/ and verify each file is imported somewhere

const std = @import("std");

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

// Import lib tests
test {
    std.testing.refAllDeclsRecursive(@import("lib/test/helpers.zig"));
}

// Import CLI tests
test {
    std.testing.refAllDeclsRecursive(@import("cli/test.zig"));
}

// Import benchmark tests
test {
    std.testing.refAllDeclsRecursive(@import("benchmark/test.zig"));
}

// Import lib tests (including parser tests)
test {
    std.testing.refAllDeclsRecursive(@import("lib/test.zig"));
}

// Import format tests
test {
    std.testing.refAllDeclsRecursive(@import("format/test.zig"));
}

// Import deps tests
test {
    std.testing.refAllDeclsRecursive(@import("lib/deps/test.zig"));
}

// Import echo tests
test {
    std.testing.refAllDeclsRecursive(@import("echo/test.zig"));
}
