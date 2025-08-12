const std = @import("std");

test {
    // Extracted tests
    _ = @import("test/matcher_test.zig");
    _ = @import("test/gitignore_test.zig");
}
