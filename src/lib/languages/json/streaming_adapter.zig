const std = @import("std");
const Token = @import("../../parser/foundation/types/token.zig").Token;
const StatefulLexer = @import("../../transform/streaming/stateful_lexer.zig").StatefulLexer;
const JsonLexer = @import("lexer.zig").JsonLexer;
const StatefulJsonLexer = @import("stateful_lexer.zig").StatefulJsonLexer;

/// Streaming adapter for JSON lexer - integrates stateful JSON lexer with token iterator
pub const JsonStreamingAdapter = struct {
    lexer: StatefulJsonLexer,

    const Self = @This();

    pub fn init(options: JsonLexer.LexerOptions) Self {
        const stateful_options = StatefulLexer.Options{
            .allow_comments = options.allow_comments,
            .allow_trailing_commas = options.allow_trailing_commas,
            .json5_mode = false,
            .error_recovery = true,
            .allow_template_literals = false,
            .allow_regex_literals = false,
            .allow_raw_strings = false,
            .allow_multiline_strings = false,
        };
        return Self{
            .lexer = StatefulJsonLexer.init(std.heap.page_allocator, stateful_options),
        };
    }

    pub fn tokenizeChunk(self: *Self, input: []const u8, start_pos: usize, allocator: std.mem.Allocator) ![]Token {
        // Use the stateful lexer for correct chunk handling
        return try self.lexer.processChunk(input, start_pos, allocator);
    }

    pub fn deinit(self: *Self) void {
        self.lexer.deinit();
    }
};

// Tests
const testing = std.testing;

test "JsonStreamingAdapter - basic functionality" {
    var adapter = JsonStreamingAdapter.init(.{
        .allow_comments = false,
        .allow_trailing_commas = false,
    });
    defer adapter.deinit();

    const input = "{\"test\": 123}";
    const tokens = try adapter.tokenizeChunk(input, 0, testing.allocator);
    defer testing.allocator.free(tokens);

    try testing.expect(tokens.len > 0);
    try testing.expect(tokens[0].kind == .left_brace);
}

test "JsonStreamingAdapter - chunk boundary handling" {
    var adapter = JsonStreamingAdapter.init(.{
        .allow_comments = false,
        .allow_trailing_commas = false,
    });
    defer adapter.deinit();

    // First chunk - incomplete string
    const chunk1 = "{\"na";
    const tokens1 = try adapter.tokenizeChunk(chunk1, 0, testing.allocator);
    defer testing.allocator.free(tokens1);

    // Second chunk - complete the string
    const chunk2 = "me\": 42}";
    const tokens2 = try adapter.tokenizeChunk(chunk2, chunk1.len, testing.allocator);
    defer testing.allocator.free(tokens2);

    // Should handle chunk boundary correctly
    try testing.expect(tokens1.len >= 1); // At least opening brace
    try testing.expect(tokens2.len >= 3); // String, colon, number, closing brace
}

test "JsonStreamingAdapter - JSON5 support" {
    var adapter = JsonStreamingAdapter.init(.{
        .allow_comments = true,
        .allow_trailing_commas = true,
    });
    defer adapter.deinit();

    const input = "{ /* comment */ \"key\": 123, }";
    const tokens = try adapter.tokenizeChunk(input, 0, testing.allocator);
    defer testing.allocator.free(tokens);

    try testing.expect(tokens.len > 0);
}