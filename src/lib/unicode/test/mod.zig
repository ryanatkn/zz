/// Unicode Module Test Suite
///
/// Comprehensive tests for Unicode validation, escape sequences, and UTF-8 handling.
const std = @import("std");

// Import all test files
test {
    // Comprehensive test suites
    _ = @import("integration.zig");
    _ = @import("security.zig");
    _ = @import("rfc_compliance.zig");
}

// Re-export the original tests from individual modules
comptime {
    _ = @import("../validation.zig");
    _ = @import("../codepoint.zig");
    _ = @import("../escape.zig");
    _ = @import("../utf8.zig");
    _ = @import("../mod.zig");
}
