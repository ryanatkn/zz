// Test runner for the progressive parser architecture modules
const std = @import("std");

// Import all test files
test {
    // Phase 1 Infrastructure (New Progressive Parser Modules)
    _ = @import("lexer/test.zig"); // NEW: Lexer infrastructure
    _ = @import("parser/test.zig"); // NEW: Parser infrastructure
    _ = @import("transform/test.zig"); // NEW: Transform pipelines

    // Core Infrastructure (Existing)
    _ = @import("token/test.zig"); // Updated token module
    _ = @import("span/test.zig"); // Span primitives
    _ = @import("fact/test.zig"); // Fact system
    _ = @import("stream/test.zig"); // Stream infrastructure
    _ = @import("cache/test.zig"); // Fact caching
    _ = @import("memory/test.zig"); // Memory management

    // Language Implementations (Integration Testing)
    _ = @import("languages/json/test.zig"); // JSON language support
    _ = @import("languages/zon/test.zig"); // ZON language support
    _ = @import("languages/test.zig"); // Language registry

    // Additional Core Modules
    _ = @import("core/test.zig"); // Core utilities
    _ = @import("char/test.zig"); // Character utilities
    _ = @import("text/test.zig"); // Text processing
    _ = @import("patterns/test.zig"); // Pattern matching
    _ = @import("filesystem/test.zig"); // Filesystem abstraction

    // Legacy Comparison (Phase 3 Migration Tests)
    _ = @import("transform_old/test.zig"); // Old transform for comparison
    _ = @import("ast_old/test.zig"); // Old AST for comparison
    _ = @import("parser_old/test.zig"); // Old parser for comparison

    // Query and Advanced Features (Phase 3)
    _ = @import("query/test.zig"); // Query engine
    _ = @import("grammar/test.zig"); // Grammar system

    // Development Support
    _ = @import("benchmark/test.zig"); // Performance testing
    _ = @import("terminal/test.zig"); // Terminal utilities
    _ = @import("execution/test.zig"); // Execution utilities
    _ = @import("deps/test.zig"); // Dependency management
}
