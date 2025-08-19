const std = @import("std");
const char = @import("../../char/mod.zig");

/// Lexer utilities - mostly deprecated in favor of char module
/// This file exists for backward compatibility
/// New code should import char module directly
pub const LexerUtils = struct {
    /// @deprecated - use char.skipWhitespace
    pub const skipWhitespace = char.skipWhitespace;

    /// @deprecated - use char.skipWhitespaceAndNewlines
    pub const skipWhitespaceAndNewlines = char.skipWhitespaceAndNewlines;

    /// @deprecated - use char.consumeString
    pub const consumeString = char.consumeString;

    /// @deprecated - use char.consumeNumber
    pub const consumeNumber = char.consumeNumber;

    /// @deprecated - use char.consumeIdentifier
    pub const consumeIdentifier = char.consumeIdentifier;

    /// @deprecated - use char.consumeSingleLineComment
    pub const consumeSingleLineComment = char.consumeSingleLineComment;

    /// @deprecated - use char.consumeMultiLineComment
    pub const consumeMultiLineComment = char.consumeMultiLineComment;

    // Character predicates - all deprecated
    /// @deprecated - use char.isDigit
    pub const isDigit = char.isDigit;

    /// @deprecated - use char.isHexDigit
    pub const isHexDigit = char.isHexDigit;

    /// @deprecated - use char.isBinaryDigit
    pub const isBinaryDigit = char.isBinaryDigit;

    /// @deprecated - use char.isOctalDigit
    pub const isOctalDigit = char.isOctalDigit;

    /// @deprecated - use char.isAlpha
    pub const isAlpha = char.isAlpha;

    /// @deprecated - use char.isAlphaNumeric
    pub const isAlphaNum = char.isAlphaNumeric;

    /// @deprecated - use char.isWhitespace
    pub const isWhitespace = char.isWhitespace;

    /// @deprecated - use char.isNewline
    pub const isNewline = char.isNewline;

    /// @deprecated - use char.isIdentifierStart
    pub const isIdentifierStart = char.isIdentifierStart;

    /// @deprecated - use char.isIdentifierChar
    pub const isIdentifierChar = char.isIdentifierChar;
};

test {
    // All tests moved to char module
    _ = @import("../../char/mod.zig");
}
