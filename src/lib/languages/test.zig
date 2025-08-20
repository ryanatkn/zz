// Test barrel for language implementations
const std = @import("std");

test {
    // Language implementations
    _ = @import("json/test.zig");
    _ = @import("zon/test.zig");
    
    // Language-specific tokens
    _ = @import("json/tokens.zig");
    _ = @import("zon/tokens.zig");
    
    // Common utilities
    _ = @import("common/token_base.zig");
}