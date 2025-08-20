// Test runner for the stream-first architecture modules
const std = @import("std");

// Import all test files
test {
    _ = @import("stream/test.zig");
    _ = @import("span/test.zig");
    _ = @import("fact/test.zig");
}