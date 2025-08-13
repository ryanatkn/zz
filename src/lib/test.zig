// Test runner for lib module
const std = @import("std");
const testing = std.testing;

test {
    // Parser tests
    _ = @import("test/parser_test.zig");
}