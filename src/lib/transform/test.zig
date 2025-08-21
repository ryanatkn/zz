// Barrel file to import all transform module tests
// Tests for individual components should be in their respective files

test {
    // Import tests from individual transform modules
    // This ensures all test blocks get compiled
    _ = @import("pipeline.zig");
    _ = @import("format.zig");
    _ = @import("extract.zig");
    _ = @import("optimize.zig");
    
    // Also run inline tests in this file
    @import("std").testing.refAllDecls(@This());
}

// Basic smoke test for transform module compilation
test "transform module compiles" {
    const pipeline = @import("pipeline.zig");
    const format = @import("format.zig");
    
    // Just verify types exist
    _ = pipeline.Pipeline;
    _ = pipeline.Transform;
    _ = format.FormatTransform;
}
