const std = @import("std");

test {
    _ = @import("fence.zig");
    _ = @import("glob.zig");
    _ = @import("builder.zig");
    _ = @import("config.zig");
    _ = @import("main.zig");
    _ = @import("prompt_test.zig");
    _ = @import("error_test.zig");
    
    // Comprehensive test suite
    _ = @import("test/test.zig");
}