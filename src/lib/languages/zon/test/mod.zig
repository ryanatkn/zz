const std = @import("std");

// Import all test files (now in test/ subdirectory)
test {
    // Core component tests in test/ directory
    _ = @import("lexer.zig");
    _ = @import("parser.zig");
    _ = @import("formatter.zig");
    _ = @import("linter.zig");
    _ = @import("analyzer.zig");

    // Integration and performance tests
    _ = @import("integration.zig");
    _ = @import("performance.zig");

    // Specialized test files
    _ = @import("stream.zig");
    _ = @import("escape_sequences.zig");
    _ = @import("edge_cases.zig");
    _ = @import("spec_compliance.zig");
    _ = @import("boundary_lexer.zig");

    // Include parent modules with embedded tests (split modules)
    _ = @import("../parser/mod.zig"); // Bridge file with tests
    _ = @import("../parser/core.zig"); // Core parser tests

    _ = @import("../analyzer/mod.zig"); // Bridge file with tests
    _ = @import("../analyzer/core.zig"); // Core analyzer tests

    _ = @import("../lexer/mod.zig"); // Bridge file with tests
    _ = @import("../lexer/core.zig"); // Core lexer tests

    _ = @import("../format/mod.zig"); // Bridge file with tests
    _ = @import("../format/core.zig"); // Core formatter tests
    _ = @import("../format/stream.zig"); // Stream formatter tests

    _ = @import("../linter/mod.zig"); // Bridge file with tests
    _ = @import("../linter/core.zig"); // Core linter tests

    _ = @import("../ast/mod.zig"); // Bridge file with tests
    _ = @import("../ast/nodes.zig"); // AST node tests
    _ = @import("../ast/converter.zig"); // AST converter tests

    _ = @import("../token/mod.zig"); // Bridge file with tests
    _ = @import("../token/types.zig"); // Token types tests

    _ = @import("../transform/mod.zig"); // Bridge file with tests
    _ = @import("../transform/pipeline.zig"); // Transform pipeline tests
    _ = @import("../transform/serializer.zig"); // Serializer tests
}
