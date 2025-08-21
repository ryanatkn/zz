const std = @import("std");
const Token = @import("../../parser_old/foundation/types/token.zig").Token;
const TokenKind = @import("../../parser_old/foundation/types/predicate.zig").TokenKind;
const Span = @import("../../parser_old/foundation/types/span.zig").Span;
const TokenFlags = @import("../../parser_old/foundation/types/token.zig").TokenFlags;
const char = @import("../../char/mod.zig");

/// High-performance ZON lexer using stratified parser infrastructure
///
/// Features:
/// - Complete ZON token support including Zig-specific literals
/// - Comment handling (// and /* */)
/// - All Zig number formats (decimal, hex, binary, octal)
/// - Field names (.field_name) and anonymous struct syntax (.{})
/// - Error recovery with detailed diagnostics
/// - Performance target: <0.1ms for typical config files
///
/// EOF Token Convention:
/// All lexers automatically append an EOF token with empty text to signal end-of-input.
/// Parsers rely on this for clean termination detection. Tests should expect +1 token count.
pub const ZonLexer = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    position: usize,
    line: u32,
    column: u32,
    tokens: std.ArrayList(Token),
    preserve_comments: bool,

    const Self = @This();

    pub const LexerOptions = struct {
        preserve_comments: bool = true, // ZON often needs comments preserved
    };

    // ZON uses the foundation TokenKind enum
    // We'll map specific ZON tokens to the basic kinds

    pub fn init(allocator: std.mem.Allocator, source: []const u8, options: LexerOptions) ZonLexer {
        return ZonLexer{
            .allocator = allocator,
            .source = source,
            .position = 0,
            .line = 1,
            .column = 1,
            .tokens = std.ArrayList(Token).init(allocator),
            .preserve_comments = options.preserve_comments,
        };
    }

    pub fn deinit(self: *Self) void {
        self.tokens.deinit();
    }

    /// Tokenize the entire ZON source
    pub fn tokenize(self: *Self) ![]Token {
        while (self.position < self.source.len) {
            try self.nextToken();
        }

        // Add EOF token
        const eof_span = Span{
            .start = self.position,
            .end = self.position,
        };
        try self.addToken(TokenKind.eof, eof_span, "", .{});

        return self.tokens.toOwnedSlice();
    }

    fn nextToken(self: *Self) !void {
        self.skipWhitespace();

        if (self.position >= self.source.len) return;

        const start_pos = self.position;
        const current = self.currentChar();

        switch (current) {
            '.' => try self.tokenizeDotOrFieldName(),
            '"' => try self.tokenizeString(),
            '\\' => try self.tokenizeMultilineString(),
            '{' => try self.tokenizeSingleChar(TokenKind.delimiter),
            '}' => try self.tokenizeSingleChar(TokenKind.delimiter),
            '[' => try self.tokenizeSingleChar(TokenKind.delimiter),
            ']' => try self.tokenizeSingleChar(TokenKind.delimiter),
            '(' => try self.tokenizeSingleChar(TokenKind.delimiter),
            ')' => try self.tokenizeSingleChar(TokenKind.delimiter),
            '=' => try self.tokenizeSingleChar(TokenKind.operator),
            ',' => try self.tokenizeSingleChar(TokenKind.delimiter),
            '/' => try self.tokenizeCommentOrUnknown(),
            '0'...'9' => try self.tokenizeNumber(),
            'a'...'z', 'A'...'Z', '_', '@' => try self.tokenizeIdentifierOrKeyword(),
            '\n' => {
                const span = Span{
                    .start = start_pos,
                    .end = self.position + 1,
                };
                self.advance();
                try self.addToken(TokenKind.newline, span, "\n", .{});
            },
            else => {
                // Unknown character - advance and mark as unknown
                const span = Span{
                    .start = start_pos,
                    .end = self.position + 1,
                };
                const text = self.source[start_pos .. self.position + 1];
                self.advance();
                try self.addToken(TokenKind.unknown, span, text, .{});
            },
        }
    }

    fn tokenizeDotOrFieldName(self: *Self) !void {
        const start_pos = self.position;

        // Always emit the dot as a separate operator token
        const dot_span = Span{
            .start = start_pos,
            .end = start_pos + 1,
        };
        try self.addToken(TokenKind.operator, dot_span, ".", .{});

        self.advance(); // Skip '.'

        // Check if there's an identifier following the dot
        if (self.position < self.source.len and isIdentifierStart(self.currentChar())) {
            // Tokenize the identifier separately
            const id_start = self.position;

            // Handle @"..." quoted identifiers
            if (self.currentChar() == '@' and
                self.position + 1 < self.source.len and
                self.source[self.position + 1] == '"')
            {
                // Quoted identifier
                self.advance(); // Skip '@'
                self.advance(); // Skip '"'

                while (self.position < self.source.len and self.currentChar() != '"') {
                    self.advance();
                }

                if (self.position < self.source.len and self.currentChar() == '"') {
                    self.advance(); // Skip closing '"'
                }

                const id_span = Span{
                    .start = id_start,
                    .end = self.position,
                };
                const id_text = self.source[id_start..self.position];
                try self.addToken(TokenKind.identifier, id_span, id_text, .{});
            } else {
                // Regular identifier
                while (self.position < self.source.len and isIdentifierContinue(self.currentChar())) {
                    self.advance();
                }

                const id_span = Span{
                    .start = id_start,
                    .end = self.position,
                };
                const id_text = self.source[id_start..self.position];
                try self.addToken(TokenKind.identifier, id_span, id_text, .{});
            }
        }
    }

    fn tokenizeString(self: *Self) !void {
        const start_pos = self.position;

        self.advance(); // Skip opening quote

        while (self.position < self.source.len) {
            const ch = self.currentChar();
            if (ch == '"') {
                self.advance(); // Skip closing quote
                break;
            } else if (ch == '\\') {
                self.advance(); // Skip backslash
                if (self.position < self.source.len) {
                    self.advance(); // Skip escaped character
                }
            } else {
                self.advance();
            }
        }

        const span = Span{
            .start = start_pos,
            .end = self.position,
        };
        const text = self.source[start_pos..self.position];
        try self.addToken(TokenKind.string_literal, span, text, .{});
    }

    fn tokenizeMultilineString(self: *Self) !void {
        const start_pos = self.position;

        self.advance(); // Skip first backslash

        if (self.position < self.source.len and self.currentChar() == '\\') {
            self.advance(); // Skip second backslash

            // Collect the entire multiline string
            var string_content = std.ArrayList(u8).init(self.allocator);
            defer string_content.deinit();

            // Add the opening marker
            try string_content.appendSlice("\\\\");

            // Continue collecting lines until we hit a non-continuation line
            while (self.position < self.source.len) {
                // Collect current line
                const line_start = self.position;
                while (self.position < self.source.len and self.currentChar() != '\n') {
                    self.advance();
                }

                // Add line content
                try string_content.appendSlice(self.source[line_start..self.position]);

                // Check if we're at end of file
                if (self.position >= self.source.len) {
                    break;
                }

                // Skip the newline
                if (self.position < self.source.len and self.currentChar() == '\n') {
                    self.advance();
                    self.line += 1;
                    self.column = 1;
                }

                // Skip leading whitespace on next line
                while (self.position < self.source.len and
                    (self.currentChar() == ' ' or self.currentChar() == '\t'))
                {
                    self.advance();
                }

                // Check if the next line starts with \\
                if (self.position + 1 < self.source.len and
                    self.source[self.position] == '\\' and
                    self.source[self.position + 1] == '\\')
                {
                    // It's a continuation line
                    self.advance(); // Skip first backslash
                    self.advance(); // Skip second backslash
                    // The line content will be collected in the next iteration
                } else {
                    // Not a continuation, we're done
                    break;
                }
            }

            const span = Span{
                .start = start_pos,
                .end = self.position,
            };

            // For now, just return the raw text including the \\ markers
            // The ast_converter will need to handle the processing
            const text = self.source[start_pos..self.position];
            try self.addToken(TokenKind.string_literal, span, text, .{});
        } else {
            // Single backslash - treat as unknown
            const span = Span{
                .start = start_pos,
                .end = self.position,
            };
            try self.addToken(TokenKind.unknown, span, "\\", .{});
        }
    }

    fn tokenizeSingleChar(self: *Self, kind: TokenKind) !void {
        const start_pos = self.position;

        const text = self.source[start_pos .. start_pos + 1];
        self.advance();

        const span = Span{
            .start = start_pos,
            .end = self.position,
        };
        try self.addToken(kind, span, text, .{});
    }

    fn tokenizeCommentOrUnknown(self: *Self) !void {
        const start_pos = self.position;

        self.advance(); // Skip first '/'

        if (self.position < self.source.len) {
            const next = self.currentChar();
            if (next == '/') {
                // Line comment
                self.advance(); // Skip second '/'

                while (self.position < self.source.len and self.currentChar() != '\n') {
                    self.advance();
                }

                const span = Span{
                    .start = start_pos,
                    .end = self.position,
                };
                const text = self.source[start_pos..self.position];

                if (self.preserve_comments) {
                    try self.addToken(TokenKind.comment, span, text, .{});
                }
                return;
            }
        }

        // Single '/' - unknown
        const span = Span{
            .start = start_pos,
            .end = self.position,
        };
        try self.addToken(TokenKind.unknown, span, "/", .{});
    }

    fn tokenizeNumber(self: *Self) !void {
        const start_pos = self.position;

        if (self.currentChar() == '0' and self.position + 1 < self.source.len) {
            const next = self.source[self.position + 1];
            switch (next) {
                'x', 'X' => {
                    self.advance(); // Skip '0'
                    self.advance(); // Skip 'x'
                    while (self.position < self.source.len and isHexDigit(self.currentChar())) {
                        self.advance();
                    }
                    const span = Span{
                        .start = start_pos,
                        .end = self.position,
                    };
                    const text = self.source[start_pos..self.position];
                    try self.addToken(TokenKind.number_literal, span, text, .{});
                    return;
                },
                'b', 'B' => {
                    self.advance(); // Skip '0'
                    self.advance(); // Skip 'b'
                    while (self.position < self.source.len and isBinaryDigit(self.currentChar())) {
                        self.advance();
                    }
                    const span = Span{
                        .start = start_pos,
                        .end = self.position,
                    };
                    const text = self.source[start_pos..self.position];
                    try self.addToken(TokenKind.number_literal, span, text, .{});
                    return;
                },
                'o', 'O' => {
                    self.advance(); // Skip '0'
                    self.advance(); // Skip 'o'
                    while (self.position < self.source.len and isOctalDigit(self.currentChar())) {
                        self.advance();
                    }
                    const span = Span{
                        .start = start_pos,
                        .end = self.position,
                    };
                    const text = self.source[start_pos..self.position];
                    try self.addToken(TokenKind.number_literal, span, text, .{});
                    return;
                },
                else => {},
            }
        }

        // Decimal number
        while (self.position < self.source.len and char.isDigit(self.currentChar())) {
            self.advance();
        }

        // Check for decimal point
        if (self.position < self.source.len and self.currentChar() == '.') {
            self.advance();
            while (self.position < self.source.len and char.isDigit(self.currentChar())) {
                self.advance();
            }
        }

        // Check for scientific notation
        if (self.position < self.source.len and (self.currentChar() == 'e' or self.currentChar() == 'E')) {
            self.advance();
            if (self.position < self.source.len and (self.currentChar() == '+' or self.currentChar() == '-')) {
                self.advance();
            }
            while (self.position < self.source.len and char.isDigit(self.currentChar())) {
                self.advance();
            }
        }

        const span = Span{
            .start = start_pos,
            .end = self.position,
        };
        const text = self.source[start_pos..self.position];
        try self.addToken(TokenKind.number_literal, span, text, .{});
    }

    fn tokenizeIdentifierOrKeyword(self: *Self) !void {
        const start_pos = self.position;

        // Handle @"keyword" syntax
        if (self.currentChar() == '@') {
            self.advance(); // Skip '@'
            if (self.position < self.source.len and self.currentChar() == '"') {
                self.advance(); // Skip '"'
                while (self.position < self.source.len and self.currentChar() != '"') {
                    self.advance();
                }
                if (self.position < self.source.len) {
                    self.advance(); // Skip closing '"'
                }

                const span = Span{
                    .start = start_pos,
                    .end = self.position,
                };
                const text = self.source[start_pos..self.position];
                try self.addToken(TokenKind.identifier, span, text, .{});
                return;
            }
        }

        // Regular identifier
        while (self.position < self.source.len and isIdentifierContinue(self.currentChar())) {
            self.advance();
        }

        const span = Span{
            .start = start_pos,
            .end = self.position,
        };
        const text = self.source[start_pos..self.position];

        // Check for literal types and keywords
        const token_kind = if (std.mem.eql(u8, text, "true") or std.mem.eql(u8, text, "false"))
            TokenKind.boolean_literal
        else if (std.mem.eql(u8, text, "null"))
            TokenKind.null_literal
        else if (std.mem.eql(u8, text, "undefined"))
            TokenKind.keyword // undefined is a Zig keyword, not a literal
        else
            TokenKind.identifier;

        try self.addToken(token_kind, span, text, .{});
    }

    fn currentChar(self: *const Self) u8 {
        if (self.position >= self.source.len) return 0;
        return self.source[self.position];
    }

    fn advance(self: *Self) void {
        if (self.position < self.source.len) {
            if (self.source[self.position] == '\n') {
                self.line += 1;
                self.column = 1;
            } else {
                self.column += 1;
            }
            self.position += 1;
        }
    }

    fn skipWhitespace(self: *Self) void {
        const new_pos = char.skipWhitespace(self.source, self.position);
        self.position = new_pos;
    }

    fn addToken(self: *Self, kind: TokenKind, span: Span, text: []const u8, flags: TokenFlags) !void {
        const token = Token{
            .kind = kind,
            .span = span,
            .text = text,
            .bracket_depth = 0, // TODO: Track actual bracket depth
            .flags = flags,
        };
        try self.tokens.append(token);
    }

    fn isIdentifierStart(ch: u8) bool {
        return char.isIdentifierStart(ch);
    }

    fn isIdentifierContinue(ch: u8) bool {
        return char.isIdentifierChar(ch);
    }

    fn isHexDigit(ch: u8) bool {
        return char.isHexDigit(ch);
    }

    fn isBinaryDigit(ch: u8) bool {
        return char.isBinaryDigit(ch);
    }

    fn isOctalDigit(ch: u8) bool {
        return char.isOctalDigit(ch);
    }
};

/// Convenience function for tokenizing ZON source
pub fn tokenize(allocator: std.mem.Allocator, source: []const u8) ![]Token {
    var lexer = ZonLexer.init(allocator, source, .{});
    defer lexer.deinit();
    return lexer.tokenize();
}
