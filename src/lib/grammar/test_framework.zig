const std = @import("std");
const testing = std.testing;

/// Test framework for grammar and parser testing
/// Provides utilities for testing rule matching, AST generation, and parser behavior

/// Result of attempting to match a rule against input
pub const MatchResult = struct {
    success: bool,
    consumed: usize, // Number of characters consumed
    remaining: []const u8, // Remaining input after match
    captured: ?[]const u8, // Captured text if successful
    
    pub fn init(success: bool, consumed: usize, input: []const u8) MatchResult {
        return .{
            .success = success,
            .consumed = consumed,
            .remaining = if (consumed < input.len) input[consumed..] else "",
            .captured = if (success and consumed > 0) input[0..consumed] else null,
        };
    }
    
    pub fn failure() MatchResult {
        return .{
            .success = false,
            .consumed = 0,
            .remaining = "",
            .captured = null,
        };
    }
};

/// Test context for rule matching
pub const TestContext = struct {
    allocator: std.mem.Allocator,
    input: []const u8,
    position: usize,
    
    pub fn init(allocator: std.mem.Allocator, input: []const u8) TestContext {
        return .{
            .allocator = allocator,
            .input = input,
            .position = 0,
        };
    }
    
    pub fn remaining(self: TestContext) []const u8 {
        if (self.position >= self.input.len) return "";
        return self.input[self.position..];
    }
    
    pub fn advance(self: *TestContext, count: usize) void {
        self.position = @min(self.position + count, self.input.len);
    }
    
    pub fn reset(self: *TestContext) void {
        self.position = 0;
    }
};

/// Test helpers for assertions
pub const TestHelpers = struct {
    /// Assert that a rule matches the expected input
    pub fn expectMatch(result: MatchResult, expected: []const u8) !void {
        try testing.expect(result.success);
        if (result.captured) |captured| {
            try testing.expectEqualStrings(expected, captured);
        } else {
            return error.NoCapture;
        }
    }
    
    /// Assert that a rule fails to match
    pub fn expectNoMatch(result: MatchResult) !void {
        try testing.expect(!result.success);
        try testing.expectEqual(@as(usize, 0), result.consumed);
    }
    
    /// Assert specific consumed count
    pub fn expectConsumed(result: MatchResult, expected: usize) !void {
        try testing.expectEqual(expected, result.consumed);
    }
    
    /// Assert remaining input after match
    pub fn expectRemaining(result: MatchResult, expected: []const u8) !void {
        try testing.expectEqualStrings(expected, result.remaining);
    }
};

/// Simple mock parser for testing
pub const MockParser = struct {
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) MockParser {
        return .{ .allocator = allocator };
    }
    
    pub fn deinit(self: *MockParser) void {
        _ = self;
    }
};

/// Test utilities for performance measurement
pub const PerfTest = struct {
    name: []const u8,
    start_time: i64,
    
    pub fn begin(name: []const u8) PerfTest {
        return .{
            .name = name,
            .start_time = @intCast(std.time.nanoTimestamp()),
        };
    }
    
    pub fn end(self: PerfTest) void {
        const elapsed = std.time.nanoTimestamp() - self.start_time;
        const ms = @as(f64, @floatFromInt(elapsed)) / 1_000_000.0;
        std.debug.print("{s}: {d:.3}ms\n", .{ self.name, ms });
    }
};

// Test the test framework itself
test "TestContext basic operations" {
    const allocator = testing.allocator;
    var ctx = TestContext.init(allocator, "hello world");
    
    try testing.expectEqualStrings("hello world", ctx.remaining());
    try testing.expectEqual(@as(usize, 0), ctx.position);
    
    ctx.advance(5);
    try testing.expectEqualStrings(" world", ctx.remaining());
    try testing.expectEqual(@as(usize, 5), ctx.position);
    
    ctx.reset();
    try testing.expectEqualStrings("hello world", ctx.remaining());
    try testing.expectEqual(@as(usize, 0), ctx.position);
}

test "MatchResult creation" {
    const input = "hello world";
    
    // Successful match
    const success = MatchResult.init(true, 5, input);
    try testing.expect(success.success);
    try testing.expectEqual(@as(usize, 5), success.consumed);
    try testing.expectEqualStrings(" world", success.remaining);
    try testing.expectEqualStrings("hello", success.captured.?);
    
    // Failed match
    const failure = MatchResult.failure();
    try testing.expect(!failure.success);
    try testing.expectEqual(@as(usize, 0), failure.consumed);
    try testing.expectEqual(@as(?[]const u8, null), failure.captured);
}

test "TestHelpers assertions" {
    const input = "test input";
    
    // Test successful match
    const match = MatchResult.init(true, 4, input);
    try TestHelpers.expectMatch(match, "test");
    try TestHelpers.expectConsumed(match, 4);
    try TestHelpers.expectRemaining(match, " input");
    
    // Test failed match
    const no_match = MatchResult.failure();
    try TestHelpers.expectNoMatch(no_match);
}