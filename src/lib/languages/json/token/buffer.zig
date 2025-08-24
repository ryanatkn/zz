/// Dynamic token buffer for handling tokens that span 4KB boundaries
/// Solves the streaming lexer boundary issue with minimal performance impact
const std = @import("std");
const Span = @import("../../../span/mod.zig").Span;

/// Token state for tracking incomplete tokens across buffer boundaries
pub const TokenState = enum {
    none, // No incomplete token
    in_string, // In the middle of scanning a string
    in_number, // In the middle of scanning a number
    in_keyword, // In the middle of scanning true/false/null
    in_comment, // In the middle of scanning a comment
};

/// Dynamic buffer for incomplete tokens that span chunk boundaries
pub const TokenBuffer = struct {
    allocator: std.mem.Allocator,

    // Token continuation state
    state: TokenState,
    start_position: u32,
    start_line: u32,
    start_column: u32,

    // Dynamic buffer for partial token content
    buffer: std.ArrayList(u8),

    // String-specific state
    has_escapes: bool,
    found_closing_quote: bool,

    // Number-specific state
    is_float: bool,
    is_negative: bool,
    is_scientific: bool,

    pub fn init(allocator: std.mem.Allocator) TokenBuffer {
        return TokenBuffer{
            .allocator = allocator,
            .state = .none,
            .start_position = 0,
            .start_line = 1,
            .start_column = 1,
            .buffer = std.ArrayList(u8).init(allocator),
            .has_escapes = false,
            .found_closing_quote = false,
            .is_float = false,
            .is_negative = false,
            .is_scientific = false,
        };
    }

    pub fn deinit(self: *TokenBuffer) void {
        self.buffer.deinit();
    }

    /// Start accumulating a new token
    pub fn startToken(self: *TokenBuffer, token_state: TokenState, position: u32, line: u32, column: u32) !void {
        self.state = token_state;
        self.start_position = position;
        self.start_line = line;
        self.start_column = column;
        self.buffer.clearRetainingCapacity();

        // Reset state flags
        self.has_escapes = false;
        self.found_closing_quote = false;
        self.is_float = false;
        self.is_negative = false;
        self.is_scientific = false;
    }

    /// Add characters to the current token buffer
    pub fn appendChar(self: *TokenBuffer, char: u8) !void {
        try self.buffer.append(char);
    }

    /// Add string slice to the current token buffer
    pub fn appendSlice(self: *TokenBuffer, slice: []const u8) !void {
        try self.buffer.appendSlice(slice);
    }

    /// Check if we're currently accumulating a token
    pub fn hasIncompleteToken(self: TokenBuffer) bool {
        return self.state != .none;
    }

    /// Get the current accumulated token content
    pub fn getContent(self: TokenBuffer) []const u8 {
        return self.buffer.items;
    }

    /// Complete the current token and reset state
    pub fn completeToken(self: *TokenBuffer) TokenCompletion {
        const completion = TokenCompletion{
            .state = self.state,
            .start_position = self.start_position,
            .start_line = self.start_line,
            .start_column = self.start_column,
            .content = self.buffer.items,
            .has_escapes = self.has_escapes,
            .found_closing_quote = self.found_closing_quote,
            .is_float = self.is_float,
            .is_negative = self.is_negative,
            .is_scientific = self.is_scientific,
        };

        self.state = .none;
        return completion;
    }

    /// Set string-specific flags
    pub fn setStringFlags(self: *TokenBuffer, has_escapes: bool, found_closing: bool) void {
        self.has_escapes = has_escapes;
        self.found_closing_quote = found_closing;
    }

    /// Set number-specific flags
    pub fn setNumberFlags(self: *TokenBuffer, is_float: bool, is_negative: bool, is_scientific: bool) void {
        self.is_float = is_float;
        self.is_negative = is_negative;
        self.is_scientific = is_scientific;
    }

    /// Estimate memory usage for monitoring
    pub fn getMemoryUsage(self: TokenBuffer) usize {
        return self.buffer.capacity + @sizeOf(TokenBuffer);
    }
};

/// Result of completing a token from the buffer
pub const TokenCompletion = struct {
    state: TokenState,
    start_position: u32,
    start_line: u32,
    start_column: u32,
    content: []const u8,

    // String flags
    has_escapes: bool,
    found_closing_quote: bool,

    // Number flags
    is_float: bool,
    is_negative: bool,
    is_scientific: bool,
};

/// Helper for testing boundary conditions
pub const BoundaryTester = struct {
    /// Create a test case where a JSON string spans multiple chunks
    pub fn createBoundaryString(allocator: std.mem.Allocator, chunk_size: usize) ![]u8 {
        // Create a string that's guaranteed to span a boundary
        const boundary_string = "Hello World From Across The Boundary - This Is A Very Long String That Should Definitely Cross Boundaries";

        var result = std.ArrayList(u8).init(allocator);
        try result.appendSlice("{\"data\":\"");

        // Fill with enough content to guarantee size > chunk_size
        const min_padding = chunk_size + 100; // Ensure we exceed chunk_size by at least 100 bytes

        var i: usize = 0;
        while (i < min_padding) : (i += 1) {
            try result.append('x');
        }

        try result.appendSlice(boundary_string);
        try result.appendSlice("\"}");

        return result.toOwnedSlice();
    }

    /// Create a test case where a number spans a boundary
    pub fn createBoundaryNumber(allocator: std.mem.Allocator, chunk_size: usize) ![]u8 {
        // Create JSON with a long number that spans boundary
        const boundary_number = "123456789.987654321e-10";

        var result = std.ArrayList(u8).init(allocator);
        try result.appendSlice("{\"data\":\"");

        // Fill with enough content to guarantee size > chunk_size
        const min_padding = chunk_size + 100; // Ensure we exceed chunk_size by at least 100 bytes
        var i: usize = 0;
        while (i < min_padding) : (i += 1) {
            try result.append('x');
        }

        try result.appendSlice("\",\"number\":");
        try result.appendSlice(boundary_number);
        try result.appendSlice("}");

        return result.toOwnedSlice();
    }
};

test "TokenBuffer basic operations" {
    const testing = std.testing;

    var buffer = TokenBuffer.init(testing.allocator);
    defer buffer.deinit();

    // Start a string token
    try buffer.startToken(.in_string, 100, 1, 50);
    try testing.expect(buffer.hasIncompleteToken());
    try testing.expectEqual(TokenState.in_string, buffer.state);

    // Add some content
    try buffer.appendSlice("Hello World");
    try testing.expectEqualStrings("Hello World", buffer.getContent());

    // Complete the token
    const completion = buffer.completeToken();
    try testing.expectEqual(TokenState.in_string, completion.state);
    try testing.expectEqualStrings("Hello World", completion.content);
    try testing.expect(!buffer.hasIncompleteToken());
}

test "TokenBuffer boundary string test" {
    const testing = std.testing;

    const boundary_json = try BoundaryTester.createBoundaryString(testing.allocator, 4096);
    defer testing.allocator.free(boundary_json);

    // Should contain a string that would span a 4KB boundary
    try testing.expect(boundary_json.len > 4096);
    try testing.expect(std.mem.indexOf(u8, boundary_json, "Hello World From Across") != null);
}

test "TokenBuffer memory efficiency" {
    const testing = std.testing;

    var buffer = TokenBuffer.init(testing.allocator);
    defer buffer.deinit();

    // Test with various token sizes
    const test_sizes = [_]usize{ 10, 100, 1000, 10000 };

    for (test_sizes) |size| {
        try buffer.startToken(.in_string, 0, 1, 1);

        // Fill with test data
        var i: usize = 0;
        while (i < size) : (i += 1) {
            try buffer.appendChar('x');
        }

        try testing.expectEqual(size, buffer.getContent().len);

        // Memory usage should be reasonable (buffer + overhead)
        const memory_usage = buffer.getMemoryUsage();
        try testing.expect(memory_usage >= size);

        // ArrayList can grow significantly due to power-of-2 growth strategy
        // For small sizes, overhead can be very high (128 byte min capacity for small ArrayList)
        // For large sizes, allow reasonable growth factors
        const min_capacity = 128; // Typical ArrayList minimum capacity
        const max_expected = @max(min_capacity + @sizeOf(TokenBuffer), size * 4 + @sizeOf(TokenBuffer));
        try testing.expect(memory_usage <= max_expected);

        _ = buffer.completeToken();
    }
}
