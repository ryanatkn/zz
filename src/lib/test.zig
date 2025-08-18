// Test runner for lib module
const std = @import("std");
const testing = std.testing;

// Export modules for tests
pub const grammar = @import("grammar/mod.zig");
pub const parser = @import("parser/mod.zig");

test {
    // Grammar tests
    _ = @import("grammar/grammar_test.zig");
    // Parser tests
    _ = @import("parser/test.zig");
    // Legacy tests - DELETED during cleanup
    // _ = @import("test/parser_test.zig");
    // ZON language implementation tests
    _ = @import("languages/zon/test.zig");
    // Comprehensive fixture-based tests - DELETED during cleanup  
    // _ = @import("test/fixture_loader.zig");
    // Fixture runner tests (with defensive error handling and logging)
    _ = @import("test/fixture_runner.zig");
    // Core module tests
    _ = @import("core/datetime_test.zig");
}
