// Test runner for the stream-first architecture modules
const std = @import("std");

// Import all test files
test {
    // Phase 1 modules (Core Infrastructure)
    _ = @import("stream/test.zig");
    _ = @import("span/test.zig");
    _ = @import("fact/test.zig");
    _ = @import("memory/arena_pool.zig");
    _ = @import("memory/atom_table.zig");
    
    // Phase 2 modules (Token Integration)
    _ = @import("token/test.zig");
    // Lexer bridge removed in Phase 6
    _ = @import("cache/test.zig");     // NEW: Fact cache module
    
    // Language-specific token tests
    _ = @import("languages/json/stream_token.zig");
    _ = @import("languages/zon/stream_token.zig");
    _ = @import("languages/stream_token_example.zig");
    
    // Phase 3: Direct stream lexers
    _ = @import("languages/json/test_stream.zig");
    _ = @import("languages/zon/test_stream.zig");
    
    // Phase 3 modules (Query Engine)
    _ = @import("query/test.zig");
    
    // Phase 5: DirectStream migration tests
    _ = @import("stream/test_direct_stream.zig");
    
    // Phase 6: Stream-first formatters and extractors
    _ = @import("languages/json/stream_format.zig");
    _ = @import("languages/zon/stream_format.zig");
    _ = @import("stream/format.zig");
    _ = @import("stream/extract.zig");
}
