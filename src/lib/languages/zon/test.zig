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

    // Edge cases and specialized tests
    _ = @import("test_edge_cases.zig");

    // Stream tests if they exist
    _ = @import("test_stream.zig");

    // Keep existing token tests if they exist
    _ = @import("tokens.zig");

    // Include modules with embedded tests
    _ = @import("lexer.zig");
    _ = @import("parser.zig");
    _ = @import("formatter.zig");
    _ = @import("analyzer.zig");
    _ = @import("stream_lexer.zig");
    _ = @import("stream_token.zig");
    _ = @import("stream_format.zig");
    _ = @import("transform.zig");
    _ = @import("serializer.zig");
}
