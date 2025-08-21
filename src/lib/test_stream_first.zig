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
    _ = @import("lexer/test.zig");     // NEW: Lexer bridge module
    _ = @import("cache/test.zig");     // NEW: Fact cache module
    
    // Language-specific token tests
    _ = @import("languages/json/stream_token.zig");
    _ = @import("languages/zon/stream_token.zig");
    _ = @import("languages/stream_token_example.zig");
    
    // TODO: Phase 3 modules (Query Engine)
    // _ = @import("query/test.zig");
    
    // TODO: Phase 4 modules (Language Adapters)
    // _ = @import("adapter/test.zig");
}
