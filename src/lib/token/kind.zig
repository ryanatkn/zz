/// Unified token classification for all languages
/// Designed to be minimal yet cover common patterns across languages
/// Uses u8 for compact storage (1 byte)
const std = @import("std");

/// Universal token kinds that apply across all supported languages
pub const TokenKind = enum(u8) {
    // ====== Literals ======
    identifier,
    number,
    string,
    boolean,
    null,

    // ====== Keywords (common subset) ======
    keyword_if,
    keyword_else,
    keyword_function,
    keyword_class,
    keyword_return,
    keyword_import,
    keyword_export,
    keyword_const,
    keyword_let,
    keyword_var,
    keyword_for,
    keyword_while,
    keyword_switch,
    keyword_case,
    keyword_default,
    keyword_break,
    keyword_continue,
    keyword_new,
    keyword_this,
    keyword_type,
    keyword_interface,
    keyword_enum,
    keyword_struct,
    keyword_async,
    keyword_await,
    keyword_try,
    keyword_catch,
    keyword_finally,
    keyword_throw,
    keyword_public,
    keyword_private,
    keyword_static,

    // ====== Operators ======
    // Arithmetic
    plus, // +
    minus, // -
    star, // *
    slash, // /
    percent, // %

    // Comparison
    equals, // ==
    not_equals, // !=
    less_than, // <
    greater_than, // >
    less_equals, // <=
    greater_equals, // >=

    // Assignment
    assign, // =
    plus_assign, // +=
    minus_assign, // -=
    star_assign, // *=
    slash_assign, // /=

    // Logical
    logical_and, // &&
    logical_or, // ||
    logical_not, // !

    // Bitwise
    bit_and, // &
    bit_or, // |
    bit_xor, // ^
    bit_not, // ~
    left_shift, // <<
    right_shift, // >>

    // ====== Delimiters ======
    left_paren, // (
    right_paren, // )
    left_brace, // {
    right_brace, // }
    left_bracket, // [
    right_bracket, // ]
    left_angle, // < (when used as delimiter)
    right_angle, // > (when used as delimiter)

    // ====== Punctuation ======
    comma, // ,
    semicolon, // ;
    colon, // :
    dot, // .
    arrow, // ->
    fat_arrow, // =>
    question, // ?
    at, // @
    hash, // #
    dollar, // $
    ampersand, // & (reference)
    pipe, // | (union type)

    // ====== Trivia ======
    whitespace,
    newline,
    comment,
    doc_comment,

    // ====== Special ======
    eof,
    err, // 'error' is reserved in Zig
    unknown,

    // ====== Language-specific markers ======
    // These help preserve language semantics without full enumeration
    template_start, // Template literals, JSX, etc.
    template_end,
    interpolation_start,
    interpolation_end,
    regex, // Regular expression literals
    decorator, // @decorator syntax

    /// Get a human-readable name for the token kind
    pub fn name(self: TokenKind) []const u8 {
        return @tagName(self);
    }

    /// Check if this token kind is trivia (can be skipped in parsing)
    pub fn isTrivia(self: TokenKind) bool {
        return switch (self) {
            .whitespace, .newline, .comment, .doc_comment => true,
            else => false,
        };
    }

    /// Check if this token kind is a delimiter
    pub fn isDelimiter(self: TokenKind) bool {
        return switch (self) {
            .left_paren, .right_paren, .left_brace, .right_brace, .left_bracket, .right_bracket, .left_angle, .right_angle => true,
            else => false,
        };
    }

    /// Check if this token kind opens a scope
    pub fn isOpenDelimiter(self: TokenKind) bool {
        return switch (self) {
            .left_paren, .left_brace, .left_bracket, .left_angle => true,
            else => false,
        };
    }

    /// Check if this token kind closes a scope
    pub fn isCloseDelimiter(self: TokenKind) bool {
        return switch (self) {
            .right_paren, .right_brace, .right_bracket, .right_angle => true,
            else => false,
        };
    }

    /// Check if this token kind is a keyword
    pub fn isKeyword(self: TokenKind) bool {
        const name_str = @tagName(self);
        return std.mem.startsWith(u8, name_str, "keyword_");
    }

    /// Check if this token kind is an operator
    pub fn isOperator(self: TokenKind) bool {
        return switch (self) {
            .plus, .minus, .star, .slash, .percent, .equals, .not_equals, .less_than, .greater_than, .less_equals, .greater_equals, .assign, .plus_assign, .minus_assign, .star_assign, .slash_assign, .logical_and, .logical_or, .logical_not, .bit_and, .bit_or, .bit_xor, .bit_not, .left_shift, .right_shift => true,
            else => false,
        };
    }

    /// Check if this token kind is a literal
    pub fn isLiteral(self: TokenKind) bool {
        return switch (self) {
            .identifier, .number, .string, .boolean, .null, .regex => true,
            else => false,
        };
    }
};

// Size assertion - must be 1 byte
comptime {
    std.debug.assert(@sizeOf(TokenKind) == 1);
}

test "TokenKind size" {
    try std.testing.expectEqual(@as(usize, 1), @sizeOf(TokenKind));
}

test "TokenKind categorization" {
    try std.testing.expect(TokenKind.whitespace.isTrivia());
    try std.testing.expect(TokenKind.comment.isTrivia());
    try std.testing.expect(!TokenKind.identifier.isTrivia());

    try std.testing.expect(TokenKind.left_brace.isDelimiter());
    try std.testing.expect(TokenKind.left_brace.isOpenDelimiter());
    try std.testing.expect(!TokenKind.left_brace.isCloseDelimiter());

    try std.testing.expect(TokenKind.right_brace.isDelimiter());
    try std.testing.expect(TokenKind.right_brace.isCloseDelimiter());
    try std.testing.expect(!TokenKind.right_brace.isOpenDelimiter());

    try std.testing.expect(TokenKind.keyword_if.isKeyword());
    try std.testing.expect(!TokenKind.identifier.isKeyword());

    try std.testing.expect(TokenKind.plus.isOperator());
    try std.testing.expect(!TokenKind.comma.isOperator());

    try std.testing.expect(TokenKind.string.isLiteral());
    try std.testing.expect(TokenKind.number.isLiteral());
    try std.testing.expect(!TokenKind.plus.isLiteral());
}
