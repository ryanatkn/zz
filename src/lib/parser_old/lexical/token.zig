const std = @import("std");

/// Basic token structure for lexical analysis
pub const Token = struct {
    kind: TokenKind,
    text: []const u8,
    start_position: usize,
    end_position: usize,

    pub fn length(self: Token) usize {
        return self.end_position - self.start_position;
    }
};

/// Token kinds for lexical categorization
pub const TokenKind = enum {
    identifier,
    keyword,
    operator,
    literal,
    string_literal,
    number_literal,
    delimiter,
    whitespace,
    comment,
    newline,
    eof,
    unknown,
};
