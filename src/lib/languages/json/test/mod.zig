const std = @import("std");

// Import all test files (now in test/ subdirectory)
test {
    // Core component tests in test/ directory
    _ = @import("lexer.zig");
    _ = @import("parser.zig");
    _ = @import("formatter.zig");
    _ = @import("linter.zig");
    _ = @import("analyzer.zig"); // moved from test_analyzer.zig

    // Integration and performance tests
    _ = @import("integration.zig");
    _ = @import("performance.zig");

    // Specialized test files
    _ = @import("rfc8259_compliance.zig");
    _ = @import("stream.zig");
    _ = @import("boundary_lexer.zig");
    _ = @import("escape_sequences.zig");

    // Include parent modules with embedded tests (split modules)
    _ = @import("../parser/mod.zig"); // Bridge file with tests
    _ = @import("../parser/core.zig"); // Core parser tests
    _ = @import("../parser/values.zig"); // Value parsing tests

    _ = @import("../analyzer/mod.zig"); // Bridge file with tests
    _ = @import("../analyzer/core.zig"); // Core analyzer tests
    _ = @import("../analyzer/schema.zig"); // Schema analysis tests

    _ = @import("../linter/mod.zig"); // Bridge file with tests
    _ = @import("../linter/core.zig"); // Core linter tests
    _ = @import("../linter/rules/strings.zig"); // String rule tests

    // Other modules with embedded tests
    _ = @import("../format/mod.zig");
    _ = @import("../lexer/core.zig");
    _ = @import("../token/mod.zig");
    _ = @import("../format/stream.zig");
    _ = @import("../transform/mod.zig");
    _ = @import("../token/buffer.zig");
    _ = @import("../mod.zig");
}
