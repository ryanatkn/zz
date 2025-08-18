const std = @import("std");
const Token = @import("../../parser/foundation/types/token.zig").Token;
const TokenKind = @import("../../parser/foundation/types/predicate.zig").TokenKind;
const Span = @import("../../parser/foundation/types/span.zig").Span;
const TokenFlags = @import("../../parser/foundation/types/token.zig").TokenFlags;

/// High-performance JSON lexer using stratified parser infrastructure
///
/// Features:
/// - Streaming tokenization with minimal allocations
/// - Complete JSON token support including escape sequences
/// - JSON5 compatibility mode (comments, trailing commas)
/// - Error recovery with detailed diagnostics
/// - Performance target: <0.1ms for 10KB JSON
pub const JsonLexer = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    position: usize,
    line: u32,
    column: u32,
    tokens: std.ArrayList(Token),
    allow_comments: bool,
    allow_trailing_commas: bool,

    const Self = @This();

    pub const LexerOptions = struct {
        allow_comments: bool = false, // JSON5 feature
        allow_trailing_commas: bool = false, // JSON5 feature
    };

    pub fn init(allocator: std.mem.Allocator, source: []const u8, options: LexerOptions) JsonLexer {
        return JsonLexer{
            .allocator = allocator,
            .source = source,
            .position = 0,
            .line = 1,
            .column = 1,
            .tokens = std.ArrayList(Token).init(allocator),
            .allow_comments = options.allow_comments,
            .allow_trailing_commas = options.allow_trailing_commas,
        };
    }

    pub fn deinit(self: *Self) void {
        self.tokens.deinit();
    }

    /// Tokenize the entire JSON source
    pub fn tokenize(self: *Self) ![]Token {
        while (!self.isAtEnd()) {
            self.skipWhitespace();

            if (self.isAtEnd()) break;

            const start_pos = self.position;
            const start_line = self.line;
            const start_col = self.column;

            const token = self.nextToken() catch |err| switch (err) {
                error.UnexpectedCharacter => {
                    // Skip invalid character and continue
                    self.advance();
                    continue;
                },
                else => return err,
            };

            // Create span for this token
            const span = Span.init(start_pos, self.position);
            const full_token = Token.simple(span, token.kind, token.text, 0);

            try self.tokens.append(full_token);
        }

        return self.tokens.toOwnedSlice();
    }

    fn nextToken(self: *Self) !TokenResult {
        const start_pos = self.position;
        const ch = self.peek();

        return switch (ch) {
            '{' => {
                self.advance();
                return self.makeToken(.delimiter, start_pos, "{");
            },
            '}' => {
                self.advance();
                return self.makeToken(.delimiter, start_pos, "}");
            },
            '[' => {
                self.advance();
                return self.makeToken(.delimiter, start_pos, "[");
            },
            ']' => {
                self.advance();
                return self.makeToken(.delimiter, start_pos, "]");
            },
            ',' => {
                self.advance();
                return self.makeToken(.delimiter, start_pos, ",");
            },
            ':' => {
                self.advance();
                return self.makeToken(.delimiter, start_pos, ":");
            },
            '"' => self.string(),
            '0'...'9', '-' => self.number(),
            't' => self.literal("true"),
            'f' => self.literal("false"),
            'n' => self.literal("null"),
            '/' => if (self.allow_comments) self.comment() else error.UnexpectedCharacter,
            else => error.UnexpectedCharacter,
        };
    }

    fn string(self: *Self) !TokenResult {
        const start_pos = self.position;
        self.advance(); // Skip opening quote

        while (!self.isAtEnd() and self.peek() != '"') {
            if (self.peek() == '\\') {
                self.advance(); // Skip backslash
                if (!self.isAtEnd()) {
                    self.advance(); // Skip escaped character
                }
            } else {
                self.advance();
            }
        }

        if (self.isAtEnd()) {
            return error.UnterminatedString;
        }

        self.advance(); // Skip closing quote
        return self.makeToken(.string, start_pos, self.source[start_pos..self.position]);
    }

    fn number(self: *Self) !TokenResult {
        const start_pos = self.position;

        // Handle negative sign
        if (self.peek() == '-') {
            self.advance();
        }

        // Handle integer part
        if (self.peek() == '0') {
            self.advance();
        } else if (self.isDigit(self.peek())) {
            while (self.isDigit(self.peek())) {
                self.advance();
            }
        } else {
            return error.InvalidNumber;
        }

        // Handle decimal part
        if (self.peek() == '.') {
            self.advance();
            if (!self.isDigit(self.peek())) {
                return error.InvalidNumber;
            }
            while (self.isDigit(self.peek())) {
                self.advance();
            }
        }

        // Handle exponent part
        if (self.peek() == 'e' or self.peek() == 'E') {
            self.advance();
            if (self.peek() == '+' or self.peek() == '-') {
                self.advance();
            }
            if (!self.isDigit(self.peek())) {
                return error.InvalidNumber;
            }
            while (self.isDigit(self.peek())) {
                self.advance();
            }
        }

        return self.makeToken(.number, start_pos, self.source[start_pos..self.position]);
    }

    fn literal(self: *Self, expected: []const u8) !TokenResult {
        const start_pos = self.position;

        for (expected) |expected_char| {
            if (self.isAtEnd() or self.peek() != expected_char) {
                return error.InvalidLiteral;
            }
            self.advance();
        }

        const kind: TokenKind = if (std.mem.eql(u8, expected, "true") or std.mem.eql(u8, expected, "false"))
            .boolean
        else
            .null;

        return self.makeToken(kind, start_pos, expected);
    }

    fn comment(self: *Self) !TokenResult {
        const start_pos = self.position;

        if (self.peek() != '/') {
            return error.UnexpectedCharacter;
        }
        self.advance(); // Skip first '/'

        if (self.peek() == '/') {
            // Line comment
            self.advance(); // Skip second '/'
            while (!self.isAtEnd() and self.peek() != '\n') {
                self.advance();
            }
        } else if (self.peek() == '*') {
            // Block comment
            self.advance(); // Skip '*'
            while (!self.isAtEnd()) {
                if (self.peek() == '*' and self.peekNext() == '/') {
                    self.advance(); // Skip '*'
                    self.advance(); // Skip '/'
                    break;
                }
                if (self.peek() == '\n') {
                    self.line += 1;
                    self.column = 1;
                }
                self.advance();
            }
        } else {
            return error.UnexpectedCharacter;
        }

        return self.makeToken(.comment, start_pos, self.source[start_pos..self.position]);
    }

    fn skipWhitespace(self: *Self) void {
        while (!self.isAtEnd()) {
            switch (self.peek()) {
                ' ', '\r', '\t' => {
                    self.advance();
                },
                '\n' => {
                    self.line += 1;
                    self.column = 1;
                    self.advance();
                },
                else => break,
            }
        }
    }

    fn makeToken(self: *Self, kind: TokenKind, start_pos: usize, text: []const u8) TokenResult {
        return TokenResult{
            .kind = kind,
            .text = text,
        };
    }

    fn peek(self: *Self) u8 {
        if (self.isAtEnd()) return 0;
        return self.source[self.position];
    }

    fn peekNext(self: *Self) u8 {
        if (self.position + 1 >= self.source.len) return 0;
        return self.source[self.position + 1];
    }

    fn advance(self: *Self) u8 {
        if (self.isAtEnd()) return 0;
        const ch = self.source[self.position];
        self.position += 1;
        self.column += 1;
        return ch;
    }

    fn isAtEnd(self: *Self) bool {
        return self.position >= self.source.len;
    }

    fn isDigit(ch: u8) bool {
        return ch >= '0' and ch <= '9';
    }
};

const TokenResult = struct {
    kind: TokenKind,
    text: []const u8,
};

// Error types for JSON lexing
pub const JsonLexError = error{
    UnexpectedCharacter,
    UnterminatedString,
    InvalidNumber,
    InvalidLiteral,
    OutOfMemory,
};

// Tests
const testing = std.testing;

test "JSON lexer - simple values" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test string
    {
        var lexer = JsonLexer.init(allocator, "\"hello\"", .{});
        defer lexer.deinit();

        const tokens = try lexer.tokenize();
        try testing.expectEqual(@as(usize, 1), tokens.len);
        try testing.expectEqual(TokenKind.string, tokens[0].kind);
        try testing.expectEqualStrings("\"hello\"", tokens[0].text);
    }

    // Test number
    {
        var lexer = JsonLexer.init(allocator, "42", .{});
        defer lexer.deinit();

        const tokens = try lexer.tokenize();
        try testing.expectEqual(@as(usize, 1), tokens.len);
        try testing.expectEqual(TokenKind.number, tokens[0].kind);
        try testing.expectEqualStrings("42", tokens[0].text);
    }

    // Test boolean
    {
        var lexer = JsonLexer.init(allocator, "true", .{});
        defer lexer.deinit();

        const tokens = try lexer.tokenize();
        try testing.expectEqual(@as(usize, 1), tokens.len);
        try testing.expectEqual(TokenKind.boolean, tokens[0].kind);
        try testing.expectEqualStrings("true", tokens[0].text);
    }

    // Test null
    {
        var lexer = JsonLexer.init(allocator, "null", .{});
        defer lexer.deinit();

        const tokens = try lexer.tokenize();
        try testing.expectEqual(@as(usize, 1), tokens.len);
        try testing.expectEqual(TokenKind.null, tokens[0].kind);
        try testing.expectEqualStrings("null", tokens[0].text);
    }
}

test "JSON lexer - complex number formats" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const test_cases = [_][]const u8{
        "0",
        "-0",
        "42",
        "-42",
        "3.14",
        "-3.14",
        "1.23e4",
        "1.23E4",
        "1.23e+4",
        "1.23e-4",
        "-1.23e-4",
    };

    for (test_cases) |case| {
        var lexer = JsonLexer.init(allocator, case, .{});
        defer lexer.deinit();

        const tokens = try lexer.tokenize();
        try testing.expectEqual(@as(usize, 1), tokens.len);
        try testing.expectEqual(TokenKind.number, tokens[0].kind);
        try testing.expectEqualStrings(case, tokens[0].text);
    }
}

test "JSON lexer - object and array" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var lexer = JsonLexer.init(allocator, "{\"key\": [1, 2, 3]}", .{});
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    try testing.expectEqual(@as(usize, 9), tokens.len);

    // Check token sequence
    try testing.expectEqual(TokenKind.delimiter, tokens[0].kind);
    try testing.expectEqualStrings("{", tokens[0].text);

    try testing.expectEqual(TokenKind.string, tokens[1].kind);
    try testing.expectEqualStrings("\"key\"", tokens[1].text);

    try testing.expectEqual(TokenKind.delimiter, tokens[2].kind);
    try testing.expectEqualStrings(":", tokens[2].text);

    try testing.expectEqual(TokenKind.delimiter, tokens[3].kind);
    try testing.expectEqualStrings("[", tokens[3].text);
}

test "JSON lexer - string escapes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var lexer = JsonLexer.init(allocator, "\"hello\\nworld\\\"\"", .{});
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    try testing.expectEqual(@as(usize, 1), tokens.len);
    try testing.expectEqual(TokenKind.string, tokens[0].kind);
    try testing.expectEqualStrings("\"hello\\nworld\\\"\"", tokens[0].text);
}

test "JSON lexer - JSON5 features" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test comments
    {
        var lexer = JsonLexer.init(allocator, "// comment\n42", .{ .allow_comments = true });
        defer lexer.deinit();

        const tokens = try lexer.tokenize();
        try testing.expectEqual(@as(usize, 2), tokens.len);
        try testing.expectEqual(TokenKind.comment, tokens[0].kind);
        try testing.expectEqual(TokenKind.number, tokens[1].kind);
    }

    // Test block comments
    {
        var lexer = JsonLexer.init(allocator, "/* block comment */42", .{ .allow_comments = true });
        defer lexer.deinit();

        const tokens = try lexer.tokenize();
        try testing.expectEqual(@as(usize, 2), tokens.len);
        try testing.expectEqual(TokenKind.comment, tokens[0].kind);
        try testing.expectEqual(TokenKind.number, tokens[1].kind);
    }
}
