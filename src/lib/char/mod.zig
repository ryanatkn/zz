/// Character utilities module
/// Single source of truth for character classification and consumption
/// Used by all lexers, parsers, and language implementations
///
/// This module consolidates previously duplicated functionality from:
/// - parser/lexical/utils.zig
/// - parser/lexical/scanner.zig
/// - languages/common/patterns.zig
/// - languages/*/lexer.zig
const std = @import("std");

// Export predicates
pub const predicates = @import("predicates.zig");
pub const isWhitespace = predicates.isWhitespace;
pub const isWhitespaceOrNewline = predicates.isWhitespaceOrNewline;
pub const isNewline = predicates.isNewline;
pub const isDigit = predicates.isDigit;
pub const isHexDigit = predicates.isHexDigit;
pub const isBinaryDigit = predicates.isBinaryDigit;
pub const isOctalDigit = predicates.isOctalDigit;
pub const isAlpha = predicates.isAlpha;
pub const isAlphaNumeric = predicates.isAlphaNumeric;
pub const isIdentifierStart = predicates.isIdentifierStart;
pub const isIdentifierChar = predicates.isIdentifierChar;
pub const isStringDelimiter = predicates.isStringDelimiter;
pub const isOperatorChar = predicates.isOperatorChar;
pub const isDelimiterChar = predicates.isDelimiterChar;
pub const isUpper = predicates.isUpper;
pub const isLower = predicates.isLower;
pub const isControl = predicates.isControl;
pub const isPrintable = predicates.isPrintable;

// Export consumers
pub const consumers = @import("consumers.zig");
pub const skipWhitespace = consumers.skipWhitespace;
pub const skipWhitespaceAndNewlines = consumers.skipWhitespaceAndNewlines;
pub const consumeIdentifier = consumers.consumeIdentifier;
pub const consumeString = consumers.consumeString;
pub const consumeNumber = consumers.consumeNumber;
pub const consumeSingleLineComment = consumers.consumeSingleLineComment;
pub const consumeMultiLineComment = consumers.consumeMultiLineComment;

// Export result types
pub const StringResult = consumers.StringResult;
pub const NumberResult = consumers.NumberResult;
pub const BlockCommentResult = consumers.BlockCommentResult;

test {
    std.testing.refAllDecls(@This());
    _ = @import("predicates.zig");
    _ = @import("consumers.zig");
}
