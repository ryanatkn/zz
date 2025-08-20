const std = @import("std");
const Token = @import("../../parser/foundation/types/token.zig").Token;
const TokenKind = @import("../../parser/foundation/types/predicate.zig").TokenKind;
const TokenFlags = @import("../../parser/foundation/types/token.zig").TokenFlags;
const Span = @import("../../parser/foundation/types/span.zig").Span;
const JsonToken = @import("../../languages/json/tokens.zig").JsonToken;
const ZonToken = @import("../../languages/zon/tokens.zig").ZonToken;

/// Token converter for transforming language-specific tokens to generic tokens
///
/// Design Philosophy:
/// - Rich language tokens (JsonToken, ZonToken) contain maximum semantic info
/// - Generic Token provides uniform interface for stratified parser layers
/// - Conversion is necessary architectural choice, not code smell
/// - Optimized for streaming/lazy conversion to minimize allocations
///
/// Preserves maximum semantic information while providing a uniform interface
pub const TokenConverter = struct {
    // Use convertJsonToken or convertZonToken directly for better performance

    /// Convert JSON token to generic token
    pub fn convertJsonToken(token: JsonToken, source: []const u8) Token {
        const data = token.tokenData();
        const span = token.span();

        // Extract text slice from source
        const text = if (span.start < source.len and span.end <= source.len)
            source[span.start..span.end]
        else
            token.text();

        const kind: TokenKind = switch (token) {
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
            span,
            kind,
            text,
            data.depth,
            flags,
        );
    }

    /// Convert ZON token to generic token
    pub fn convertZonToken(token: ZonToken, source: []const u8) Token {
        const data = token.tokenData();
        const span = token.span();

        // Extract text slice from source
        const text = if (span.start < source.len and span.end <= source.len)
            source[span.start..span.end]
        else
            token.text();

        const kind: TokenKind = switch (token) {
            .object_start => .left_brace,
            .object_end => .right_brace,
            .array_start => .left_bracket,
            .array_end => .right_bracket,
            .comma => .comma,
            .colon => .colon,
            .equals => .operator, // ZON uses = for assignment
            .identifier => .identifier,
            .field_name => if (token.field_name.is_quoted) .string_literal else .identifier,
            .string_value => .string_literal,
            .number_value => .number_literal,
            .char_literal => .string_literal, // Treat as string for generic token
            .boolean_value => .boolean_literal,
            .null_value => .null_literal,
            .undefined_value => .keyword, // undefined is like a keyword
            .enum_literal => .identifier, // Enum literals are like identifiers
            .struct_literal => .delimiter, // .{} is a delimiter pattern
            .comment => .comment,
            .whitespace => .whitespace,
            .invalid => .unknown,
        };

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
            span,
            kind,
            text,
            data.depth,
            flags,
        );
    }

    // NOTE: For batch conversion, use inline loops with individual token conversion
    // functions (convertJsonToken, convertZonToken) in calling code for better
    // performance and memory efficiency.
};

// Tests
const testing = std.testing;

test "TokenConverter - JSON structural tokens" {
    const span = Span.init(0, 1);
    const data = @import("../../languages/common/token_base.zig").TokenData.init(span, 1, 1, 0);
    const json_token = @import("../../languages/json/tokens.zig").structural(.object_start, data);

    const source = "{";
    const generic_token = TokenConverter.convertJsonToken(json_token, source);

    try testing.expectEqual(TokenKind.left_brace, generic_token.kind);
    try testing.expectEqualStrings("{", generic_token.text);
    try testing.expect(generic_token.isOpenDelimiter());
}

test "TokenConverter - JSON value tokens" {
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
    const generic_token = TokenConverter.convertJsonToken(string_token, source);

    try testing.expectEqual(TokenKind.string_literal, generic_token.kind);
    try testing.expectEqualStrings("\"hello\"", generic_token.text);
    try testing.expect(!generic_token.isTrivia());
}

test "TokenConverter - ZON identifier tokens" {
    const span = Span.init(0, 7);
    const data = @import("../../languages/common/token_base.zig").TokenData.init(span, 1, 1, 0);

    const id_token = ZonToken{
        .identifier = .{
            .data = data,
            .text = "myField",
            .is_builtin = false,
        },
    };

    const source = "myField = 42";
    const generic_token = TokenConverter.convertZonToken(id_token, source);

    try testing.expectEqual(TokenKind.identifier, generic_token.kind);
    try testing.expectEqualStrings("myField", generic_token.text);
}

// Removed tests for convertMany and convertFiltered since they are no longer needed.
// Production code should use inline conversion loops for better performance.
