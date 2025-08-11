// Main test runner for the entire zz project
// Usage: zig test src/test.zig

const std = @import("std");

test {
    // Import all modules with tests - this will run all their test blocks
    std.testing.refAllDeclsRecursive(@import("main.zig"));
    std.testing.refAllDeclsRecursive(@import("cli/args.zig"));
    std.testing.refAllDeclsRecursive(@import("tree/test.zig"));
    std.testing.refAllDeclsRecursive(@import("prompt/test.zig"));
}
