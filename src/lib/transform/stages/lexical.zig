const std = @import("std");
const transform_mod = @import("../transform.zig");
const Transform = transform_mod.Transform;
const Context = transform_mod.Context;
const types = @import("../types.zig");

// Import foundation types from stratified parser
const Token = @import("../../parser/foundation/types/token.zig").Token;
const predicate_types = @import("../../parser/foundation/types/predicate.zig");
const TokenKind = predicate_types.TokenKind;
const Span = @import("../../parser/foundation/types/span.zig").Span;

// Import text utilities for reverse transform
const escape_mod = @import("../../text/escape.zig");
const quote_mod = @import("../../text/quote.zig");

/// Lexical stage transform: Text ↔ Tokens
/// Provides bidirectional transformation between source text and token streams
pub const LexicalTransform = Transform([]const u8, []const Token);

/// Interface for lexical transforms (similar to ILexer pattern)
/// Languages implement this to provide tokenization capabilities
pub const ILexicalTransform = struct {
    /// Forward: tokenize text into tokens
    tokenizeFn: *const fn (ctx: *Context, text: []const u8) anyerror![]const Token,

    /// Reverse: reconstruct text from tokens (with trivia preservation)
    detokenizeFn: ?*const fn (ctx: *Context, tokens: []const Token) anyerror![]const u8,

    /// Language identifier for language-specific behavior
    language: ?escape_mod.Escaper.Language = null,

    /// Metadata about the transform
    metadata: types.TransformMetadata,

    const Self = @This();

    /// Convert to Transform interface
    pub fn toTransform(self: *const Self) LexicalTransform {
        return .{
            .forward = self.tokenizeFn,
            .reverse = self.detokenizeFn,
            .forward_async = null,
            .reverse_async = null,
            .metadata = self.metadata,
            .impl = @constCast(@ptrCast(self)),
        };
    }
};

/// Token with trivia preservation for format-preserving transforms
pub const TokenWithTrivia = struct {
    token: Token,
    leading_trivia: []const u8, // Whitespace/comments before token
    trailing_trivia: []const u8, // Whitespace/comments after token

    /// Create from regular token
    pub fn fromToken(token: Token) TokenWithTrivia {
        return .{
            .token = token,
            .leading_trivia = "",
            .trailing_trivia = "",
        };
    }

    /// Extract trivia from source text
    pub fn extractTrivia(
        allocator: std.mem.Allocator,
        source: []const u8,
        token: Token,
        prev_end: usize,
        next_start: usize,
    ) !TokenWithTrivia {
        const leading = if (prev_end < token.span.start)
            try allocator.dupe(u8, source[prev_end..token.span.start])
        else
            "";

        const trailing = if (token.span.end < next_start)
            try allocator.dupe(u8, source[token.span.end..next_start])
        else
            "";

        return .{
            .token = token,
            .leading_trivia = leading,
            .trailing_trivia = trailing,
        };
    }
};

/// Helper to create a lexical transform from existing lexer
pub fn createLexicalTransform(
    tokenize_fn: *const fn (*Context, []const u8) anyerror![]const Token,
    detokenize_fn: ?*const fn (*Context, []const Token) anyerror![]const u8,
    metadata: types.TransformMetadata,
) LexicalTransform {
    return .{
        .forward = tokenize_fn,
        .reverse = detokenize_fn,
        .forward_async = null,
        .reverse_async = null,
        .metadata = metadata,
    };
}

/// Default detokenizer that reconstructs text from tokens
/// Preserves original text when possible, handles escaping when needed
pub fn defaultDetokenize(ctx: *Context, tokens: []const Token) ![]const u8 {
    var result = std.ArrayList(u8).init(ctx.allocator);
    errdefer result.deinit();

    // Get language from context for proper escaping
    const language = ctx.getOption("language", []const u8) orelse "json";
    const escape_lang = std.meta.stringToEnum(escape_mod.Escaper.Language, language) orelse .json;

    var prev_end: usize = 0;
    for (tokens) |token| {
        // Add any gap between tokens (preserves whitespace)
        if (prev_end < token.span.start) {
            // This would need access to original source for perfect preservation
            // For now, add a space between tokens
            if (prev_end > 0) {
                try result.append(' ');
            }
        }

        // Add token text
        if (token.kind == .string_literal) {
            // Ensure strings are properly quoted/escaped
            var quote_manager = quote_mod.QuoteManager.init(ctx.allocator);
            const quoted = try quote_manager.ensureQuoted(token.text, .{
                .style = .double,
                .language = escape_lang,
            });
            defer ctx.allocator.free(quoted);
            try result.appendSlice(quoted);
        } else {
            try result.appendSlice(token.text);
        }

        prev_end = token.span.end;
    }

    return result.toOwnedSlice();
}

/// Streaming tokenizer interface for large files
pub const TokenIterator = struct {
    ctx: *Context,
    source: []const u8,
    position: usize,
    lexer: ILexicalTransform,
    buffer: std.ArrayList(Token),
    finished: bool,

    const Self = @This();
    const CHUNK_SIZE = 4096;

    pub fn init(ctx: *Context, source: []const u8, lexer: ILexicalTransform) TokenIterator {
        return .{
            .ctx = ctx,
            .source = source,
            .position = 0,
            .lexer = lexer,
            .buffer = std.ArrayList(Token).init(ctx.allocator),
            .finished = false,
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
    }

    pub fn next(self: *Self) !?Token {
        if (self.buffer.items.len > 0) {
            return self.buffer.orderedRemove(0);
        }

        if (self.finished) {
            return null;
        }

        // Tokenize next chunk
        const chunk_end = @min(self.position + CHUNK_SIZE, self.source.len);
        const chunk = self.source[self.position..chunk_end];

        const tokens = try self.lexer.tokenizeFn(self.ctx, chunk);
        defer self.ctx.allocator.free(tokens);

        // Adjust token spans to absolute positions
        for (tokens) |token| {
            var adjusted = token;
            adjusted.span = Span.init(
                token.span.start + self.position,
                token.span.end + self.position,
            );
            try self.buffer.append(adjusted);
        }

        self.position = chunk_end;
        if (self.position >= self.source.len) {
            self.finished = true;
        }

        return if (self.buffer.items.len > 0)
            self.buffer.orderedRemove(0)
        else
            null;
    }
};

// Tests
const testing = std.testing;

test "TokenWithTrivia extraction" {
    const allocator = testing.allocator;

    const source = "  hello  world  ";
    const token = Token.simple(Span.init(2, 7), .identifier, "hello", 0);

    const with_trivia = try TokenWithTrivia.extractTrivia(
        allocator,
        source,
        token,
        0, // prev_end
        9, // next_start
    );
    defer {
        allocator.free(with_trivia.leading_trivia);
        allocator.free(with_trivia.trailing_trivia);
    }

    try testing.expectEqualStrings("  ", with_trivia.leading_trivia);
    try testing.expectEqualStrings("  ", with_trivia.trailing_trivia);
}

test "Default detokenizer" {
    const allocator = testing.allocator;

    var ctx = Context.init(allocator);
    defer ctx.deinit();

    const tokens = [_]Token{
        Token.simple(Span.init(0, 1), .delimiter, "{", 0),
        Token.simple(Span.init(2, 7), .string_literal, "key", 0),
        Token.simple(Span.init(8, 9), .delimiter, ":", 0),
        Token.simple(Span.init(10, 15), .string_literal, "value", 0),
        Token.simple(Span.init(16, 17), .delimiter, "}", 0),
    };

    const result = try defaultDetokenize(&ctx, &tokens);
    defer allocator.free(result);

    // Result should have tokens with spaces between
    try testing.expect(std.mem.indexOf(u8, result, "{") != null);
    try testing.expect(std.mem.indexOf(u8, result, "}") != null);
}
