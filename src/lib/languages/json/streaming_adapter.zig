const std = @import("std");
const Token = @import("../../parser/foundation/types/token.zig").Token;
const StatefulLexer = @import("../../transform/streaming/stateful_lexer.zig").StatefulLexer;
const JsonLexer = @import("lexer.zig").JsonLexer;
const StatefulJsonLexer = @import("stateful_lexer.zig").StatefulJsonLexer;
const JsonToken = @import("tokens.zig").JsonToken;
const TokenConverter = @import("../../transform/streaming/token_converter.zig").TokenConverter;

/// Streaming adapter for JSON lexer - integrates stateful JSON lexer with token iterator
/// Converts rich JsonToken types to generic Token interface for parser consumption
///
/// Design Note: Token conversion is necessary to maintain clean separation between
/// language-specific rich tokens (JsonToken) and the generic Token interface used
/// by the stratified parser layers. This allows maximum semantic information in
/// language tokens while providing a uniform interface for parsing infrastructure.
pub const JsonStreamingAdapter = struct {
    lexer: StatefulJsonLexer,
    source: []const u8, // Keep reference to source for conversion
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, options: JsonLexer.LexerOptions) Self {
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
            .lexer = StatefulJsonLexer.init(allocator, stateful_options),
            .source = &.{},
            .allocator = allocator,
        };
    }

    pub fn tokenizeChunk(self: *Self, input: []const u8, start_pos: usize, allocator: std.mem.Allocator) ![]Token {
        // Store source reference for conversion
        self.source = input;

        // Get JSON tokens from stateful lexer
        const json_tokens = try self.lexer.processChunk(input, start_pos, allocator);
        defer allocator.free(json_tokens);

        // Optimize: Convert directly without intermediate array
        return try self.convertTokensStreaming(json_tokens, allocator);
    }

    /// Optimized streaming conversion that avoids double allocation
    fn convertTokensStreaming(self: *Self, json_tokens: []const JsonToken, allocator: std.mem.Allocator) ![]Token {
        var result = try std.ArrayList(Token).initCapacity(allocator, json_tokens.len);
        errdefer result.deinit();

        for (json_tokens) |json_token| {
            const converted = TokenConverter.convertJsonToken(json_token, self.source);
            try result.append(converted);
        }

        return result.toOwnedSlice();
    }

    /// Alternative streaming interface that yields tokens one by one
    /// Avoids allocation of token arrays for memory-conscious applications
    pub fn tokenIterator(self: *Self, input: []const u8, start_pos: usize, allocator: std.mem.Allocator) !TokenIterator {
        self.source = input;
        const json_tokens = try self.lexer.processChunk(input, start_pos, allocator);
        return TokenIterator{
            .json_tokens = json_tokens,
            .source = self.source,
            .index = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.lexer.deinit();
    }
};

/// Iterator that converts JsonTokens to Tokens on-demand
/// More memory efficient for large token streams
pub const TokenIterator = struct {
    json_tokens: []const JsonToken,
    source: []const u8,
    index: usize,
    allocator: std.mem.Allocator,

    pub fn next(self: *TokenIterator) ?Token {
        if (self.index >= self.json_tokens.len) return null;

        const json_token = self.json_tokens[self.index];
        self.index += 1;

        return TokenConverter.convertJsonToken(json_token, self.source);
    }

    pub fn deinit(self: *TokenIterator) void {
        self.allocator.free(self.json_tokens);
    }
};

// Tests
const testing = std.testing;

test "JsonStreamingAdapter - basic functionality" {
    var adapter = JsonStreamingAdapter.init(testing.allocator, .{
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
    var adapter = JsonStreamingAdapter.init(testing.allocator, .{
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
    var adapter = JsonStreamingAdapter.init(testing.allocator, .{
        .allow_comments = true,
        .allow_trailing_commas = true,
    });
    defer adapter.deinit();

    const input = "{ /* comment */ \"key\": 123, }";
    const tokens = try adapter.tokenizeChunk(input, 0, testing.allocator);
    defer testing.allocator.free(tokens);

    try testing.expect(tokens.len > 0);
}
