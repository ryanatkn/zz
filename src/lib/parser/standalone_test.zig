const std = @import("std");
const testing = std.testing;

// For standalone testing, let's run the parser via the build system
test "parser module compiles" {
    // This test just ensures the parser module compiles correctly
    _ = @import("parser.zig");
    _ = @import("context.zig");
    _ = @import("mod.zig");
}