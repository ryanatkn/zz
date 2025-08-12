const std = @import("std");

test {
    _ = @import("fence.zig");
    _ = @import("main.zig");

    // Extracted tests
    _ = @import("test/builder_test.zig");
    _ = @import("test/config_test.zig");
    _ = @import("test/glob_test.zig");

    // Comprehensive test suite
    _ = @import("test/test.zig");
}
