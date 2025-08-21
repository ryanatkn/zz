// Barrel file to import all parser module tests
// Tests for individual components should be in their respective files

test {
    // Import tests from individual parser modules
    // This ensures all test blocks get compiled
    _ = @import("interface.zig");
    _ = @import("recursive.zig");
    _ = @import("structural.zig");
    _ = @import("recovery.zig");
    _ = @import("viewport.zig");
    _ = @import("cache.zig");
    _ = @import("context.zig");
    
    // Also run inline tests in this file
    @import("std").testing.refAllDecls(@This());
}

// Basic smoke test for parser module compilation
test "parser module compiles" {
    const interface = @import("interface.zig");
    const structural = @import("structural.zig");
    
    // Just verify types exist
    _ = interface.ParserInterface;
    _ = structural.Boundary;
}
