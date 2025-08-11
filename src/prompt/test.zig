const std = @import("std");

test {
    _ = @import("fence.zig");
    _ = @import("glob.zig");
    _ = @import("builder.zig");
    _ = @import("config.zig");
    _ = @import("main.zig");
    
    // Comprehensive test suite
    _ = @import("test/test.zig");
}