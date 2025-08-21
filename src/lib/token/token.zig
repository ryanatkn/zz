/// Base token definition
///
/// Fundamental token type used by parsers and lexers.
const std = @import("std");
const Span = @import("../span/span.zig").Span;

/// Base token structure
pub const Token = struct {
    /// Location in source
    span: Span,
    /// Token category
    kind: TokenKind,
    /// Nesting depth for brackets/braces
    depth: u8 = 0,
    /// Additional flags
    flags: TokenFlags = .{},

    /// Get token text from source
    pub fn getText(self: Token, source: []const u8) []const u8 {
        const start = @min(self.span.start, source.len);
        const end = @min(self.span.end, source.len);
        return source[start..end];
    }

    /// Check if token is of given kind
    pub fn is(self: Token, kind: TokenKind) bool {
        return self.kind == kind;
    }

    /// Check if token is any of given kinds
    pub fn isAny(self: Token, kinds: []const TokenKind) bool {
        for (kinds) |kind| {
            if (self.kind == kind) return true;
        }
        return false;
    }
};

/// Token categories
pub const TokenKind = enum(u8) {
    // Literals
    identifier,
    string,
    number,
    boolean,
    null,

    // Keywords
    keyword,

    // Operators
    plus,
    minus,
    star,
    slash,
    percent,
    equal,
    not_equal,
    less_than,
    greater_than,
    less_equal,
    greater_equal,

    // Punctuation
    comma,
    semicolon,
    colon,
    dot,
    arrow,

    // Delimiters
    left_paren,
    right_paren,
    left_brace,
    right_brace,
    left_bracket,
    right_bracket,

    // Whitespace
    whitespace,
    newline,

    // Comments
    comment,
    doc_comment,

    // Special
    eof,
    err,
    unknown,

    /// Check if token kind is a delimiter
    pub fn isDelimiter(self: TokenKind) bool {
        return switch (self) {
            .left_paren, .right_paren, .left_brace, .right_brace, .left_bracket, .right_bracket => true,
            else => false,
        };
    }

    /// Check if token kind is an opening delimiter
    pub fn isOpening(self: TokenKind) bool {
        return switch (self) {
            .left_paren, .left_brace, .left_bracket => true,
            else => false,
        };
    }

    /// Check if token kind is a closing delimiter
    pub fn isClosing(self: TokenKind) bool {
        return switch (self) {
            .right_paren, .right_brace, .right_bracket => true,
            else => false,
        };
    }

    /// Get matching delimiter
    pub fn getMatchingDelimiter(self: TokenKind) ?TokenKind {
        return switch (self) {
            .left_paren => .right_paren,
            .right_paren => .left_paren,
            .left_brace => .right_brace,
            .right_brace => .left_brace,
            .left_bracket => .right_bracket,
            .right_bracket => .left_bracket,
            else => null,
        };
    }
};

/// Token flags for additional metadata
pub const TokenFlags = packed struct {
    /// Token has trailing whitespace
    has_trailing_space: bool = false,
    /// Token has leading whitespace
    has_leading_space: bool = false,
    /// Token is first on line
    is_line_start: bool = false,
    /// Token is last on line
    is_line_end: bool = false,
    /// Token has escape sequences
    has_escapes: bool = false,
    /// Token is synthetic (inserted by parser)
    is_synthetic: bool = false,
    /// Reserved for future use
    _reserved: u2 = 0,
};
