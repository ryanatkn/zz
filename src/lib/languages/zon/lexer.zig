/// ZON Lexer - Clean implementation for progressive parser architecture
///
/// Implements LexerInterface with direct streaming and batch tokenization.
/// Supports Zig Object Notation (ZON) syntax.
const std = @import("std");
const Allocator = std.mem.Allocator;

// Import new infrastructure
const token_mod = @import("../../token/mod.zig");
const Token = token_mod.Token;
const TokenKind = token_mod.TokenKind;
const TokenFlags = token_mod.TokenFlags;
const Span = @import("../../span/mod.zig").Span;
const LexerInterface = @import("../../lexer/interface.zig").LexerInterface;
const createInterface = @import("../../lexer/interface.zig").createInterface;
const TokenStream = @import("../../lexer/streaming.zig").TokenStream;
const createTokenStream = @import("../../lexer/streaming.zig").createTokenStream;

// Use character utilities
const char = @import("../../char/mod.zig");

/// ZON Lexer with streaming-first design
pub const ZonLexer = struct {
    allocator: Allocator,
    source: []const u8,
    position: usize,
    eof_returned: bool,
    last_error: ?LexerError,

    const Self = @This();

    pub const LexerError = error{
        InvalidEscapeSequence,
        InvalidUnicodeEscape,
        UnterminatedString,
    };

    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .source = "",
            .position = 0,
            .eof_returned = false,
            .last_error = null,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
        // Nothing to clean up in basic implementation
    }

    /// Create a LexerInterface for this lexer
    pub fn interface(self: *Self) LexerInterface {
        return createInterface(self);
    }

    /// Stream tokens without allocation
    pub fn streamTokens(self: *Self, source: []const u8) TokenStream {
        self.source = source;
        self.position = 0;
        self.eof_returned = false;

        return createTokenStream(self);
    }

    /// Stream-compatible next method for direct TokenStream creation
    pub fn next(self: *Self) ?Token {
        // Skip whitespace including newlines
        while (self.position < self.source.len) {
            const c = self.source[self.position];
            if (!char.isWhitespaceOrNewline(c)) break;
            self.position += 1;
        }

        // Check for EOF
        if (self.position >= self.source.len) {
            if (self.eof_returned) {
                return null; // EOF already returned, stop iteration
            }
            self.eof_returned = true;
            return Token{
                .span = Span.init(@intCast(@min(self.position, std.math.maxInt(u32))), @intCast(@min(self.position, std.math.maxInt(u32)))),
                .kind = .eof,
                .depth = 0,
                .flags = .{},
            };
        }

        const start = self.position;
        const c = self.source[self.position];

        // Comments (ZON supports //)
        if (c == '/' and self.position + 1 < self.source.len and self.source[self.position + 1] == '/') {
            self.position += 2;
            while (self.position < self.source.len and self.source[self.position] != '\n') {
                self.position += 1;
            }
            return Token{
                .span = Span.init(@intCast(start), @intCast(self.position)),
                .kind = .comment,
                .depth = 0,
                .flags = .{},
            };
        }

        // Single character tokens
        const token_kind: ?TokenKind = switch (c) {
            '{' => blk: {
                self.position += 1;
                break :blk .left_brace;
            },
            '}' => blk: {
                self.position += 1;
                break :blk .right_brace;
            },
            '[' => blk: {
                self.position += 1;
                break :blk .left_bracket;
            },
            ']' => blk: {
                self.position += 1;
                break :blk .right_bracket;
            },
            '(' => blk: {
                self.position += 1;
                break :blk .left_paren;
            },
            ')' => blk: {
                self.position += 1;
                break :blk .right_paren;
            },
            ',' => blk: {
                self.position += 1;
                break :blk .comma;
            },
            '=' => blk: {
                self.position += 1;
                break :blk .equal;
            },
            '.' => blk: {
                self.position += 1;
                break :blk .dot;
            },
            else => null,
        };

        if (token_kind) |kind| {
            return Token{
                .span = Span.init(@intCast(@min(start, std.math.maxInt(u32))), @intCast(@min(self.position, std.math.maxInt(u32)))),
                .kind = kind,
                .depth = 0,
                .flags = .{},
            };
        }

        // String literals
        if (c == '"') {
            self.position += 1;
            while (self.position < self.source.len) {
                const ch = self.source[self.position];
                if (ch == '"') {
                    self.position += 1;
                    break;
                } else if (ch == '\\' and self.position + 1 < self.source.len) {
                    const escape_char = self.source[self.position + 1];
                    switch (escape_char) {
                        '\\', '"', '\'', 'n', 'r', 't', '0' => {
                            self.position += 2; // Valid escape sequence  
                        },
                        'u' => {
                            // Unicode escape: \u{XXXX}
                            if (self.position + 2 < self.source.len and self.source[self.position + 2] == '{') {
                                self.position += 3; // Skip \u{
                                var hex_digits: u32 = 0;
                                var unicode_value: u32 = 0;
                                while (self.position < self.source.len) {
                                    const hex_ch = self.source[self.position];
                                    if (hex_ch == '}') {
                                        self.position += 1;
                                        break;
                                    }
                                    if (!char.isHexDigit(hex_ch) or hex_digits >= 6) {
                                        self.last_error = LexerError.InvalidUnicodeEscape;
                                        return null;
                                    }
                                    // Parse hex digit
                                    const digit_value = switch (hex_ch) {
                                        '0'...'9' => hex_ch - '0',
                                        'A'...'F' => hex_ch - 'A' + 10,
                                        'a'...'f' => hex_ch - 'a' + 10,
                                        else => unreachable,
                                    };
                                    unicode_value = unicode_value * 16 + digit_value;
                                    self.position += 1;
                                    hex_digits += 1;
                                }
                                if (hex_digits == 0) {
                                    self.last_error = LexerError.InvalidUnicodeEscape;
                                    return null;
                                }
                                // Check if unicode value is in valid range (0x0 to 0x10FFFF)
                                // Also exclude surrogate pairs (0xD800 to 0xDFFF)
                                if (unicode_value > 0x10FFFF or (unicode_value >= 0xD800 and unicode_value <= 0xDFFF)) {
                                    self.last_error = LexerError.InvalidUnicodeEscape;
                                    return null;
                                }
                            } else {
                                self.last_error = LexerError.InvalidEscapeSequence;
                                return null;
                            }
                        },
                        else => {
                            self.last_error = LexerError.InvalidEscapeSequence;
                            return null;
                        },
                    }
                } else {
                    self.position += 1;
                }
            }

            // Check if string was properly terminated
            if (self.position >= self.source.len or self.source[self.position - 1] != '"') {
                self.last_error = LexerError.UnterminatedString;
                return null;
            }

            return Token{
                .span = Span.init(@intCast(@min(start, std.math.maxInt(u32))), @intCast(@min(self.position, std.math.maxInt(u32)))),
                .kind = .string,
                .depth = 0,
                .flags = .{ .has_escapes = std.mem.indexOfScalar(u8, self.source[start..self.position], '\\') != null },
            };
        }

        // Numbers (integers, floats)
        if (char.isDigit(c) or c == '-') {
            if (c == '-') self.position += 1;

            // Check for hex/binary/octal prefixes
            if (self.position < self.source.len and self.source[self.position] == '0' and
                self.position + 1 < self.source.len)
            {
                const prefix = self.source[self.position + 1];
                if (prefix == 'x' or prefix == 'X' or prefix == 'b' or prefix == 'B' or prefix == 'o' or prefix == 'O') {
                    self.position += 2; // Skip 0x, 0b, or 0o
                    while (self.position < self.source.len) {
                        const ch = self.source[self.position];
                        const is_valid = switch (prefix) {
                            'x', 'X' => char.isHexDigit(ch) or ch == '_',
                            'b', 'B' => ch == '0' or ch == '1' or ch == '_',
                            'o', 'O' => (ch >= '0' and ch <= '7') or ch == '_',
                            else => false,
                        };
                        if (!is_valid) break;
                        self.position += 1;
                    }
                } else {
                    // Regular decimal number starting with 0
                    while (self.position < self.source.len and char.isDigit(self.source[self.position])) {
                        self.position += 1;
                    }
                }
            } else {
                // Regular decimal number
                while (self.position < self.source.len and char.isDigit(self.source[self.position])) {
                    self.position += 1;
                }
            }

            // Check for decimal point (only for decimal numbers, not hex/binary)
            if (self.position < self.source.len and self.source[self.position] == '.') {
                // Skip decimal point if we're in a hex/binary/octal number
                var is_special_number = false;
                if (start < self.source.len and self.source[start] == '0' and start + 1 < self.source.len) {
                    const p = self.source[start + 1];
                    is_special_number = (p == 'x' or p == 'X' or p == 'b' or p == 'B' or p == 'o' or p == 'O');
                }

                if (!is_special_number) {
                    self.position += 1;
                    while (self.position < self.source.len and char.isDigit(self.source[self.position])) {
                        self.position += 1;
                    }

                    // Check for exponent
                    if (self.position < self.source.len and (self.source[self.position] == 'e' or self.source[self.position] == 'E')) {
                        self.position += 1;
                        if (self.position < self.source.len and (self.source[self.position] == '+' or self.source[self.position] == '-')) {
                            self.position += 1;
                        }
                        while (self.position < self.source.len and char.isDigit(self.source[self.position])) {
                            self.position += 1;
                        }
                    }
                }
            }

            return Token{
                .span = Span.init(@intCast(@min(start, std.math.maxInt(u32))), @intCast(@min(self.position, std.math.maxInt(u32)))),
                .kind = .number,
                .depth = 0,
                .flags = .{},
            };
        }

        // Quoted identifiers (@"name")
        if (c == '@' and self.position + 1 < self.source.len and self.source[self.position + 1] == '"') {
            self.position += 1; // Skip '@'
            self.position += 1; // Skip '"'

            while (self.position < self.source.len) {
                const ch = self.source[self.position];
                if (ch == '"') {
                    self.position += 1;
                    break;
                } else if (ch == '\\' and self.position + 1 < self.source.len) {
                    self.position += 2; // Skip escaped character
                } else {
                    self.position += 1;
                }
            }

            return Token{
                .span = Span.init(@intCast(@min(start, std.math.maxInt(u32))), @intCast(@min(self.position, std.math.maxInt(u32)))),
                .kind = .identifier,
                .depth = 0,
                .flags = .{},
            };
        }

        // Builtin functions (@import, @field, etc.)
        if (c == '@' and self.position + 1 < self.source.len and char.isAlpha(self.source[self.position + 1])) {
            self.position += 1; // Skip '@'
            while (self.position < self.source.len and (char.isAlphaNumeric(self.source[self.position]) or self.source[self.position] == '_')) {
                self.position += 1;
            }
            return Token{
                .span = Span.init(@intCast(@min(start, std.math.maxInt(u32))), @intCast(@min(self.position, std.math.maxInt(u32)))),
                .kind = .keyword,
                .depth = 0,
                .flags = .{},
            };
        }

        // Identifiers and keywords
        if (char.isAlpha(c) or c == '_') {
            while (self.position < self.source.len and (char.isAlphaNumeric(self.source[self.position]) or self.source[self.position] == '_')) {
                self.position += 1;
            }

            const text = self.source[start..self.position];
            const kind: TokenKind = if (std.mem.eql(u8, text, "true") or std.mem.eql(u8, text, "false"))
                .boolean
            else if (std.mem.eql(u8, text, "null"))
                .null
            else
                .identifier;

            return Token{
                .span = Span.init(@intCast(@min(start, std.math.maxInt(u32))), @intCast(@min(self.position, std.math.maxInt(u32)))),
                .kind = kind,
                .depth = 0,
                .flags = .{},
            };
        }

        // Unknown character
        self.position += 1;
        return Token{
            .span = Span.init(@intCast(@min(start, std.math.maxInt(u32))), @intCast(@min(self.position, std.math.maxInt(u32)))),
            .kind = .unknown,
            .depth = 0,
            .flags = .{},
        };
    }

    /// Batch tokenize - allocates all tokens
    pub fn batchTokenize(self: *Self, allocator: Allocator, source: []const u8) ![]Token {
        self.source = source;
        self.position = 0;
        self.last_error = null;

        var tokens = std.ArrayList(Token).init(allocator);
        defer tokens.deinit();

        // Use the lexer's direct next() method for consistency
        self.eof_returned = false;
        while (self.next()) |token| {
            try tokens.append(token);
            if (token.kind == .eof) break;
        }

        // Check if we stopped due to an error
        if (self.last_error) |err| {
            return err;
        }

        return tokens.toOwnedSlice();
    }

    /// Compatibility alias for batchTokenize
    pub fn tokenize(self: *Self, source: []const u8) ![]Token {
        return try self.batchTokenize(self.allocator, source);
    }

    /// Reset lexer state
    pub fn reset(self: *Self) void {
        self.position = 0;
        self.source = "";
    }
};

/// Streaming iterator for zero-allocation tokenization
const StreamIterator = struct {
    lexer: *ZonLexer,
    eof_returned: bool,

    const Self = @This();

    pub fn init(lexer: *ZonLexer) Self {
        return .{ .lexer = lexer, .eof_returned = false };
    }

    pub fn next(self: *Self) ?Token {
        const lexer = self.lexer;

        // Skip whitespace
        while (lexer.position < lexer.source.len) {
            const c = lexer.source[lexer.position];
            if (!char.isWhitespace(c)) break;
            lexer.position += 1;
        }

        // Check for EOF
        if (lexer.position >= lexer.source.len) {
            if (self.eof_returned) {
                return null; // EOF already returned, stop iteration
            }
            self.eof_returned = true;
            return Token{
                .span = Span.init(@intCast(lexer.position), @intCast(lexer.position)),
                .kind = .eof,
                .depth = 0,
                .flags = .{},
            };
        }

        const start = lexer.position;
        const c = lexer.source[lexer.position];

        // Comments (ZON supports //)
        if (c == '/' and lexer.position + 1 < lexer.source.len and lexer.source[lexer.position + 1] == '/') {
            lexer.position += 2;
            while (lexer.position < lexer.source.len and lexer.source[lexer.position] != '\n') {
                lexer.position += 1;
            }
            return Token{
                .span = Span.init(@intCast(start), @intCast(lexer.position)),
                .kind = .comment,
                .depth = 0,
                .flags = .{},
            };
        }

        // Single character tokens
        const token_kind: ?TokenKind = switch (c) {
            '{' => blk: {
                lexer.position += 1;
                break :blk .left_brace;
            },
            '}' => blk: {
                lexer.position += 1;
                break :blk .right_brace;
            },
            '[' => blk: {
                lexer.position += 1;
                break :blk .left_bracket;
            },
            ']' => blk: {
                lexer.position += 1;
                break :blk .right_bracket;
            },
            '(' => blk: {
                lexer.position += 1;
                break :blk .left_paren;
            },
            ')' => blk: {
                lexer.position += 1;
                break :blk .right_paren;
            },
            ',' => blk: {
                lexer.position += 1;
                break :blk .comma;
            },
            ':' => blk: {
                lexer.position += 1;
                break :blk .colon;
            },
            ';' => blk: {
                lexer.position += 1;
                break :blk .semicolon;
            },
            '=' => blk: {
                lexer.position += 1;
                break :blk .equal;
            },
            '+' => blk: {
                lexer.position += 1;
                break :blk .plus;
            },
            '-' => blk: {
                // Could be minus or start of number
                if (lexer.position + 1 < lexer.source.len and char.isDigit(lexer.source[lexer.position + 1])) {
                    break :blk null; // Let number handler take it
                }
                lexer.position += 1;
                break :blk .minus;
            },
            '*' => blk: {
                lexer.position += 1;
                break :blk .star;
            },
            '/' => blk: {
                lexer.position += 1;
                break :blk .slash;
            },
            '%' => blk: {
                lexer.position += 1;
                break :blk .percent;
            },
            else => null,
        };

        if (token_kind) |kind| {
            return Token{
                .span = Span.init(@intCast(start), @intCast(lexer.position)),
                .kind = kind,
                .depth = 0, // TODO: Track nesting depth
                .flags = .{},
            };
        }

        // Dot (for .{} struct literals and .field)
        if (c == '.') {
            lexer.position += 1;

            // Check for .{ or .field
            if (lexer.position < lexer.source.len) {
                const next_char = lexer.source[lexer.position];
                if (next_char == '{' or char.isAlpha(next_char) or next_char == '_') {
                    // Continue to get .{ or .identifier
                    if (next_char != '{') {
                        // It's a field access like .field
                        while (lexer.position < lexer.source.len) {
                            const ch = lexer.source[lexer.position];
                            if (!char.isAlphaNumeric(ch) and ch != '_') break;
                            lexer.position += 1;
                        }
                        return Token{
                            .span = Span.init(@intCast(start), @intCast(lexer.position)),
                            .kind = .identifier, // .field is an identifier in ZON
                            .depth = 0,
                            .flags = .{},
                        };
                    }
                }
            }

            return Token{
                .span = Span.init(@intCast(start), @intCast(lexer.position)),
                .kind = .dot,
                .depth = 0,
                .flags = .{},
            };
        }

        // String
        if (c == '"') {
            lexer.position += 1; // Skip opening quote
            while (lexer.position < lexer.source.len) {
                const ch = lexer.source[lexer.position];
                lexer.position += 1;
                if (ch == '"') break;
                if (ch == '\\' and lexer.position < lexer.source.len) {
                    lexer.position += 1; // Skip escaped character
                }
            }

            return Token{
                .span = Span.init(@intCast(start), @intCast(lexer.position)),
                .kind = .string,
                .depth = 0,
                .flags = .{ .has_escapes = std.mem.indexOfScalar(u8, lexer.source[start..lexer.position], '\\') != null },
            };
        }

        // Number (including hex 0x, binary 0b, octal 0o)
        if (char.isDigit(c) or (c == '-' and lexer.position + 1 < lexer.source.len and char.isDigit(lexer.source[lexer.position + 1]))) {
            if (c == '-') lexer.position += 1;

            // Check for hex/binary/octal
            if (lexer.position < lexer.source.len and lexer.source[lexer.position] == '0' and
                lexer.position + 1 < lexer.source.len)
            {
                const prefix = lexer.source[lexer.position + 1];
                if (prefix == 'x' or prefix == 'X' or prefix == 'b' or prefix == 'B' or prefix == 'o' or prefix == 'O') {
                    lexer.position += 2; // Skip 0x, 0b, or 0o
                    while (lexer.position < lexer.source.len) {
                        const ch = lexer.source[lexer.position];
                        const is_valid = switch (prefix) {
                            'x', 'X' => char.isHexDigit(ch) or ch == '_',
                            'b', 'B' => ch == '0' or ch == '1' or ch == '_',
                            'o', 'O' => (ch >= '0' and ch <= '7') or ch == '_',
                            else => false,
                        };
                        if (!is_valid) break;
                        lexer.position += 1;
                    }
                } else {
                    // Regular decimal number
                    lexer.position += 1;
                }
            }

            // Regular decimal number parsing
            while (lexer.position < lexer.source.len) {
                const ch = lexer.source[lexer.position];
                if (!char.isDigit(ch) and ch != '.' and ch != 'e' and ch != 'E' and ch != '+' and ch != '-' and ch != '_') {
                    break;
                }
                lexer.position += 1;
            }

            return Token{
                .span = Span.init(@intCast(start), @intCast(lexer.position)),
                .kind = .number,
                .depth = 0,
                .flags = .{},
            };
        }

        // Identifiers and keywords
        if (char.isAlpha(c) or c == '_' or c == '@') {
            lexer.position += 1;
            while (lexer.position < lexer.source.len) {
                const ch = lexer.source[lexer.position];
                if (!char.isAlphaNumeric(ch) and ch != '_') break;
                lexer.position += 1;
            }

            const text = lexer.source[start..lexer.position];
            const kind: TokenKind = if (std.mem.eql(u8, text, "true") or std.mem.eql(u8, text, "false"))
                .boolean
            else if (std.mem.eql(u8, text, "null") or std.mem.eql(u8, text, "undefined"))
                .null
            else if (text[0] == '@')
                .keyword // @import, @field, etc.
            else
                .identifier;

            return Token{
                .span = Span.init(@intCast(start), @intCast(lexer.position)),
                .kind = kind,
                .depth = 0,
                .flags = .{},
            };
        }

        // Unknown character
        lexer.position += 1;
        return Token{
            .span = Span.init(@intCast(start), @intCast(lexer.position)),
            .kind = .unknown,
            .depth = 0,
            .flags = .{},
        };
    }

    pub fn reset(self: *Self) void {
        self.lexer.position = 0;
    }
};

// Tests
const testing = std.testing;

test "ZonLexer - struct literal" {
    var lexer = ZonLexer.init(testing.allocator);
    defer lexer.deinit();

    const source = ".{ .key = \"value\" }";
    const tokens = try lexer.batchTokenize(testing.allocator, source);
    defer testing.allocator.free(tokens);

    try testing.expect(tokens.len >= 7);
    try testing.expect(tokens[0].kind == .dot);
    try testing.expect(tokens[1].kind == .left_brace);
    try testing.expect(tokens[2].kind == .dot); // . before key
    try testing.expect(tokens[3].kind == .identifier); // key
    try testing.expect(tokens[4].kind == .equal);
    try testing.expect(tokens[5].kind == .string);
    try testing.expect(tokens[6].kind == .right_brace);
}

test "ZonLexer - array" {
    var lexer = ZonLexer.init(testing.allocator);
    defer lexer.deinit();

    const source = ".{ 1, 0x2A, 0b101 }";
    const tokens = try lexer.batchTokenize(testing.allocator, source);
    defer testing.allocator.free(tokens);

    try testing.expect(tokens[2].kind == .number); // 1
    try testing.expect(tokens[4].kind == .number); // 0x2A
    try testing.expect(tokens[6].kind == .number); // 0b101
}

test "ZonLexer - comments" {
    var lexer = ZonLexer.init(testing.allocator);
    defer lexer.deinit();

    const source = ".{ // comment\n.field = 42 }";
    const tokens = try lexer.batchTokenize(testing.allocator, source);
    defer testing.allocator.free(tokens);

    try testing.expect(tokens[2].kind == .comment);
}

test "ZonLexer - builtin functions" {
    var lexer = ZonLexer.init(testing.allocator);
    defer lexer.deinit();

    const source = "@import(\"std\")";
    const tokens = try lexer.batchTokenize(testing.allocator, source);
    defer testing.allocator.free(tokens);

    try testing.expect(tokens[0].kind == .keyword); // @import
    try testing.expect(tokens[1].kind == .left_paren);
    try testing.expect(tokens[2].kind == .string);
    try testing.expect(tokens[3].kind == .right_paren);
}
