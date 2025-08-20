const std = @import("std");
const Token = @import("../../parser/foundation/types/token.zig").Token;
const TokenKind = @import("../../parser/foundation/types/predicate.zig").TokenKind;
const TokenFlags = @import("../../parser/foundation/types/token.zig").TokenFlags;
const Span = @import("../../parser/foundation/types/span.zig").Span;
const JsonToken = @import("../../languages/json/tokens.zig").JsonToken;
const ZonToken = @import("../../languages/zon/tokens.zig").ZonToken;

/// Token converter for transforming language-specific tokens to generic tokens
/// Preserves maximum semantic information while providing a uniform interface
pub const TokenConverter = struct {
    /// Convert any language token to generic Token
    pub fn convert(comptime T: type, token: T, source: []const u8) Token {
        return switch (T) {
            JsonToken => convertJsonToken(token, source),
            ZonToken => convertZonToken(token, source),
            else => @compileError("Unsupported token type for conversion"),
        };
    }
    
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
            .equals => .operator,  // ZON uses = for assignment
            .identifier => .identifier,
            .field_name => if (token.field_name.is_quoted) .string_literal else .identifier,
            .string_value => .string_literal,
            .number_value => .number_literal,
            .char_literal => .string_literal,  // Treat as string for generic token
            .boolean_value => .boolean_literal,
            .null_value => .null_literal,
            .undefined_value => .keyword,  // undefined is like a keyword
            .enum_literal => .identifier,  // Enum literals are like identifiers
            .struct_literal => .delimiter,  // .{} is a delimiter pattern
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
    
    /// Convert a slice of language tokens to generic tokens
    pub fn convertMany(
        comptime T: type,
        tokens: []const T,
        source: []const u8,
        allocator: std.mem.Allocator,
    ) ![]Token {
        var result = try std.ArrayList(Token).initCapacity(allocator, tokens.len);
        errdefer result.deinit();
        
        for (tokens) |token| {
            try result.append(convert(T, token, source));
        }
        
        return result.toOwnedSlice();
    }
    
    /// Filter and convert tokens (e.g., skip trivia)
    pub fn convertFiltered(
        comptime T: type,
        tokens: []const T,
        source: []const u8,
        allocator: std.mem.Allocator,
        filter: TokenFilter,
    ) ![]Token {
        var result = std.ArrayList(Token).init(allocator);
        errdefer result.deinit();
        
        for (tokens) |token| {
            const should_include = switch (T) {
                JsonToken => filter.shouldIncludeJson(token),
                ZonToken => filter.shouldIncludeZon(token),
                else => true,
            };
            
            if (should_include) {
                try result.append(convert(T, token, source));
            }
        }
        
        return result.toOwnedSlice();
    }
};

/// Token filter configuration
pub const TokenFilter = struct {
    skip_trivia: bool = true,
    skip_comments: bool = false,
    skip_whitespace: bool = true,
    skip_errors: bool = false,
    
    pub fn shouldIncludeJson(self: TokenFilter, token: JsonToken) bool {
        if (self.skip_trivia and token.isTrivia()) return false;
        if (self.skip_comments and token == .comment) return false;
        if (self.skip_whitespace and token == .whitespace) return false;
        if (self.skip_errors and token == .invalid) return false;
        return true;
    }
    
    pub fn shouldIncludeZon(self: TokenFilter, token: ZonToken) bool {
        if (self.skip_trivia and token.isTrivia()) return false;
        if (self.skip_comments and token == .comment) return false;
        if (self.skip_whitespace and token == .whitespace) return false;
        if (self.skip_errors and token == .invalid) return false;
        return true;
    }
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

test "TokenConverter - convertMany" {
    const TokenData = @import("../../languages/common/token_base.zig").TokenData;
    
    const tokens = [_]JsonToken{
        @import("../../languages/json/tokens.zig").structural(
            .object_start,
            TokenData.init(Span.init(0, 1), 1, 1, 0),
        ),
        JsonToken{
            .string_value = .{
                .data = TokenData.init(Span.init(2, 7), 1, 3, 1),
                .value = "test",
                .raw = "\"test\"",
                .has_escapes = false,
            },
        },
        @import("../../languages/json/tokens.zig").structural(
            .object_end,
            TokenData.init(Span.init(8, 9), 1, 9, 0),
        ),
    };
    
    const source = "{ \"test\" }";
    const generic_tokens = try TokenConverter.convertMany(
        JsonToken,
        &tokens,
        source,
        testing.allocator,
    );
    defer testing.allocator.free(generic_tokens);
    
    try testing.expectEqual(@as(usize, 3), generic_tokens.len);
    try testing.expectEqual(TokenKind.left_brace, generic_tokens[0].kind);
    try testing.expectEqual(TokenKind.string_literal, generic_tokens[1].kind);
    try testing.expectEqual(TokenKind.right_brace, generic_tokens[2].kind);
}

test "TokenConverter - filter trivia" {
    const TokenData = @import("../../languages/common/token_base.zig").TokenData;
    
    const tokens = [_]JsonToken{
        @import("../../languages/json/tokens.zig").structural(
            .object_start,
            TokenData.init(Span.init(0, 1), 1, 1, 0),
        ),
        JsonToken{
            .whitespace = .{
                .data = TokenData.init(Span.init(1, 2), 1, 2, 0),
                .text = " ",
            },
        },
        @import("../../languages/json/tokens.zig").structural(
            .object_end,
            TokenData.init(Span.init(2, 3), 1, 3, 0),
        ),
    };
    
    const source = "{ }";
    const filter = TokenFilter{ .skip_trivia = true };
    const filtered = try TokenConverter.convertFiltered(
        JsonToken,
        &tokens,
        source,
        testing.allocator,
        filter,
    );
    defer testing.allocator.free(filtered);
    
    // Should only have 2 tokens (whitespace filtered out)
    try testing.expectEqual(@as(usize, 2), filtered.len);
    try testing.expectEqual(TokenKind.left_brace, filtered[0].kind);
    try testing.expectEqual(TokenKind.right_brace, filtered[1].kind);
}