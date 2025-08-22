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

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .source = "",
            .position = 0,
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

        var iterator = StreamIterator.init(self);
        return createTokenStream(&iterator);
    }

    /// Batch tokenize - allocates all tokens
    pub fn batchTokenize(self: *Self, allocator: Allocator, source: []const u8) ![]Token {
        self.source = source;
        self.position = 0;

        var tokens = std.ArrayList(Token).init(allocator);
        defer tokens.deinit();

        var iterator = StreamIterator.init(self);
        while (iterator.next()) |token| {
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

    try testing.expect(tokens.len >= 6);
    try testing.expect(tokens[0].kind == .dot);
    try testing.expect(tokens[1].kind == .left_brace);
    try testing.expect(tokens[2].kind == .identifier); // .key
    try testing.expect(tokens[3].kind == .equal);
    try testing.expect(tokens[4].kind == .string);
    try testing.expect(tokens[5].kind == .right_brace);
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
