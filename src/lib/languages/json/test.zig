const std = @import("std");

// Import all modular test files
test {
    // Core component tests
    _ = @import("test_lexer.zig");
    _ = @import("test_parser.zig");
    _ = @import("test_formatter.zig");
    _ = @import("test_linter.zig");
    _ = @import("test_analyzer.zig");

    // Integration and performance tests
    _ = @import("test_integration.zig");
    _ = @import("test_performance.zig");

    // Existing specialized test files
    _ = @import("test_rfc8259_compliance.zig");
    _ = @import("tokens.zig");
}
