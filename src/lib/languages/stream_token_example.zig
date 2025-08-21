/// Example of composing a custom StreamToken for your application
/// This shows how to create a project-specific token union
const std = @import("std");
const TokenKind = @import("../token/kind.zig").TokenKind;
const SimpleStreamToken = @import("../token/generic.zig").SimpleStreamToken;

// Import only the language tokens you need
const JsonToken = @import("json/stream_token.zig").JsonToken;
const JsonTokenKind = @import("json/stream_token.zig").JsonTokenKind;
const ZonToken = @import("zon/stream_token.zig").ZonToken;
const ZonTokenKind = @import("zon/stream_token.zig").ZonTokenKind;

/// Define your custom token union with only the languages you support
pub const MyTokenUnion = union(enum) {
    json: JsonToken,
    zon: ZonToken,
    // Add more languages as needed:
    // typescript: TsToken,
    // python: PyToken,
    // custom: MyCustomToken,
};

/// Create your application's StreamToken type
pub const MyStreamToken = SimpleStreamToken(MyTokenUnion);

/// Custom kind mapping for your application
pub fn mapTokenKind(token: MyTokenUnion) TokenKind {
    return switch (token) {
        .json => |t| mapJsonKind(t.kind),
        .zon => |t| mapZonKind(t.kind),
    };
}

fn mapJsonKind(kind: JsonTokenKind) TokenKind {
    return switch (kind) {
        .object_start => .left_brace,
        .object_end => .right_brace,
        .array_start => .left_bracket,
        .array_end => .right_bracket,
        .comma => .comma,
        .colon => .colon,
        .property_name => .string,
        .string_value => .string,
        .number_value => .number,
        .boolean_true, .boolean_false => .boolean,
        .null_value => .null,
        .whitespace => .whitespace,
        .comment => .comment,
        .eof => .eof,
        .err => .err,
    };
}

fn mapZonKind(kind: ZonTokenKind) TokenKind {
    return switch (kind) {
        .struct_start => .left_brace,
        .struct_end => .right_brace,
        .array_start => .left_bracket,
        .array_end => .right_bracket,
        .comma => .comma,
        .equals => .assign,
        .dot => .dot,
        .field_name => .identifier,
        .identifier => .identifier,
        .string_value => .string,
        .number_value => .number,
        .boolean_true, .boolean_false => .boolean,
        .null_value => .null,
        .undefined => .unknown,
        .enum_literal => .identifier,
        .import => .keyword_import,
        .whitespace => .whitespace,
        .comment => .comment,
        .eof => .eof,
        .err => .err,
    };
}

/// Example: Creating a minimal token union for JSON-only support
pub const JsonOnlyToken = union(enum) {
    json: JsonToken,
};

pub const JsonOnlyStreamToken = SimpleStreamToken(JsonOnlyToken);

/// Example: Adding a custom token type
pub const CustomToken = extern struct {
    span: @import("../span/mod.zig").PackedSpan,
    kind: CustomTokenKind,
    depth: u8,
    flags: u8,
    data: u32,
    
    pub fn isTrivia(self: CustomToken) bool {
        return self.kind == .whitespace or self.kind == .comment;
    }
    
    pub fn isOpenDelimiter(self: CustomToken) bool {
        return self.kind == .block_start;
    }
    
    pub fn isCloseDelimiter(self: CustomToken) bool {
        return self.kind == .block_end;
    }
};

pub const CustomTokenKind = enum(u8) {
    identifier,
    number,
    string,
    block_start,
    block_end,
    whitespace,
    comment,
};

/// Example: Token union with custom language
pub const ExtendedTokenUnion = union(enum) {
    json: JsonToken,
    zon: ZonToken,
    custom: CustomToken,
};

pub const ExtendedStreamToken = SimpleStreamToken(ExtendedTokenUnion);

test "Custom token composition" {
    const Span = @import("../span/mod.zig").Span;
    const span = Span.init(10, 20);
    
    // Create a JSON token through custom union
    const json_tok = JsonToken.structural(span, .object_start, 0);
    const my_token = MyStreamToken{
        .token = MyTokenUnion{ .json = json_tok },
    };
    
    try std.testing.expectEqual(json_tok.span, my_token.span());
    try std.testing.expectEqual(@as(u8, 0), my_token.depth());
    try std.testing.expect(my_token.isOpenDelimiter());
    
    // Test minimal JSON-only token
    const json_only = JsonOnlyStreamToken{
        .token = JsonOnlyToken{ .json = json_tok },
    };
    
    try std.testing.expectEqual(json_tok.span, json_only.span());
    try std.testing.expect(json_only.isOpenDelimiter());
}