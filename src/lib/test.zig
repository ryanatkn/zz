// Test runner for lib module
const std = @import("std");
const testing = std.testing;

test {
    // Parser tests
    _ = @import("test/parser_test.zig");
    // Extraction tests for all languages
    _ = @import("test/extraction_test.zig");
    // Cached formatter tests
    _ = @import("test/cached_formatter_test.zig");
    // ZON parser utility tests
    _ = @import("parsing/zon_parser.zig");
    // Comprehensive fixture-based tests
    _ = @import("test/fixture_loader.zig");
    // Fixture runner tests (with defensive error handling and logging)
    _ = @import("test/fixture_runner.zig");
}
