/// ZON-specific patterns and delimiters
///
/// This module defines ZON-specific syntax patterns that differ from JSON.
/// ZON (Zig Object Notation) supports additional features like:
/// - Field names with dot notation (.field_name)
/// - Quoted identifiers (@"name")
/// - Anonymous struct/list syntax
/// - Zig-style comments
const std = @import("std");

/// ZON delimiters and structural tokens
pub const ZonDelimiters = struct {
    pub const OBJECT_START = '{';
    pub const OBJECT_END = '}';
    pub const ARRAY_START = '[';
    pub const ARRAY_END = ']';
    pub const FIELD_SEPARATOR = '=';
    pub const ELEMENT_SEPARATOR = ',';
    pub const FIELD_NAME_PREFIX = '.';
    pub const STRING_DELIMITER = '"';

    // ZON-specific
    pub const QUOTED_IDENTIFIER_PREFIX = '@';
    pub const COMMENT_LINE = "//";
    pub const COMMENT_MULTILINE_START = "/*";
    pub const COMMENT_MULTILINE_END = "*/";
};

/// Check if character can start a ZON identifier
pub fn isIdentifierStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_';
}

/// Check if character can continue a ZON identifier
pub fn isIdentifierContinue(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

/// Check if character is ZON whitespace
pub fn isWhitespace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r';
}

/// Check if character can start a number in ZON
pub fn isNumberStart(c: u8) bool {
    return std.ascii.isDigit(c) or c == '-' or c == '+';
}

/// Check if two characters form a line comment start
pub fn isLineCommentStart(a: u8, b: u8) bool {
    return a == '/' and b == '/';
}

/// Check if two characters form a multiline comment start
pub fn isMultilineCommentStart(a: u8, b: u8) bool {
    return a == '/' and b == '*';
}

/// Check if two characters form a multiline comment end
pub fn isMultilineCommentEnd(a: u8, b: u8) bool {
    return a == '*' and b == '/';
}
