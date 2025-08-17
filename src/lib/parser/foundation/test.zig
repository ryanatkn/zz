const std = @import("std");

// Import all foundation modules for testing
test "foundation types" {
    _ = @import("types/span.zig");
    _ = @import("types/predicate.zig");
    _ = @import("types/fact.zig");
    _ = @import("types/token.zig");
}

test "foundation math" {
    _ = @import("math/coordinates.zig");
    _ = @import("math/span_ops.zig");
}