const std = @import("std");
const char = @import("../../char/mod.zig");

/// Character-level scanner with UTF-8 support and SIMD preparation
///
/// The Scanner provides efficient character-by-character reading with:
/// - UTF-8 validation and handling
/// - Lookahead capabilities
/// - Fast character classification
/// - Preparation for future SIMD optimizations
pub const Scanner = struct {
    /// Source text being scanned
    text: []const u8,

    /// Current position in text
    position: usize,

    /// Start position of current token
    token_start: usize,

    /// Cached current character
    current_char: u8,

    /// Cached next character (lookahead)
    next_char: u8,

    /// Whether we've reached end of input
    at_end: bool,

    /// Character classification table for fast lookup
    char_table: [256]CharClass,

    pub fn init() Scanner {
        var scanner = Scanner{
            .text = "",
            .position = 0,
            .token_start = 0,
            .current_char = 0,
            .next_char = 0,
            .at_end = true,
            .char_table = undefined,
        };

        scanner.initCharTable();
        return scanner;
    }

    /// Reset scanner with new text and position
    pub fn reset(self: *Scanner, text: []const u8, start_pos: usize) void {
        self.text = text;
        self.position = start_pos;
        self.token_start = start_pos;
        self.at_end = start_pos >= text.len;

        if (!self.at_end) {
            self.current_char = text[start_pos];
            self.next_char = if (start_pos + 1 < text.len) text[start_pos + 1] else 0;
        } else {
            self.current_char = 0;
            self.next_char = 0;
        }
    }

    /// Peek at current character without advancing
    pub fn peek(self: Scanner) u8 {
        return if (self.at_end) 0 else self.current_char;
    }

    /// Peek at next character without advancing
    pub fn peekNext(self: Scanner) u8 {
        return if (self.position + 1 >= self.text.len) 0 else self.next_char;
    }

    /// Peek ahead by offset characters
    pub fn peekAhead(self: Scanner, offset: usize) u8 {
        const pos = self.position + offset;
        return if (pos >= self.text.len) 0 else self.text[pos];
    }

    /// Advance to next character
    pub fn advance(self: *Scanner) u8 {
        if (self.at_end) return 0;

        const prev_char = self.current_char;
        self.position += 1;

        if (self.position >= self.text.len) {
            self.at_end = true;
            self.current_char = 0;
            self.next_char = 0;
        } else {
            self.current_char = self.text[self.position];
            self.next_char = if (self.position + 1 < self.text.len) self.text[self.position + 1] else 0;
        }

        return prev_char;
    }

    /// Advance if current character matches expected
    pub fn match(self: *Scanner, expected: u8) bool {
        if (self.peek() != expected) return false;
        _ = self.advance();
        return true;
    }

    /// Mark the start of a new token
    pub fn markTokenStart(self: *Scanner) void {
        self.token_start = self.position;
    }

    /// Get text of current token
    pub fn getCurrentText(self: Scanner) []const u8 {
        return self.text[self.token_start..self.position];
    }

    /// Get length of current token
    pub fn getCurrentLength(self: Scanner) usize {
        return self.position - self.token_start;
    }

    /// Skip whitespace characters
    pub fn skipWhitespace(self: *Scanner) void {
        const new_pos = char.skipWhitespaceAndNewlines(self.text, self.position);
        while (self.position < new_pos) {
            _ = self.advance();
        }
    }

    /// Skip to end of line comment
    pub fn skipLineComment(self: *Scanner) void {
        // Skip the "//"
        _ = self.advance();
        _ = self.advance();

        // Skip to end of line
        while (!self.at_end and self.current_char != '\n') {
            _ = self.advance();
        }
    }

    /// Skip block comment
    pub fn skipBlockComment(self: *Scanner) !void {
        // Skip the "/*"
        _ = self.advance();
        _ = self.advance();

        while (!self.at_end) {
            if (self.current_char == '*' and self.next_char == '/') {
                _ = self.advance(); // Skip '*'
                _ = self.advance(); // Skip '/'
                return;
            }
            _ = self.advance();
        }

        // Unterminated comment
        return error.UnterminatedComment;
    }

    /// Scan a string literal
    pub fn scanString(self: *Scanner, quote: u8) !void {
        _ = self.advance(); // Skip opening quote

        while (!self.at_end and self.current_char != quote) {
            if (self.current_char == '\\') {
                _ = self.advance(); // Skip escape character
                if (!self.at_end) {
                    _ = self.advance(); // Skip escaped character
                }
            } else {
                _ = self.advance();
            }
        }

        if (self.at_end) {
            return error.UnterminatedString;
        }

        _ = self.advance(); // Skip closing quote
    }

    /// Scan a numeric literal
    pub fn scanNumber(self: *Scanner) !void {
        // Handle hex numbers
        if (self.current_char == '0' and (self.next_char == 'x' or self.next_char == 'X')) {
            _ = self.advance(); // Skip '0'
            _ = self.advance(); // Skip 'x'

            while (!self.at_end and self.isHexDigit(self.current_char)) {
                _ = self.advance();
            }
            return;
        }

        // Handle binary numbers
        if (self.current_char == '0' and (self.next_char == 'b' or self.next_char == 'B')) {
            _ = self.advance(); // Skip '0'
            _ = self.advance(); // Skip 'b'

            while (!self.at_end and self.isBinaryDigit(self.current_char)) {
                _ = self.advance();
            }
            return;
        }

        // Handle decimal numbers
        while (!self.at_end and (self.isDigit(self.current_char) or self.current_char == '_')) {
            _ = self.advance();
        }

        // Handle decimal point
        if (!self.at_end and self.current_char == '.' and self.isDigit(self.next_char)) {
            _ = self.advance(); // Skip '.'
            while (!self.at_end and (self.isDigit(self.current_char) or self.current_char == '_')) {
                _ = self.advance();
            }
        }

        // Handle exponent
        if (!self.at_end and (self.current_char == 'e' or self.current_char == 'E')) {
            _ = self.advance(); // Skip 'e'

            if (!self.at_end and (self.current_char == '+' or self.current_char == '-')) {
                _ = self.advance(); // Skip sign
            }

            while (!self.at_end and self.isDigit(self.current_char)) {
                _ = self.advance();
            }
        }
    }

    /// Scan an identifier
    pub fn scanIdentifier(self: *Scanner) !void {
        while (!self.at_end and self.isIdentifierChar(self.current_char)) {
            _ = self.advance();
        }
    }

    /// Scan an operator
    pub fn scanOperator(self: *Scanner) !void {
        const first_char = self.current_char;
        _ = self.advance();

        // Handle multi-character operators
        switch (first_char) {
            '=' => {
                if (self.current_char == '=') _ = self.advance();
            },
            '!' => {
                if (self.current_char == '=') _ = self.advance();
            },
            '<' => {
                if (self.current_char == '=' or self.current_char == '<') _ = self.advance();
            },
            '>' => {
                if (self.current_char == '=' or self.current_char == '>') _ = self.advance();
            },
            '&' => {
                if (self.current_char == '&') _ = self.advance();
            },
            '|' => {
                if (self.current_char == '|') _ = self.advance();
            },
            '+' => {
                if (self.current_char == '+' or self.current_char == '=') _ = self.advance();
            },
            '-' => {
                if (self.current_char == '-' or self.current_char == '=' or self.current_char == '>') _ = self.advance();
            },
            '*' => {
                if (self.current_char == '=') _ = self.advance();
            },
            '/' => {
                if (self.current_char == '=') _ = self.advance();
            },
            '%' => {
                if (self.current_char == '=') _ = self.advance();
            },
            '^' => {
                if (self.current_char == '=') _ = self.advance();
            },
            else => {},
        }
    }

    // ========================================================================
    // Character Classification
    // ========================================================================

    /// Check if character is whitespace
    pub fn isWhitespace(self: Scanner, ch: u8) bool {
        _ = self;
        return char.isWhitespace(ch) or char.isNewline(ch);
    }

    /// Check if character is a digit
    pub fn isDigit(self: Scanner, ch: u8) bool {
        _ = self;
        return char.isDigit(ch);
    }

    /// Check if character is a hex digit
    pub fn isHexDigit(self: Scanner, ch: u8) bool {
        _ = self;
        return char.isHexDigit(ch);
    }

    /// Check if character is a binary digit
    pub fn isBinaryDigit(self: Scanner, ch: u8) bool {
        _ = self;
        return char.isBinaryDigit(ch);
    }

    /// Check if character can start an identifier
    pub fn isIdentifierStart(self: Scanner, ch: u8) bool {
        _ = self;
        return char.isIdentifierStart(ch);
    }

    /// Check if character can be part of an identifier
    pub fn isIdentifierChar(self: Scanner, ch: u8) bool {
        _ = self;
        return char.isIdentifierChar(ch);
    }

    /// Check if character is an operator
    pub fn isOperator(self: Scanner, ch: u8) bool {
        return self.char_table[ch] == .operator;
    }

    /// Get current position in bytes
    pub fn getPosition(self: Scanner) usize {
        return self.position;
    }

    /// Get remaining text from current position
    pub fn getRemainingText(self: Scanner) []const u8 {
        return self.text[self.position..];
    }

    /// Check if at end of input
    pub fn isAtEnd(self: Scanner) bool {
        return self.at_end;
    }

    // ========================================================================
    // UTF-8 Support
    // ========================================================================

    /// Get UTF-8 character at current position
    pub fn getCurrentUTF8(self: Scanner) !u21 {
        if (self.at_end) return 0;

        const remaining = self.text[self.position..];
        const len = std.unicode.utf8ByteSequenceLength(self.current_char) catch 1;

        if (len > remaining.len) return error.InvalidUTF8;

        return std.unicode.utf8Decode(remaining[0..len]) catch self.current_char;
    }

    /// Advance by one UTF-8 character
    pub fn advanceUTF8(self: *Scanner) !u21 {
        if (self.at_end) return 0;

        const ch = try self.getCurrentUTF8();
        const len = std.unicode.utf8ByteSequenceLength(self.current_char) catch 1;

        // Advance by UTF-8 character length
        for (0..len) |_| {
            _ = self.advance();
        }

        return ch;
    }

    // ========================================================================
    // Private Implementation
    // ========================================================================

    /// Initialize character classification table
    fn initCharTable(self: *Scanner) void {
        // Initialize all as unknown
        for (&self.char_table) |*entry| {
            entry.* = .unknown;
        }

        // Whitespace
        self.char_table[' '] = .whitespace;
        self.char_table['\t'] = .whitespace;
        self.char_table['\n'] = .whitespace;
        self.char_table['\r'] = .whitespace;

        // Digits
        for ('0'..'9' + 1) |ch| {
            self.char_table[ch] = .digit;
        }

        // Lowercase letters
        for ('a'..'z' + 1) |ch| {
            self.char_table[ch] = .alpha;
        }

        // Uppercase letters
        for ('A'..'Z' + 1) |ch| {
            self.char_table[ch] = .alpha;
        }

        // Hex letters
        for ('a'..'f' + 1) |ch| {
            self.char_table[ch] = .hex_alpha;
        }
        for ('A'..'F' + 1) |ch| {
            self.char_table[ch] = .hex_alpha;
        }

        // Operators and punctuation
        const operators = "+-*/%=!<>&|^~?:;,.@#";
        for (operators) |ch| {
            self.char_table[ch] = .operator;
        }

        // Brackets
        self.char_table['('] = .bracket;
        self.char_table[')'] = .bracket;
        self.char_table['['] = .bracket;
        self.char_table[']'] = .bracket;
        self.char_table['{'] = .bracket;
        self.char_table['}'] = .bracket;

        // String delimiters
        self.char_table['"'] = .string_delim;
        self.char_table['\''] = .string_delim;
        self.char_table['`'] = .string_delim;
    }
};

/// Character classification for fast lookup
const CharClass = enum {
    unknown,
    whitespace,
    alpha,
    digit,
    hex_alpha,
    operator,
    bracket,
    string_delim,
};

// Tests
const testing = std.testing;

test "Scanner basic operations" {
    var scanner = Scanner.init();

    const text = "hello world";
    scanner.reset(text, 0);

    try testing.expectEqual(@as(u8, 'h'), scanner.peek());
    try testing.expectEqual(@as(u8, 'e'), scanner.peekNext());

    const ch = scanner.advance();
    try testing.expectEqual(@as(u8, 'h'), ch);
    try testing.expectEqual(@as(u8, 'e'), scanner.peek());
}

test "Scanner whitespace skipping" {
    var scanner = Scanner.init();

    const text = "   hello";
    scanner.reset(text, 0);

    scanner.skipWhitespace();
    try testing.expectEqual(@as(u8, 'h'), scanner.peek());
    try testing.expectEqual(@as(usize, 3), scanner.position);
}

test "Scanner string scanning" {
    var scanner = Scanner.init();

    const text = "\"hello world\"";
    scanner.reset(text, 0);
    scanner.markTokenStart();

    try scanner.scanString('"');
    const token_text = scanner.getCurrentText();
    try testing.expectEqualStrings("\"hello world\"", token_text);
}

test "Scanner number scanning" {
    var scanner = Scanner.init();

    const text = "123.45e-6";
    scanner.reset(text, 0);
    scanner.markTokenStart();

    try scanner.scanNumber();
    const token_text = scanner.getCurrentText();
    try testing.expectEqualStrings("123.45e-6", token_text);
}

test "Scanner identifier scanning" {
    var scanner = Scanner.init();

    const text = "hello_world123";
    scanner.reset(text, 0);
    scanner.markTokenStart();

    try scanner.scanIdentifier();
    const token_text = scanner.getCurrentText();
    try testing.expectEqualStrings("hello_world123", token_text);
}

test "Scanner character classification" {
    var scanner = Scanner.init();

    try testing.expect(scanner.isWhitespace(' '));
    try testing.expect(scanner.isWhitespace('\t'));
    try testing.expect(scanner.isWhitespace('\n'));

    try testing.expect(scanner.isDigit('5'));
    try testing.expect(!scanner.isDigit('a'));

    try testing.expect(scanner.isIdentifierStart('a'));
    try testing.expect(scanner.isIdentifierStart('_'));
    try testing.expect(!scanner.isIdentifierStart('1'));

    try testing.expect(scanner.isIdentifierChar('a'));
    try testing.expect(scanner.isIdentifierChar('1'));
    try testing.expect(scanner.isIdentifierChar('_'));
}

test "Scanner UTF-8 support" {
    var scanner = Scanner.init();

    // Test with ASCII
    scanner.reset("hello", 0);
    const ascii_char = try scanner.getCurrentUTF8();
    try testing.expectEqual(@as(u21, 'h'), ascii_char);

    // Test with UTF-8 (if we had UTF-8 input)
    // For now, just test that it doesn't crash
    const advanced = try scanner.advanceUTF8();
    try testing.expectEqual(@as(u21, 'h'), advanced);
}
