// Test barrel for language implementations
const std = @import("std");

test {
    // Language implementations
    _ = @import("json/test.zig");
    _ = @import("zon/test.zig");
}
