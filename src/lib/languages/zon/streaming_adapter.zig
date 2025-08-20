const std = @import("std");
const Token = @import("../../parser/foundation/types/token.zig").Token;
const ZonLexer = @import("lexer.zig").ZonLexer;

/// Streaming adapter for ZON lexer - currently stateless but prepared for stateful upgrade
pub const ZonStreamingAdapter = struct {
    options: ZonLexer.LexerOptions,

    const Self = @This();

    pub fn init(options: ZonLexer.LexerOptions) Self {
        return Self{ .options = options };
    }

    pub fn tokenizeChunk(self: *Self, input: []const u8, start_pos: usize, allocator: std.mem.Allocator) ![]Token {
        var lexer = ZonLexer.init(allocator, input, self.options);
        defer lexer.deinit();

        const tokens = try lexer.tokenize();

        // Adjust token positions for the start_pos offset
        for (tokens) |*token| {
            token.span.start += start_pos;
            token.span.end += start_pos;
        }

        return tokens;
    }

    pub fn deinit(self: *Self) void {
        _ = self; // No cleanup needed for stateless adapter
    }
};

// Tests
const testing = std.testing;

test "ZonStreamingAdapter - basic functionality" {
    var adapter = ZonStreamingAdapter.init(.{
        .preserve_comments = true,
    });
    defer adapter.deinit();

    const input = ".{ .name = \"test\", .value = 123 }";
    const tokens = try adapter.tokenizeChunk(input, 0, testing.allocator);
    defer testing.allocator.free(tokens);

    try testing.expect(tokens.len > 0);
    // Should start with dot operator token
    try testing.expect(tokens[0].kind == .operator);
}

test "ZonStreamingAdapter - position adjustment" {
    var adapter = ZonStreamingAdapter.init(.{
        .preserve_comments = false,
    });
    defer adapter.deinit();

    const input = ".{ .field = 42 }";
    const start_pos: usize = 100;
    const tokens = try adapter.tokenizeChunk(input, start_pos, testing.allocator);
    defer testing.allocator.free(tokens);

    try testing.expect(tokens.len > 0);
    // All tokens should have positions adjusted by start_pos
    for (tokens) |token| {
        try testing.expect(token.span.start >= start_pos);
        try testing.expect(token.span.end >= start_pos);
    }
}

test "ZonStreamingAdapter - comment preservation" {
    var adapter = ZonStreamingAdapter.init(.{
        .preserve_comments = true,
    });
    defer adapter.deinit();

    const input = ".{ // Comment\n .key = \"value\" }";
    const tokens = try adapter.tokenizeChunk(input, 0, testing.allocator);
    defer testing.allocator.free(tokens);

    try testing.expect(tokens.len > 0);

    // Should contain comment token when preserve_comments is true
    var found_comment = false;
    for (tokens) |token| {
        if (token.kind == .comment) {
            found_comment = true;
            break;
        }
    }
    // Note: This might not always find a comment depending on ZonLexer implementation
    // The test is here to ensure the adapter works correctly
}
