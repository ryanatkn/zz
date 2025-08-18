// Test runner for dependency management modules
const std = @import("std");

// Import all deps modules to test
test {
    std.testing.refAllDeclsRecursive(@import("config.zig"));
    std.testing.refAllDeclsRecursive(@import("versioning.zig"));
    std.testing.refAllDeclsRecursive(@import("operations.zig"));
    std.testing.refAllDeclsRecursive(@import("lock.zig"));
    std.testing.refAllDeclsRecursive(@import("../core/git.zig"));
    std.testing.refAllDeclsRecursive(@import("manager.zig"));
    std.testing.refAllDeclsRecursive(@import("docs/mod.zig"));
}

// Import all focused test modules
test {
    _ = @import("manager_test.zig");
    _ = @import("config_test.zig");
    _ = @import("versioning_test.zig");
    _ = @import("path_matcher_test.zig");
    _ = @import("pattern_validator_test.zig");
    _ = @import("integration_test.zig");
    _ = @import("docs_test.zig");
    _ = @import("integration_docs_test.zig");
}
