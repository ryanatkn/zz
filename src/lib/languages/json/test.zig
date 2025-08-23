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
    _ = @import("test_stream.zig");
    _ = @import("tokens.zig");

    // Include modules with embedded tests
    _ = @import("lexer.zig");
    _ = @import("parser.zig");
    _ = @import("formatter.zig");
    _ = @import("analyzer.zig");
    _ = @import("linter.zig");
    _ = @import("stream_lexer.zig");
    _ = @import("stream_token.zig");
    _ = @import("stream_format.zig");
    _ = @import("transform.zig");
    _ = @import("patterns.zig");
    // node_pool.zig and bulk_allocator.zig removed - functionality in new memory system
    _ = @import("streaming_token_buffer.zig");
    _ = @import("test_boundary_lexer.zig");
    _ = @import("mod.zig");
}
