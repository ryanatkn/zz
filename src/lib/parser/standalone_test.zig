const std = @import("std");
const testing = std.testing;

// For standalone testing, let's run the parser via the build system
test "parser module compiles" {
    // This test just ensures the parser module compiles correctly
    _ = @import("detailed/parser.zig");
    _ = @import("detailed/context.zig");
    _ = @import("mod.zig");
}
