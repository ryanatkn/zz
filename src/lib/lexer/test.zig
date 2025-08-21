// Barrel file to import all lexer module tests
// Tests for individual components should be in their respective files

test {
    // Import tests from individual lexer modules
    // This ensures all test blocks get compiled
    _ = @import("interface.zig");
    _ = @import("streaming.zig");
    _ = @import("buffer.zig");
    _ = @import("context.zig");
    _ = @import("incremental.zig");
    
    // Also run inline tests in this file
    @import("std").testing.refAllDecls(@This());
}

// Basic smoke test for lexer module compilation
test "lexer module compiles" {
    const interface = @import("interface.zig");
    const streaming = @import("streaming.zig");
    
    // Just verify types exist
    _ = interface.LexerInterface;
    _ = streaming.TokenStream;
    _ = streaming.StreamVTable;
}
