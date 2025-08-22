/// JSON Lexer - Clean implementation for progressive parser architecture
///
/// Implements LexerInterface with direct streaming and batch tokenization.
/// No legacy code, no adapters, pure implementation.
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

/// JSON Lexer with streaming-first design
pub const JsonLexer = struct {
    allocator: Allocator,
    source: []const u8,
    position: usize,
    eof_returned: bool,

    const Self = @This();

    /// Convert position to u32 safely, clamping to max value if needed
    inline fn posToU32(pos: usize) u32 {
        return @intCast(@min(pos, std.math.maxInt(u32)));
    }

    pub const LexerError = error{
        UnterminatedString,
        InvalidCharacter,
        InvalidNumber,
    };

    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .source = "",
            .position = 0,
            .eof_returned = false,
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
                .span = Span.init(Self.posToU32(self.position), Self.posToU32(self.position)),
                .kind = .eof,
                .depth = 0,
                .flags = .{},
            };
        }

        const start = self.position;
        const c = self.source[self.position];

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
            ',' => blk: {
                self.position += 1;
                break :blk .comma;
            },
            ':' => blk: {
                self.position += 1;
                break :blk .colon;
            },
            else => null,
        };

        if (token_kind) |kind| {
            return Token{
                .span = Span.init(Self.posToU32(start), Self.posToU32(self.position)),
                .kind = kind,
                .depth = 0,
                .flags = .{},
            };
        }

        // String
        if (c == '"') {
            self.position += 1;
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
                .span = Span.init(Self.posToU32(start), Self.posToU32(self.position)),
                .kind = .string,
                .depth = 0,
                .flags = .{ .has_escapes = std.mem.indexOfScalar(u8, self.source[start..self.position], '\\') != null },
            };
        }

        // Number (RFC 8259 compliant)
        if (char.isDigit(c) or c == '-') {
            var is_valid = true;

            // Handle negative sign
            if (c == '-') {
                self.position += 1;
                if (self.position >= self.source.len or !char.isDigit(self.source[self.position])) {
                    is_valid = false;
                }
            }

            // Integer part
            if (is_valid and self.position < self.source.len) {
                if (self.source[self.position] == '0') {
                    // Leading zero - must be followed by . or e/E or end
                    self.position += 1;
                    if (self.position < self.source.len) {
                        const next_char = self.source[self.position];
                        if (char.isDigit(next_char)) {
                            // Leading zeros not allowed (e.g., "01", "00")
                            is_valid = false;
                        }
                    }
                } else {
                    // Non-zero digit - consume all digits
                    while (self.position < self.source.len and char.isDigit(self.source[self.position])) {
                        self.position += 1;
                    }
                }
            }

            // Decimal part
            if (is_valid and self.position < self.source.len and self.source[self.position] == '.') {
                self.position += 1;
                if (self.position >= self.source.len or !char.isDigit(self.source[self.position])) {
                    is_valid = false;
                } else {
                    while (self.position < self.source.len and char.isDigit(self.source[self.position])) {
                        self.position += 1;
                    }
                }
            }

            // Exponent part
            if (is_valid and self.position < self.source.len) {
                const exp_char = self.source[self.position];
                if (exp_char == 'e' or exp_char == 'E') {
                    self.position += 1;
                    if (self.position < self.source.len) {
                        const sign = self.source[self.position];
                        if (sign == '+' or sign == '-') {
                            self.position += 1;
                        }
                    }

                    // Exponent must have at least one digit
                    if (self.position >= self.source.len or !char.isDigit(self.source[self.position])) {
                        is_valid = false;
                    } else {
                        // Check for leading zeros in exponent (e.g., "1e01" is invalid)
                        if (self.source[self.position] == '0' and
                            self.position + 1 < self.source.len and
                            char.isDigit(self.source[self.position + 1]))
                        {
                            // Leading zero in exponent
                            is_valid = false;
                        }

                        // Consume exponent digits
                        while (self.position < self.source.len and char.isDigit(self.source[self.position])) {
                            self.position += 1;
                        }
                    }
                }
            }

            // Even if invalid, we still return a token (parser will handle the error)
            return Token{
                .span = Span.init(Self.posToU32(start), Self.posToU32(self.position)),
                .kind = if (is_valid) .number else .unknown,
                .depth = 0,
                .flags = .{},
            };
        }

        // Keywords: true, false, null
        if (char.isAlpha(c)) {
            while (self.position < self.source.len and char.isAlpha(self.source[self.position])) {
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
                .span = Span.init(Self.posToU32(start), Self.posToU32(self.position)),
                .kind = kind,
                .depth = 0,
                .flags = .{},
            };
        }

        // Unknown character
        self.position += 1;
        return Token{
            .span = Span.init(Self.posToU32(start), Self.posToU32(self.position)),
            .kind = .unknown,
            .depth = 0,
            .flags = .{},
        };
    }

    /// Batch tokenize - allocates all tokens
    pub fn batchTokenize(self: *Self, allocator: Allocator, source: []const u8) ![]Token {
        self.source = source;
        self.position = 0;
        self.eof_returned = false;

        var tokens = std.ArrayList(Token).init(allocator);
        defer tokens.deinit();

        while (self.next()) |token| {
            try tokens.append(token);
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
        self.eof_returned = false;
        self.source = "";
    }
};

/// Streaming iterator for zero-allocation tokenization
const StreamIterator = struct {
    lexer: *JsonLexer,
    eof_returned: bool,

    const Self = @This();

    pub fn init(lexer: *JsonLexer) Self {
        return .{
            .lexer = lexer,
            .eof_returned = false,
        };
    }

    pub fn next(self: *Self) ?Token {
        const lexer = self.lexer;

        // Skip whitespace including newlines
        while (lexer.position < lexer.source.len) {
            const c = lexer.source[lexer.position];
            if (!char.isWhitespaceOrNewline(c)) break;
            lexer.position += 1;
        }

        // Check for EOF
        if (lexer.position >= lexer.source.len) {
            if (self.eof_returned) {
                return null; // EOF already returned, stop iteration
            }
            self.eof_returned = true;
            return Token{
                .span = Span.init(JsonLexer.posToU32(lexer.position), JsonLexer.posToU32(lexer.position)),
                .kind = .eof,
                .depth = 0,
                .flags = .{},
            };
        }

        const start = lexer.position;
        const c = lexer.source[lexer.position];

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
            ',' => blk: {
                lexer.position += 1;
                break :blk .comma;
            },
            ':' => blk: {
                lexer.position += 1;
                break :blk .colon;
            },
            else => null,
        };

        if (token_kind) |kind| {
            return Token{
                .span = Span.init(JsonLexer.posToU32(start), JsonLexer.posToU32(lexer.position)),
                .kind = kind,
                .depth = 0, // TODO: Track nesting depth
                .flags = .{},
            };
        }

        // String
        if (c == '"') {
            lexer.position += 1; // Skip opening quote
            var string_terminated = false;
            while (lexer.position < lexer.source.len) {
                const ch = lexer.source[lexer.position];
                lexer.position += 1;
                if (ch == '"') {
                    string_terminated = true;
                    break;
                }
                if (ch == '\\' and lexer.position < lexer.source.len) {
                    lexer.position += 1; // Skip escaped character
                }
            }

            // For now, handle unterminated strings gracefully
            // TODO: Add proper error handling in future iteration

            return Token{
                .span = Span.init(JsonLexer.posToU32(start), JsonLexer.posToU32(lexer.position)),
                .kind = .string,
                .depth = 0,
                .flags = .{ .has_escapes = std.mem.indexOfScalar(u8, lexer.source[start..lexer.position], '\\') != null },
            };
        }

        // Number (RFC 8259 compliant)
        if (char.isDigit(c) or c == '-') {
            var is_valid = true;

            // Handle negative sign
            if (c == '-') {
                lexer.position += 1;
                if (lexer.position >= lexer.source.len or !char.isDigit(lexer.source[lexer.position])) {
                    is_valid = false;
                }
            }

            // Integer part
            if (is_valid and lexer.position < lexer.source.len) {
                if (lexer.source[lexer.position] == '0') {
                    // Leading zero - must be followed by . or e/E or end
                    lexer.position += 1;
                    if (lexer.position < lexer.source.len) {
                        const next_char = lexer.source[lexer.position];
                        if (char.isDigit(next_char)) {
                            // Leading zeros not allowed (e.g., "01", "00")
                            is_valid = false;
                        }
                    }
                } else {
                    // Non-zero digit - consume all digits
                    while (lexer.position < lexer.source.len and char.isDigit(lexer.source[lexer.position])) {
                        lexer.position += 1;
                    }
                }
            }

            // Decimal part
            if (is_valid and lexer.position < lexer.source.len and lexer.source[lexer.position] == '.') {
                lexer.position += 1;
                if (lexer.position >= lexer.source.len or !char.isDigit(lexer.source[lexer.position])) {
                    is_valid = false;
                } else {
                    while (lexer.position < lexer.source.len and char.isDigit(lexer.source[lexer.position])) {
                        lexer.position += 1;
                    }
                }
            }

            // Exponent part
            if (is_valid and lexer.position < lexer.source.len) {
                const exp_char = lexer.source[lexer.position];
                if (exp_char == 'e' or exp_char == 'E') {
                    lexer.position += 1;
                    if (lexer.position < lexer.source.len) {
                        const sign = lexer.source[lexer.position];
                        if (sign == '+' or sign == '-') {
                            lexer.position += 1;
                        }
                    }

                    // Exponent must have at least one digit
                    if (lexer.position >= lexer.source.len or !char.isDigit(lexer.source[lexer.position])) {
                        is_valid = false;
                    } else {
                        // Check for leading zeros in exponent (e.g., "1e01" is invalid)
                        if (lexer.source[lexer.position] == '0' and
                            lexer.position + 1 < lexer.source.len and
                            char.isDigit(lexer.source[lexer.position + 1]))
                        {
                            // Leading zero in exponent
                            is_valid = false;
                        }

                        // Consume exponent digits
                        while (lexer.position < lexer.source.len and char.isDigit(lexer.source[lexer.position])) {
                            lexer.position += 1;
                        }
                    }
                }
            }

            // Even if invalid, we still return a token (parser will handle the error)
            return Token{
                .span = Span.init(JsonLexer.posToU32(start), JsonLexer.posToU32(lexer.position)),
                .kind = if (is_valid) .number else .unknown,
                .depth = 0,
                .flags = .{},
            };
        }

        // Keywords: true, false, null
        if (char.isAlpha(c)) {
            while (lexer.position < lexer.source.len and char.isAlpha(lexer.source[lexer.position])) {
                lexer.position += 1;
            }

            const text = lexer.source[start..lexer.position];
            const kind: TokenKind = if (std.mem.eql(u8, text, "true") or std.mem.eql(u8, text, "false"))
                .boolean
            else if (std.mem.eql(u8, text, "null"))
                .null
            else
                .identifier;

            return Token{
                .span = Span.init(JsonLexer.posToU32(start), JsonLexer.posToU32(lexer.position)),
                .kind = kind,
                .depth = 0,
                .flags = .{},
            };
        }

        // Unknown character
        lexer.position += 1;
        return Token{
            .span = Span.init(JsonLexer.posToU32(start), JsonLexer.posToU32(lexer.position)),
            .kind = .unknown,
            .depth = 0,
            .flags = .{},
        };
    }

    pub fn reset(self: *Self) void {
        self.lexer.position = 0;
        self.eof_returned = false;
    }
};

// Tests
const testing = std.testing;

test "JsonLexer - basic object" {
    var lexer = JsonLexer.init(testing.allocator);
    defer lexer.deinit();

    const source = "{\"key\": \"value\"}";
    const tokens = try lexer.batchTokenize(testing.allocator, source);
    defer testing.allocator.free(tokens);

    try testing.expect(tokens.len >= 5);
    try testing.expect(tokens[0].kind == .left_brace);
    try testing.expect(tokens[1].kind == .string);
    try testing.expect(tokens[2].kind == .colon);
    try testing.expect(tokens[3].kind == .string);
    try testing.expect(tokens[4].kind == .right_brace);
}

test "JsonLexer - array" {
    var lexer = JsonLexer.init(testing.allocator);
    defer lexer.deinit();

    const source = "[1, 2, 3]";
    const tokens = try lexer.batchTokenize(testing.allocator, source);
    defer testing.allocator.free(tokens);

    try testing.expect(tokens[0].kind == .left_bracket);
    try testing.expect(tokens[1].kind == .number);
    try testing.expect(tokens[2].kind == .comma);
    try testing.expect(tokens[3].kind == .number);
}

test "JsonLexer - keywords" {
    var lexer = JsonLexer.init(testing.allocator);
    defer lexer.deinit();

    const source = "[true, false, null]";
    const tokens = try lexer.batchTokenize(testing.allocator, source);
    defer testing.allocator.free(tokens);

    try testing.expect(tokens[1].kind == .boolean);
    try testing.expect(tokens[3].kind == .boolean);
    try testing.expect(tokens[5].kind == .null);
}

test "JsonLexer - streaming" {
    var lexer = JsonLexer.init(testing.allocator);
    defer lexer.deinit();

    const source = "{}";
    var stream = lexer.streamTokens(source);

    const token1 = stream.next();
    try testing.expect(token1.?.kind == .left_brace);

    const token2 = stream.next();
    try testing.expect(token2.?.kind == .right_brace);

    const token3 = stream.next();
    try testing.expect(token3.?.kind == .eof);
}
