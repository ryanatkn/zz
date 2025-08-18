const std = @import("std");
const predicates = @import("predicates.zig");
const Token = @import("../parser/foundation/types/token.zig").Token;

/// Text consumption utilities
/// Functions for consuming/skipping sequences of characters
/// All functions work with slices and return positions

/// Skip whitespace characters and return the new position
pub fn skipWhitespace(source: []const u8, pos: usize) usize {
    var current = pos;
    while (current < source.len) : (current += 1) {
        if (!predicates.isWhitespace(source[current])) {
            break;
        }
    }
    return current;
}

/// Skip whitespace and newlines, return the new position
pub fn skipWhitespaceAndNewlines(source: []const u8, pos: usize) usize {
    var current = pos;
    while (current < source.len) : (current += 1) {
        if (!predicates.isWhitespaceOrNewline(source[current])) {
            break;
        }
    }
    return current;
}

/// Consume an identifier starting at the given position
/// Returns the end position of the identifier
pub fn consumeIdentifier(source: []const u8, pos: usize) usize {
    if (pos >= source.len or !predicates.isIdentifierStart(source[pos])) {
        return pos;
    }
    
    var current = pos + 1;
    while (current < source.len and predicates.isIdentifierChar(source[current])) {
        current += 1;
    }
    
    return current;
}

/// Result of consuming a string literal
pub const StringResult = struct {
    end: usize,
    terminated: bool,
    has_escapes: bool = false,
};

/// Consume a string literal with the given quote character
/// Handles escape sequences if allow_escapes is true
pub fn consumeString(source: []const u8, start_pos: usize, quote: u8, allow_escapes: bool) StringResult {
    if (start_pos >= source.len or source[start_pos] != quote) {
        return .{ .end = start_pos, .terminated = false };
    }
    
    var pos = start_pos + 1;
    var has_escapes = false;
    
    while (pos < source.len) {
        const ch = source[pos];
        
        if (ch == quote) {
            return .{ .end = pos + 1, .terminated = true, .has_escapes = has_escapes };
        }
        
        if (allow_escapes and ch == '\\' and pos + 1 < source.len) {
            has_escapes = true;
            pos += 2; // Skip escape sequence
        } else {
            pos += 1;
        }
    }
    
    // Unterminated string
    return .{ .end = pos, .terminated = false, .has_escapes = has_escapes };
}

/// Result of consuming a number
pub const NumberResult = struct {
    end: usize,
    is_float: bool = false,
    is_hex: bool = false,
    is_binary: bool = false,
    is_octal: bool = false,
};

/// Consume a numeric literal
/// Handles integers, floats, hex (0x), binary (0b), octal (0o)
pub fn consumeNumber(source: []const u8, start_pos: usize) NumberResult {
    if (start_pos >= source.len) {
        return .{ .end = start_pos };
    }
    
    var pos = start_pos;
    var result = NumberResult{ .end = start_pos };
    
    // Handle negative sign
    if (pos < source.len and source[pos] == '-') {
        pos += 1;
    }
    
    if (pos >= source.len or !predicates.isDigit(source[pos])) {
        return result;
    }
    
    // Check for hex/binary/octal prefix
    if (source[pos] == '0' and pos + 1 < source.len) {
        const next = source[pos + 1];
        if (next == 'x' or next == 'X') {
            // Hexadecimal
            pos += 2;
            const hex_start = pos;
            while (pos < source.len and predicates.isHexDigit(source[pos])) {
                pos += 1;
            }
            if (pos > hex_start) {
                result.is_hex = true;
                result.end = pos;
                return result;
            }
            return .{ .end = start_pos }; // Invalid hex number
        } else if (next == 'b' or next == 'B') {
            // Binary
            pos += 2;
            const bin_start = pos;
            while (pos < source.len and predicates.isBinaryDigit(source[pos])) {
                pos += 1;
            }
            if (pos > bin_start) {
                result.is_binary = true;
                result.end = pos;
                return result;
            }
            return .{ .end = start_pos }; // Invalid binary number
        } else if (next == 'o' or next == 'O') {
            // Octal
            pos += 2;
            const oct_start = pos;
            while (pos < source.len and predicates.isOctalDigit(source[pos])) {
                pos += 1;
            }
            if (pos > oct_start) {
                result.is_octal = true;
                result.end = pos;
                return result;
            }
            return .{ .end = start_pos }; // Invalid octal number
        }
    }
    
    // Consume integer part
    while (pos < source.len and predicates.isDigit(source[pos])) {
        pos += 1;
    }
    
    // Check for decimal point
    if (pos < source.len and source[pos] == '.' and 
        pos + 1 < source.len and predicates.isDigit(source[pos + 1])) {
        result.is_float = true;
        pos += 1; // Skip '.'
        
        // Consume fractional part
        while (pos < source.len and predicates.isDigit(source[pos])) {
            pos += 1;
        }
    }
    
    // Check for exponent
    if (pos < source.len and (source[pos] == 'e' or source[pos] == 'E')) {
        result.is_float = true;
        pos += 1;
        
        // Handle optional sign
        if (pos < source.len and (source[pos] == '+' or source[pos] == '-')) {
            pos += 1;
        }
        
        // Must have at least one digit
        if (pos >= source.len or !predicates.isDigit(source[pos])) {
            return .{ .end = start_pos }; // Invalid exponent
        }
        
        while (pos < source.len and predicates.isDigit(source[pos])) {
            pos += 1;
        }
    }
    
    result.end = pos;
    return result;
}

/// Consume a single-line comment starting with the given prefix
/// Returns the position after the comment (including newline if present)
pub fn consumeSingleLineComment(source: []const u8, start_pos: usize, prefix: []const u8) usize {
    if (start_pos + prefix.len > source.len) {
        return start_pos;
    }
    
    // Check for comment prefix
    if (!std.mem.eql(u8, source[start_pos .. start_pos + prefix.len], prefix)) {
        return start_pos;
    }
    
    var pos = start_pos + prefix.len;
    
    // Consume until end of line
    while (pos < source.len and source[pos] != '\n') {
        pos += 1;
    }
    
    // Include the newline if present
    if (pos < source.len and source[pos] == '\n') {
        pos += 1;
    }
    
    return pos;
}

/// Result of consuming a block comment
pub const BlockCommentResult = struct {
    end: usize,
    terminated: bool,
    line_count: usize = 0,
};

/// Consume a multi-line block comment
/// Returns the position after the comment and whether it was properly terminated
pub fn consumeMultiLineComment(source: []const u8, start_pos: usize, start_delim: []const u8, end_delim: []const u8) BlockCommentResult {
    if (start_pos + start_delim.len > source.len) {
        return .{ .end = start_pos, .terminated = false };
    }
    
    // Check for comment start
    if (!std.mem.eql(u8, source[start_pos .. start_pos + start_delim.len], start_delim)) {
        return .{ .end = start_pos, .terminated = false };
    }
    
    var pos = start_pos + start_delim.len;
    var line_count: usize = 0;
    
    // Scan for end delimiter
    while (pos + end_delim.len <= source.len) {
        if (std.mem.eql(u8, source[pos .. pos + end_delim.len], end_delim)) {
            return .{ 
                .end = pos + end_delim.len, 
                .terminated = true,
                .line_count = line_count,
            };
        }
        
        if (source[pos] == '\n') {
            line_count += 1;
        }
        
        pos += 1;
    }
    
    // Unterminated comment
    return .{ 
        .end = source.len, 
        .terminated = false,
        .line_count = line_count,
    };
}

// ============================================================================
// Tests
// ============================================================================

test "consumers - skipWhitespace" {
    const source = "   hello";
    const pos = skipWhitespace(source, 0);
    try std.testing.expectEqual(@as(usize, 3), pos);
    
    const no_ws = "hello";
    const pos2 = skipWhitespace(no_ws, 0);
    try std.testing.expectEqual(@as(usize, 0), pos2);
}

test "consumers - skipWhitespaceAndNewlines" {
    const source = "  \n\t\r\nhello";
    const pos = skipWhitespaceAndNewlines(source, 0);
    try std.testing.expectEqual(@as(usize, 6), pos);
}

test "consumers - consumeIdentifier" {
    const source = "myVariable123 + other";
    const pos = consumeIdentifier(source, 0);
    try std.testing.expectEqual(@as(usize, 13), pos);
    
    const with_dollar = "$scope_var";
    const pos2 = consumeIdentifier(with_dollar, 0);
    try std.testing.expectEqual(@as(usize, 10), pos2);
}

test "consumers - consumeString" {
    const source = "\"hello world\"";
    const result = consumeString(source, 0, '"', true);
    try std.testing.expectEqual(@as(usize, 13), result.end);
    try std.testing.expect(result.terminated);
    
    const with_escape = "\"hello\\nworld\"";
    const result2 = consumeString(with_escape, 0, '"', true);
    try std.testing.expect(result2.has_escapes);
    
    const unterminated = "\"hello";
    const result3 = consumeString(unterminated, 0, '"', true);
    try std.testing.expect(!result3.terminated);
}

test "consumers - consumeNumber" {
    const integer = "12345";
    const result1 = consumeNumber(integer, 0);
    try std.testing.expectEqual(@as(usize, 5), result1.end);
    try std.testing.expect(!result1.is_float);
    
    const float = "123.456";
    const result2 = consumeNumber(float, 0);
    try std.testing.expectEqual(@as(usize, 7), result2.end);
    try std.testing.expect(result2.is_float);
    
    const hex = "0xFF";
    const result3 = consumeNumber(hex, 0);
    try std.testing.expectEqual(@as(usize, 4), result3.end);
    try std.testing.expect(result3.is_hex);
    
    const binary = "0b1010";
    const result4 = consumeNumber(binary, 0);
    try std.testing.expectEqual(@as(usize, 6), result4.end);
    try std.testing.expect(result4.is_binary);
    
    const scientific = "1.5e10";
    const result5 = consumeNumber(scientific, 0);
    try std.testing.expectEqual(@as(usize, 6), result5.end);
    try std.testing.expect(result5.is_float);
}

test "consumers - comments" {
    const single_line = "// This is a comment\nNext line";
    const pos = consumeSingleLineComment(single_line, 0, "//");
    try std.testing.expectEqual(@as(usize, 21), pos);
    
    const block = "/* multi\nline\ncomment */rest";
    const result = consumeMultiLineComment(block, 0, "/*", "*/");
    try std.testing.expectEqual(@as(usize, 24), result.end);
    try std.testing.expect(result.terminated);
    try std.testing.expectEqual(@as(usize, 2), result.line_count);
}