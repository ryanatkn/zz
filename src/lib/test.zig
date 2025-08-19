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
    // JSON language implementation tests
    _ = @import("languages/json/test.zig");
    // Transform and serialization tests
    _ = @import("transform/test.zig");
    // Core module tests - only include files that compile
    _ = @import("core/datetime_test.zig");
    // Working utility tests (verified to compile)
    _ = @import("text/escape.zig");
    _ = @import("text/quote.zig");
    _ = @import("text/indent.zig");
    _ = @import("parallel.zig");
    _ = @import("args.zig");
    // Language pattern tests (safe to import)
    _ = @import("languages/typescript/patterns.zig");
    _ = @import("languages/zig/patterns.zig");
    _ = @import("languages/css/patterns.zig");
    _ = @import("languages/html/patterns.zig");
    // Comprehensive fixture-based tests - DELETED during cleanup  
    // _ = @import("test/fixture_loader.zig");
    // Fixture runner tests (with defensive error handling and logging)
    _ = @import("test/fixture_runner.zig");
}
