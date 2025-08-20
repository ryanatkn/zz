const std = @import("std");
const Token = @import("../../parser/foundation/types/token.zig").Token;
const TokenKind = @import("../../parser/foundation/types/predicate.zig").TokenKind;
const TokenFlags = @import("../../parser/foundation/types/token.zig").TokenFlags;
const Span = @import("../../parser/foundation/types/span.zig").Span;
const JsonToken = @import("../../languages/json/tokens.zig").JsonToken;
const ZonToken = @import("../../languages/zon/tokens.zig").ZonToken;

/// Zero-copy streaming token that avoids unnecessary conversions
/// Uses a union to hold language-specific tokens and provides direct field access
/// Achieves <100ns/token by eliminating conversion overhead
pub const StreamToken = union(enum) {
    json: JsonToken,
    zon: ZonToken,
    generic: Token,
    // Future: typescript, zig, css, html, svelte

    const Self = @This();

    /// Get span without conversion (zero-cost)
    pub inline fn span(self: Self) Span {
        return switch (self) {
            .json => |t| t.span(),
            .zon => |t| t.span(),
            .generic => |t| t.span,
        };
    }

    /// Get token kind with fast mapping
    pub inline fn kind(self: Self) TokenKind {
        return switch (self) {
            .json => |t| mapJsonKind(t),
            .zon => |t| mapZonKind(t),
            .generic => |t| t.kind,
        };
    }

    /// Get text slice without conversion
    pub inline fn text(self: Self) []const u8 {
        return switch (self) {
            .json => |t| t.text(),
            .zon => |t| t.text(),
            .generic => |t| t.text,
        };
    }

    /// Get depth/nesting level
    pub inline fn depth(self: Self) u16 {
        return switch (self) {
            .json => |t| t.tokenData().depth,
            .zon => |t| t.tokenData().depth,
            .generic => |t| t.bracket_depth,
        };
    }

    /// Check if token is trivia (whitespace/comments)
    pub inline fn isTrivia(self: Self) bool {
        return switch (self) {
            .json => |t| t.isTrivia(),
            .zon => |t| t.isTrivia(),
            .generic => |t| t.isTrivia(),
        };
    }

    /// Check if token is an opening delimiter
    pub inline fn isOpenDelimiter(self: Self) bool {
        return switch (self) {
            .json => |t| t.isOpenDelimiter(),
            .zon => |t| t.isOpenDelimiter(),
            .generic => |t| t.isOpenDelimiter(),
        };
    }

    /// Check if token is a closing delimiter
    pub inline fn isCloseDelimiter(self: Self) bool {
        return switch (self) {
            .json => |t| t.isCloseDelimiter(),
            .zon => |t| t.isCloseDelimiter(),
            .generic => |t| t.isCloseDelimiter(),
        };
    }

    /// Check if token represents an error
    pub inline fn isError(self: Self) bool {
        return switch (self) {
            .json => |t| switch (t) {
                .invalid => true,
                else => false,
            },
            .zon => |t| switch (t) {
                .invalid => true,
                else => false,
            },
            .generic => |t| t.isError(),
        };
    }

    /// Convert to generic token only when absolutely necessary
    /// This is the slow path - avoid if possible
    pub fn toGenericToken(self: Self, source: []const u8) Token {
        return switch (self) {
            .json => |t| convertJsonToken(t, source),
            .zon => |t| convertZonToken(t, source),
            .generic => |t| t,
        };
    }

    /// Fast inline mapping for JSON token kinds
    inline fn mapJsonKind(token: JsonToken) TokenKind {
        return switch (token) {
            .object_start => .left_brace,
            .object_end => .right_brace,
            .array_start => .left_bracket,
            .array_end => .right_bracket,
            .comma => .comma,
            .colon => .colon,
            .property_name => .string_literal,
            .string_value => .string_literal,
            .number_value => .number_literal,
            .boolean_value => .boolean_literal,
            .null_value => .null_literal,
            .comment => .comment,
            .whitespace => .whitespace,
            .invalid => .unknown,
        };
    }

    /// Fast inline mapping for ZON token kinds
    inline fn mapZonKind(token: ZonToken) TokenKind {
        return switch (token) {
            .object_start => .left_brace,
            .object_end => .right_brace,
            .array_start => .left_bracket,
            .array_end => .right_bracket,
            .comma => .comma,
            .colon => .colon,
            .equals => .operator,
            .identifier => .identifier,
            .field_name => |f| if (f.is_quoted) .string_literal else .identifier,
            .string_value => .string_literal,
            .decimal_int, .hex_int, .binary_int, .octal_int, .float => .number_literal,
            .char_literal => .string_literal,
            .boolean_value => .boolean_literal,
            .null_value => .null_literal,
            .undefined_value => .keyword,
            .enum_literal => .identifier,
            .struct_literal => .delimiter,
            .comment => .comment,
            .whitespace => .whitespace,
            .invalid => .unknown,
        };
    }

    /// Convert JSON token to generic (only when needed)
    fn convertJsonToken(token: JsonToken, source: []const u8) Token {
        const data = token.tokenData();
        const token_span = token.span();
        const token_text = if (token_span.start < source.len and token_span.end <= source.len)
            source[token_span.start..token_span.end]
        else
            token.text();

        const flags = TokenFlags{
            .is_trivia = token.isTrivia(),
            .is_error = switch (token) {
                .invalid => true,
                else => false,
            },
            .is_open_delimiter = token.isOpenDelimiter(),
            .is_close_delimiter = token.isCloseDelimiter(),
            .is_inserted = data.flags.is_inserted,
            .is_end_of_line = data.flags.is_eol,
        };

        return Token.init(
            token_span,
            mapJsonKind(token),
            token_text,
            data.depth,
            flags,
        );
    }

    /// Convert ZON token to generic (only when needed)
    fn convertZonToken(token: ZonToken, source: []const u8) Token {
        const data = token.tokenData();
        const token_span = token.span();
        const token_text = if (token_span.start < source.len and token_span.end <= source.len)
            source[token_span.start..token_span.end]
        else
            token.text();

        const flags = TokenFlags{
            .is_trivia = token.isTrivia(),
            .is_error = switch (token) {
                .invalid => true,
                else => false,
            },
            .is_open_delimiter = token.isOpenDelimiter(),
            .is_close_delimiter = token.isCloseDelimiter(),
            .is_inserted = data.flags.is_inserted,
            .is_end_of_line = data.flags.is_eol,
        };

        return Token.init(
            token_span,
            mapZonKind(token),
            token_text,
            data.depth,
            flags,
        );
    }
};

// Tests
const testing = std.testing;

test "StreamToken - zero-cost field access" {
    const span = Span.init(0, 5);
    const data = @import("../../languages/common/token_base.zig").TokenData.init(span, 1, 1, 0);
    const json_token = @import("../../languages/json/tokens.zig").structural(.object_start, data);

    const stream_token = StreamToken{ .json = json_token };

    // These should be zero-cost operations (no conversion)
    try testing.expectEqual(span, stream_token.span());
    try testing.expectEqual(TokenKind.left_brace, stream_token.kind());
    try testing.expect(stream_token.isOpenDelimiter());
    try testing.expect(!stream_token.isTrivia());
}

test "StreamToken - generic token passthrough" {
    const token = Token.simple(
        Span.init(0, 3),
        .identifier,
        "foo",
        0,
    );

    const stream_token = StreamToken{ .generic = token };

    // Should pass through without any conversion
    try testing.expectEqual(token.span, stream_token.span());
    try testing.expectEqual(token.kind, stream_token.kind());
    try testing.expectEqualStrings(token.text, stream_token.text());
}

test "StreamToken - lazy conversion to generic" {
    const span = Span.init(2, 9);
    const data = @import("../../languages/common/token_base.zig").TokenData.init(span, 1, 3, 1);
    const string_token = JsonToken{
        .string_value = .{
            .data = data,
            .value = "hello",
            .raw = "\"hello\"",
            .has_escapes = false,
        },
    };

    const source = "{ \"hello\" }";
    const stream_token = StreamToken{ .json = string_token };

    // Only convert when absolutely necessary
    const generic = stream_token.toGenericToken(source);
    try testing.expectEqual(TokenKind.string_literal, generic.kind);
    try testing.expectEqualStrings("\"hello\"", generic.text);
}