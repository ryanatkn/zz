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
    // Legacy tests
    _ = @import("test/parser_test.zig");
    // Cached formatter tests
    _ = @import("test/cached_formatter_test.zig");
    // ZON parser utility tests
    _ = @import("parsing/zon_parser.zig");
    // Comprehensive fixture-based tests
    _ = @import("test/fixture_loader.zig");
    // Fixture runner tests (with defensive error handling and logging)
    _ = @import("test/fixture_runner.zig");
    // Core module tests
    _ = @import("core/datetime_test.zig");
}
