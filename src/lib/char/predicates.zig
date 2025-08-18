const std = @import("std");

/// Character classification predicates
/// Single source of truth for all character testing across zz
/// All functions are inline for maximum performance

/// Check if character is whitespace (space, tab, carriage return)
/// Does NOT include newline - use isWhitespaceOrNewline for that
pub inline fn isWhitespace(ch: u8) bool {
    return switch (ch) {
        ' ', '\t', '\r' => true,
        else => false,
    };
}

/// Check if character is whitespace or newline
pub inline fn isWhitespaceOrNewline(ch: u8) bool {
    return switch (ch) {
        ' ', '\t', '\r', '\n' => true,
        else => false,
    };
}

/// Check if character is a newline
pub inline fn isNewline(ch: u8) bool {
    return ch == '\n';
}

/// Check if character is a decimal digit (0-9)
pub inline fn isDigit(ch: u8) bool {
    return ch >= '0' and ch <= '9';
}

/// Check if character is a hexadecimal digit (0-9, a-f, A-F)
pub inline fn isHexDigit(ch: u8) bool {
    return switch (ch) {
        '0'...'9', 'a'...'f', 'A'...'F' => true,
        else => false,
    };
}

/// Check if character is a binary digit (0-1)
pub inline fn isBinaryDigit(ch: u8) bool {
    return ch == '0' or ch == '1';
}

/// Check if character is an octal digit (0-7)
pub inline fn isOctalDigit(ch: u8) bool {
    return ch >= '0' and ch <= '7';
}

/// Check if character is alphabetic (a-z, A-Z)
pub inline fn isAlpha(ch: u8) bool {
    return switch (ch) {
        'a'...'z', 'A'...'Z' => true,
        else => false,
    };
}

/// Check if character is alphabetic or digit
pub inline fn isAlphaNumeric(ch: u8) bool {
    return isAlpha(ch) or isDigit(ch);
}

/// Check if character can start an identifier
/// Most languages allow: a-z, A-Z, _, $
pub inline fn isIdentifierStart(ch: u8) bool {
    return switch (ch) {
        'a'...'z', 'A'...'Z', '_', '$' => true,
        else => false,
    };
}

/// Check if character can be part of an identifier
/// Most languages allow: a-z, A-Z, 0-9, _, $
pub inline fn isIdentifierChar(ch: u8) bool {
    return switch (ch) {
        'a'...'z', 'A'...'Z', '0'...'9', '_', '$' => true,
        else => false,
    };
}

/// Check if character is a string delimiter
pub inline fn isStringDelimiter(ch: u8) bool {
    return switch (ch) {
        '"', '\'' => true,
        else => false,
    };
}

/// Check if character is an operator character
pub inline fn isOperatorChar(ch: u8) bool {
    return switch (ch) {
        '+', '-', '*', '/', '%', '=', '!', '<', '>', '&', '|', '^', '~', '?', ':' => true,
        else => false,
    };
}

/// Check if character is a delimiter/punctuation
pub inline fn isDelimiterChar(ch: u8) bool {
    return switch (ch) {
        '(', ')', '{', '}', '[', ']', ';', ',', '.' => true,
        else => false,
    };
}

/// Check if character is uppercase
pub inline fn isUpper(ch: u8) bool {
    return ch >= 'A' and ch <= 'Z';
}

/// Check if character is lowercase
pub inline fn isLower(ch: u8) bool {
    return ch >= 'a' and ch <= 'z';
}

/// Check if character is a control character
pub inline fn isControl(ch: u8) bool {
    return ch < 0x20 or ch == 0x7F;
}

/// Check if character is printable ASCII
pub inline fn isPrintable(ch: u8) bool {
    return ch >= 0x20 and ch < 0x7F;
}

// ============================================================================
// Tests
// ============================================================================

test "predicates - whitespace" {
    try std.testing.expect(isWhitespace(' '));
    try std.testing.expect(isWhitespace('\t'));
    try std.testing.expect(isWhitespace('\r'));
    try std.testing.expect(!isWhitespace('\n'));
    try std.testing.expect(!isWhitespace('a'));
}

test "predicates - whitespace or newline" {
    try std.testing.expect(isWhitespaceOrNewline(' '));
    try std.testing.expect(isWhitespaceOrNewline('\n'));
    try std.testing.expect(!isWhitespaceOrNewline('a'));
}

test "predicates - digits" {
    try std.testing.expect(isDigit('0'));
    try std.testing.expect(isDigit('9'));
    try std.testing.expect(!isDigit('a'));
    
    try std.testing.expect(isHexDigit('0'));
    try std.testing.expect(isHexDigit('a'));
    try std.testing.expect(isHexDigit('F'));
    try std.testing.expect(!isHexDigit('g'));
    
    try std.testing.expect(isBinaryDigit('0'));
    try std.testing.expect(isBinaryDigit('1'));
    try std.testing.expect(!isBinaryDigit('2'));
}

test "predicates - identifiers" {
    try std.testing.expect(isIdentifierStart('a'));
    try std.testing.expect(isIdentifierStart('Z'));
    try std.testing.expect(isIdentifierStart('_'));
    try std.testing.expect(isIdentifierStart('$'));
    try std.testing.expect(!isIdentifierStart('0'));
    
    try std.testing.expect(isIdentifierChar('a'));
    try std.testing.expect(isIdentifierChar('0'));
    try std.testing.expect(isIdentifierChar('_'));
    try std.testing.expect(!isIdentifierChar('-'));
}

test "predicates - operators and delimiters" {
    try std.testing.expect(isOperatorChar('+'));
    try std.testing.expect(isOperatorChar('='));
    try std.testing.expect(!isOperatorChar('('));
    
    try std.testing.expect(isDelimiterChar('('));
    try std.testing.expect(isDelimiterChar(';'));
    try std.testing.expect(!isDelimiterChar('+'));
}