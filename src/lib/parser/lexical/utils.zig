const std = @import("std");
const Token = @import("../foundation/types/token.zig").Token;
const TokenKind = @import("../foundation/types/token.zig").TokenKind;

/// Shared lexer utilities for all language implementations
/// Provides common tokenization helpers to avoid duplication
pub const LexerUtils = struct {
    /// Skip whitespace characters and return the new position
    pub fn skipWhitespace(source: []const u8, pos: usize) usize {
        var current = pos;
        while (current < source.len) : (current += 1) {
            const ch = source[current];
            if (!isWhitespace(ch)) {
                break;
            }
        }
        return current;
    }

    /// Skip whitespace and newlines, return the new position
    pub fn skipWhitespaceAndNewlines(source: []const u8, pos: usize) usize {
        var current = pos;
        while (current < source.len) : (current += 1) {
            const ch = source[current];
            if (!isWhitespace(ch) and ch != '\n' and ch != '\r') {
                break;
            }
        }
        return current;
    }

    /// Consume a string literal starting at pos with the given quote character
    /// Returns the token including the quotes, or error if unterminated
    pub fn consumeString(
        source: []const u8,
        start_pos: usize,
        quote: u8,
        allow_escapes: bool,
    ) !Token {
        if (start_pos >= source.len or source[start_pos] != quote) {
            return error.InvalidStringStart;
        }

        var pos = start_pos + 1;
        var escaped = false;

        while (pos < source.len) : (pos += 1) {
            const ch = source[pos];

            if (allow_escapes and escaped) {
                escaped = false;
                continue;
            }

            if (allow_escapes and ch == '\\') {
                escaped = true;
                continue;
            }

            if (ch == quote) {
                // Found closing quote
                return Token{
                    .kind = .string,
                    .text = source[start_pos .. pos + 1],
                };
            }

            if (ch == '\n' and !allow_escapes) {
                // Newline in string without escape support
                return error.UnterminatedString;
            }
        }

        return error.UnterminatedString;
    }

    /// Consume a number (integer or float) starting at pos
    /// Supports decimal, hex (0x), binary (0b), and octal (0o) formats
    pub fn consumeNumber(source: []const u8, start_pos: usize) !Token {
        if (start_pos >= source.len) {
            return error.InvalidNumberStart;
        }

        var pos = start_pos;
        const first_char = source[pos];

        if (!isDigit(first_char) and first_char != '-' and first_char != '+') {
            return error.InvalidNumberStart;
        }

        // Handle sign
        if (first_char == '-' or first_char == '+') {
            pos += 1;
            if (pos >= source.len or !isDigit(source[pos])) {
                return error.InvalidNumberStart;
            }
        }

        // Check for hex, binary, or octal
        if (pos < source.len - 1 and source[pos] == '0') {
            const next = source[pos + 1];
            switch (next) {
                'x', 'X' => {
                    // Hexadecimal
                    pos += 2;
                    if (pos >= source.len or !isHexDigit(source[pos])) {
                        return error.InvalidHexNumber;
                    }
                    while (pos < source.len and isHexDigit(source[pos])) : (pos += 1) {}
                    return Token{
                        .kind = .number,
                        .text = source[start_pos..pos],
                    };
                },
                'b', 'B' => {
                    // Binary
                    pos += 2;
                    if (pos >= source.len or !isBinaryDigit(source[pos])) {
                        return error.InvalidBinaryNumber;
                    }
                    while (pos < source.len and isBinaryDigit(source[pos])) : (pos += 1) {}
                    return Token{
                        .kind = .number,
                        .text = source[start_pos..pos],
                    };
                },
                'o', 'O' => {
                    // Octal
                    pos += 2;
                    if (pos >= source.len or !isOctalDigit(source[pos])) {
                        return error.InvalidOctalNumber;
                    }
                    while (pos < source.len and isOctalDigit(source[pos])) : (pos += 1) {}
                    return Token{
                        .kind = .number,
                        .text = source[start_pos..pos],
                    };
                },
                else => {},
            }
        }

        // Consume integer part
        while (pos < source.len and isDigit(source[pos])) : (pos += 1) {}

        // Check for decimal point
        if (pos < source.len and source[pos] == '.') {
            // Make sure there's at least one digit after the decimal
            if (pos + 1 < source.len and isDigit(source[pos + 1])) {
                pos += 1; // Skip the decimal point
                while (pos < source.len and isDigit(source[pos])) : (pos += 1) {}
            }
        }

        // Check for exponent
        if (pos < source.len and (source[pos] == 'e' or source[pos] == 'E')) {
            pos += 1;
            if (pos < source.len and (source[pos] == '+' or source[pos] == '-')) {
                pos += 1;
            }
            if (pos >= source.len or !isDigit(source[pos])) {
                // Invalid exponent
                pos -= 1; // Back up
                if (source[pos] == '+' or source[pos] == '-') {
                    pos -= 1; // Back up more
                }
            } else {
                while (pos < source.len and isDigit(source[pos])) : (pos += 1) {}
            }
        }

        return Token{
            .kind = .number,
            .text = source[start_pos..pos],
        };
    }

    /// Consume an identifier starting at pos
    /// Identifiers start with alpha or underscore, continue with alphanumeric or underscore
    pub fn consumeIdentifier(source: []const u8, start_pos: usize) !Token {
        if (start_pos >= source.len) {
            return error.InvalidIdentifierStart;
        }

        const first = source[start_pos];
        if (!isAlpha(first) and first != '_') {
            return error.InvalidIdentifierStart;
        }

        var pos = start_pos + 1;
        while (pos < source.len) : (pos += 1) {
            const ch = source[pos];
            if (!isAlphaNum(ch) and ch != '_') {
                break;
            }
        }

        return Token{
            .kind = .identifier,
            .text = source[start_pos..pos],
        };
    }

    /// Consume a single-line comment starting with the given prefix
    pub fn consumeSingleLineComment(source: []const u8, start_pos: usize, prefix: []const u8) !Token {
        if (start_pos + prefix.len > source.len) {
            return error.InvalidCommentStart;
        }

        if (!std.mem.startsWith(u8, source[start_pos..], prefix)) {
            return error.InvalidCommentStart;
        }

        var pos = start_pos + prefix.len;
        while (pos < source.len and source[pos] != '\n') : (pos += 1) {}

        return Token{
            .kind = .comment,
            .text = source[start_pos..pos],
        };
    }

    /// Consume a multi-line comment with given start and end delimiters
    pub fn consumeMultiLineComment(
        source: []const u8,
        start_pos: usize,
        start_delim: []const u8,
        end_delim: []const u8,
    ) !Token {
        if (start_pos + start_delim.len > source.len) {
            return error.InvalidCommentStart;
        }

        if (!std.mem.startsWith(u8, source[start_pos..], start_delim)) {
            return error.InvalidCommentStart;
        }

        var pos = start_pos + start_delim.len;
        while (pos < source.len) : (pos += 1) {
            if (pos + end_delim.len <= source.len) {
                if (std.mem.startsWith(u8, source[pos..], end_delim)) {
                    pos += end_delim.len;
                    return Token{
                        .kind = .comment,
                        .text = source[start_pos..pos],
                    };
                }
            }
        }

        return error.UnterminatedComment;
    }

    // Character predicate functions

    pub fn isDigit(ch: u8) bool {
        return ch >= '0' and ch <= '9';
    }

    pub fn isHexDigit(ch: u8) bool {
        return isDigit(ch) or
            (ch >= 'a' and ch <= 'f') or
            (ch >= 'A' and ch <= 'F');
    }

    pub fn isBinaryDigit(ch: u8) bool {
        return ch == '0' or ch == '1';
    }

    pub fn isOctalDigit(ch: u8) bool {
        return ch >= '0' and ch <= '7';
    }

    pub fn isAlpha(ch: u8) bool {
        return (ch >= 'a' and ch <= 'z') or
            (ch >= 'A' and ch <= 'Z');
    }

    pub fn isAlphaNum(ch: u8) bool {
        return isAlpha(ch) or isDigit(ch);
    }

    pub fn isWhitespace(ch: u8) bool {
        return ch == ' ' or ch == '\t' or ch == '\r';
    }

    pub fn isNewline(ch: u8) bool {
        return ch == '\n';
    }

    pub fn isIdentifierStart(ch: u8) bool {
        return isAlpha(ch) or ch == '_';
    }

    pub fn isIdentifierChar(ch: u8) bool {
        return isAlphaNum(ch) or ch == '_';
    }
};

// Tests
test "LexerUtils - skipWhitespace" {
    const source = "   hello";
    const pos = LexerUtils.skipWhitespace(source, 0);
    try std.testing.expectEqual(@as(usize, 3), pos);
}

test "LexerUtils - consumeString" {
    const source = "\"hello world\"";
    const token = try LexerUtils.consumeString(source, 0, '"', true);
    try std.testing.expectEqualStrings("\"hello world\"", token.text);
    try std.testing.expectEqual(TokenKind.string, token.kind);
}

test "LexerUtils - consumeString with escapes" {
    const source = "\"hello\\\"world\"";
    const token = try LexerUtils.consumeString(source, 0, '"', true);
    try std.testing.expectEqualStrings("\"hello\\\"world\"", token.text);
}

test "LexerUtils - consumeNumber decimal" {
    const source = "123.456";
    const token = try LexerUtils.consumeNumber(source, 0);
    try std.testing.expectEqualStrings("123.456", token.text);
    try std.testing.expectEqual(TokenKind.number, token.kind);
}

test "LexerUtils - consumeNumber hex" {
    const source = "0xFF";
    const token = try LexerUtils.consumeNumber(source, 0);
    try std.testing.expectEqualStrings("0xFF", token.text);
}

test "LexerUtils - consumeNumber binary" {
    const source = "0b1010";
    const token = try LexerUtils.consumeNumber(source, 0);
    try std.testing.expectEqualStrings("0b1010", token.text);
}

test "LexerUtils - consumeIdentifier" {
    const source = "myVariable123";
    const token = try LexerUtils.consumeIdentifier(source, 0);
    try std.testing.expectEqualStrings("myVariable123", token.text);
    try std.testing.expectEqual(TokenKind.identifier, token.kind);
}

test "LexerUtils - consumeSingleLineComment" {
    const source = "// This is a comment\nnext line";
    const token = try LexerUtils.consumeSingleLineComment(source, 0, "//");
    try std.testing.expectEqualStrings("// This is a comment", token.text);
    try std.testing.expectEqual(TokenKind.comment, token.kind);
}

test "LexerUtils - consumeMultiLineComment" {
    const source = "/* multi\nline\ncomment */";
    const token = try LexerUtils.consumeMultiLineComment(source, 0, "/*", "*/");
    try std.testing.expectEqualStrings("/* multi\nline\ncomment */", token.text);
    try std.testing.expectEqual(TokenKind.comment, token.kind);
}

test "LexerUtils - character predicates" {
    try std.testing.expect(LexerUtils.isDigit('5'));
    try std.testing.expect(!LexerUtils.isDigit('a'));
    
    try std.testing.expect(LexerUtils.isHexDigit('F'));
    try std.testing.expect(LexerUtils.isHexDigit('9'));
    try std.testing.expect(!LexerUtils.isHexDigit('G'));
    
    try std.testing.expect(LexerUtils.isAlpha('z'));
    try std.testing.expect(LexerUtils.isAlpha('A'));
    try std.testing.expect(!LexerUtils.isAlpha('1'));
    
    try std.testing.expect(LexerUtils.isWhitespace(' '));
    try std.testing.expect(LexerUtils.isWhitespace('\t'));
    try std.testing.expect(!LexerUtils.isWhitespace('a'));
}