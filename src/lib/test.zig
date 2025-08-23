// Unified test runner for all lib modules
test {
    // Single file imports (from original test.zig)
    _ = @import("args.zig");
    _ = @import("parallel.zig");
    _ = @import("node_types.zig");

    // Progressive Parser Infrastructure (Phase 2)
    _ = @import("lexer/test.zig"); // NEW: Lexer infrastructure
    _ = @import("parser/test.zig"); // NEW: Parser infrastructure
    _ = @import("transform/test.zig"); // NEW: Transform pipelines
    _ = @import("token/test.zig"); // Updated token module

    // Core Infrastructure
    _ = @import("span/test.zig");
    _ = @import("fact/test.zig");
    _ = @import("stream/test.zig");
    _ = @import("cache/test.zig"); // Fact caching (added from progressive)
    _ = @import("memory/test.zig");
    _ = @import("query/test.zig"); // Query engine (added from progressive)

    // Language Support
    _ = @import("languages/test.zig");
    _ = @import("languages/json/test.zig");
    _ = @import("languages/zon/test.zig");
    // Language test files removed - components moved to memory/language_strategies and parser/patterns

    // Utilities
    _ = @import("char/test.zig");
    _ = @import("core/test.zig");
    _ = @import("text/test.zig");
    _ = @import("patterns/test.zig");
    _ = @import("filesystem/test.zig");
    // Grammar module deleted - tests removed with module
    // _ = @import("grammar/test.zig"); // TODO: Restore when grammar system is rebuilt

    // Legacy/Migration (kept for reference, not imported)
    // _ = @import("parser_old/test.zig");
    // _ = @import("transform_old/test.zig");

    // Development Support
    _ = @import("benchmark/test.zig"); // Re-enabled: prefer failed tests with TODOs over disabled tests
    _ = @import("terminal/test.zig");
    _ = @import("execution/test.zig");
    _ = @import("deps/test.zig");
    _ = @import("test/fixture_runner.zig");
    _ = @import("test/performance_gates.zig");

    // Additional modules with embedded tests
    _ = @import("cache/mod.zig");
    _ = @import("query/mod.zig");
}
