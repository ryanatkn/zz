/// ZON Stream Lexer - Zero-allocation streaming tokenization for Zig Object Notation
/// Implements direct iterator pattern without vtable overhead
/// Performance target: >10MB/sec throughput with 1-2 cycle dispatch
///
/// TODO: Stream module uses vtables (3-5 cycles overhead)
/// TODO: This lexer follows our principles with direct dispatch
/// TODO: Add Stream adapter only when needed for compatibility
const std = @import("std");
const RingBuffer = @import("../../stream/mod.zig").RingBuffer;
const StreamToken = @import("../../token/mod.zig").StreamToken;
const ZonToken = @import("./stream_token.zig").ZonToken;
const ZonTokenKind = @import("./stream_token.zig").ZonTokenKind;
const ZonTokenFlags = @import("./stream_token.zig").ZonTokenFlags;
const packSpan = @import("../../span/mod.zig").packSpan;
const Span = @import("../../span/mod.zig").Span;

/// Lexer state for incremental parsing
pub const LexerState = enum {
    start,
    in_string,
    in_string_escape,
    in_multiline_string,
    in_number,
    in_identifier,
    in_comment,
    done,
    err,
};

/// ZON stream lexer with zero allocations
pub const ZonStreamLexer = struct {
    // Ring buffer for lookahead (4KB on stack)
    buffer: RingBuffer(u8, 4096),

    // Current lexer state
    state: LexerState,

    // Position tracking
    position: u32,
    line: u32,
    column: u32,

    // Token start position
    token_start: u32,
    token_line: u32,
    token_column: u32,

    // Nesting depth
    depth: u8,

    // Flags for current token
    current_flags: ZonTokenFlags,

    // Error state
    error_msg: ?[]const u8,

    /// Initialize lexer with input buffer
    /// This is the primary interface - simple iterator pattern
    pub fn init(input: []const u8) ZonStreamLexer {
        var lexer = ZonStreamLexer.initEmpty();

        // Fill ring buffer with input
        for (input) |byte| {
            _ = lexer.buffer.push(byte) catch break;
        }

        return lexer;
    }

    /// Initialize empty lexer (for streaming from reader)
    pub fn initEmpty() ZonStreamLexer {
        return .{
            .buffer = RingBuffer(u8, 4096).init(),
            .state = .start,
            .position = 0,
            .line = 1,
            .column = 1,
            .token_start = 0,
            .token_line = 1,
            .token_column = 1,
            .depth = 0,
            .current_flags = .{},
            .error_msg = null,
        };
    }

    /// Get next token - Direct iterator interface (no vtable!)
    /// This is 1-2 cycle dispatch vs 3-5 for vtable
    pub fn next(self: *ZonStreamLexer) ?StreamToken {

        // Return null if already done (after EOF)
        if (self.state == .done) {
            return null;
        }

        // Skip whitespace and comments
        self.skipWhitespaceAndComments();

        // Check for end of input - ANY state can reach EOF, not just .start
        if (self.buffer.isEmpty()) {
            self.state = .done; // Mark as done after EOF
            return StreamToken{ .zon = ZonToken{
                .span = packSpan(Span{ .start = self.position, .end = self.position }),
                .kind = .eof,
                .depth = self.depth,
                .flags = .{},
                .data = 0,
            } };
        }

        // Mark token start
        self.token_start = self.position;
        self.token_line = self.line;
        self.token_column = self.column;
        self.current_flags = .{};

        // Get next character
        const ch = self.buffer.peek() orelse return null;

        // Dispatch based on character
        switch (ch) {
            '.' => {
                // Could be .{} struct or .field
                _ = self.buffer.pop();
                self.position += 1;
                self.column += 1;

                if (self.buffer.peek()) |next_ch| {
                    if (next_ch == '{') {
                        _ = self.buffer.pop();
                        self.position += 1;
                        self.column += 1;
                        self.depth = @min(self.depth + 1, 255);
                        return StreamToken{ .zon = ZonToken{
                            .span = packSpan(Span{ .start = self.token_start, .end = self.position }),
                            .kind = .struct_start,
                            .depth = self.depth,
                            .flags = .{},
                            .data = 0,
                        } };
                    }
                }
                return self.scanFieldAccess();
            },
            '{' => return self.makeSimpleToken(.object_start, true),
            '}' => return self.makeSimpleToken(.object_end, false),
            '(' => return self.makeSimpleToken(.paren_open, true),
            ')' => return self.makeSimpleToken(.paren_close, false),
            '[' => return self.makeSimpleToken(.array_start, true),
            ']' => return self.makeSimpleToken(.array_end, false),
            ',' => return self.makeSimpleToken(.comma, false),
            ':' => return self.makeSimpleToken(.colon, false),
            '=' => return self.makeSimpleToken(.equals, false),
            '"' => return self.scanString(),
            '\\' => return self.scanMultilineString(),
            '@' => return self.scanBuiltin(),
            '0'...'9', '-', '+' => return self.scanNumber(),
            'a'...'z', 'A'...'Z', '_' => return self.scanIdentifier(),
            else => {
                self.error_msg = "Unexpected character";
                return self.makeErrorToken();
            },
        }
    }

    /// Convert to DirectStream for integration with stream pipeline
    /// Uses GeneratorStream pattern for zero-allocation streaming
    pub fn toDirectStream(self: *ZonStreamLexer) @import("../../stream/mod.zig").DirectStream(StreamToken) {
        const DirectStream = @import("../../stream/mod.zig").DirectStream;
        const GeneratorStream = @import("../../stream/mod.zig").GeneratorStream;

        const gen = GeneratorStream(StreamToken).init(
            @ptrCast(self),
            struct {
                fn generate(ctx: *anyopaque) ?StreamToken {
                    const lexer: *ZonStreamLexer = @ptrCast(@alignCast(ctx));
                    return lexer.next();
                }
            }.generate,
        );

        return DirectStream(StreamToken){ .generator = gen };
    }

    /// Skip whitespace and comments
    fn skipWhitespaceAndComments(self: *ZonStreamLexer) void {
        while (self.buffer.peek()) |ch| {
            switch (ch) {
                ' ', '\t', '\r' => {
                    _ = self.buffer.pop();
                    self.position += 1;
                    self.column += 1;
                },
                '\n' => {
                    _ = self.buffer.pop();
                    self.position += 1;
                    self.line += 1;
                    self.column = 1;
                },
                '/' => {
                    // Check for comment
                    _ = self.buffer.pop();
                    self.position += 1;
                    self.column += 1;

                    if (self.buffer.peek()) |next_ch| {
                        if (next_ch == '/') {
                            // Single-line comment
                            _ = self.buffer.pop();
                            self.position += 1;
                            self.column += 1;

                            while (self.buffer.peek()) |comment_ch| {
                                _ = self.buffer.pop();
                                self.position += 1;
                                if (comment_ch == '\n') {
                                    self.line += 1;
                                    self.column = 1;
                                    break;
                                }
                                self.column += 1;
                            }
                        } else {
                            // Not a comment, push back the '/'
                            // TODO: Implement unget for ring buffer
                            return;
                        }
                    }
                },
                else => return,
            }
        }
    }

    /// Create a simple single-character token
    fn makeSimpleToken(self: *ZonStreamLexer, kind: ZonTokenKind, increase_depth: bool) StreamToken {
        _ = self.buffer.pop();
        const end_pos = self.position + 1;

        if (increase_depth) {
            self.depth = @min(self.depth + 1, 255);
        } else if (kind == .object_end or kind == .array_end or kind == .paren_close) {
            self.depth = if (self.depth > 0) self.depth - 1 else 0;
        }

        const token = ZonToken{
            .span = packSpan(Span{ .start = self.token_start, .end = end_pos }),
            .kind = kind,
            .depth = self.depth,
            .flags = .{},
            .data = 0,
        };

        self.position = end_pos;
        self.column += 1;

        return StreamToken{ .zon = token };
    }

    /// Scan a string literal
    fn scanString(self: *ZonStreamLexer) StreamToken {
        _ = self.buffer.pop(); // Consume opening quote
        self.position += 1;
        self.column += 1;

        var has_escapes = false;

        while (self.buffer.peek()) |ch| {
            _ = self.buffer.pop();
            self.position += 1;
            self.column += 1;

            switch (ch) {
                '"' => {
                    const token = ZonToken{
                        .span = packSpan(Span{ .start = self.token_start, .end = self.position }),
                        .kind = .string_value,
                        .depth = self.depth,
                        .flags = .{ .has_escapes = has_escapes },
                        .data = 0,
                    };
                    return StreamToken{ .zon = token };
                },
                '\\' => {
                    has_escapes = true;
                    if (self.buffer.pop()) |_| {
                        self.position += 1;
                        self.column += 1;
                    }
                },
                '\n' => {
                    self.line += 1;
                    self.column = 1;
                },
                else => {},
            }
        }

        self.error_msg = "Unterminated string";
        return self.makeErrorToken();
    }

    /// Scan a multiline string (\\\\)
    fn scanMultilineString(self: *ZonStreamLexer) StreamToken {
        _ = self.buffer.pop(); // Consume first backslash
        self.position += 1;
        self.column += 1;

        if (self.buffer.peek()) |ch| {
            if (ch == '\\') {
                _ = self.buffer.pop();
                self.position += 1;
                self.column += 1;

                // Scan until we find another \\\\
                var line_count: u32 = 0;
                while (self.buffer.peek()) |scan_ch| {
                    _ = self.buffer.pop();
                    self.position += 1;

                    if (scan_ch == '\n') {
                        self.line += 1;
                        self.column = 1;
                        line_count += 1;
                    } else {
                        self.column += 1;
                    }

                    if (scan_ch == '\\') {
                        if (self.buffer.peek()) |next_ch| {
                            if (next_ch == '\\') {
                                _ = self.buffer.pop();
                                self.position += 1;
                                self.column += 1;

                                const token = ZonToken{
                                    .span = packSpan(Span{ .start = self.token_start, .end = self.position }),
                                    .kind = .string_value,
                                    .depth = self.depth,
                                    .flags = .{ .multiline_string = true },
                                    .data = 0,
                                };
                                return StreamToken{ .zon = token };
                            }
                        }
                    }
                }
            }
        }

        self.error_msg = "Invalid multiline string";
        return self.makeErrorToken();
    }

    /// Scan a number
    fn scanNumber(self: *ZonStreamLexer) StreamToken {
        var is_float = false;
        var is_hex = false;
        var is_binary = false;
        var is_octal = false;

        // Check for sign or special prefixes
        if (self.buffer.peek()) |ch| {
            if (ch == '0') {
                _ = self.buffer.pop();
                self.position += 1;
                self.column += 1;

                if (self.buffer.peek()) |next_ch| {
                    switch (next_ch) {
                        'x', 'X' => {
                            is_hex = true;
                            _ = self.buffer.pop();
                            self.position += 1;
                            self.column += 1;
                        },
                        'b', 'B' => {
                            is_binary = true;
                            _ = self.buffer.pop();
                            self.position += 1;
                            self.column += 1;
                        },
                        'o', 'O' => {
                            is_octal = true;
                            _ = self.buffer.pop();
                            self.position += 1;
                            self.column += 1;
                        },
                        else => {},
                    }
                }
            } else if (ch == '-' or ch == '+') {
                _ = self.buffer.pop();
                self.position += 1;
                self.column += 1;
            }
        }

        // Scan number body
        while (self.buffer.peek()) |ch| {
            const valid = if (is_hex)
                (ch >= '0' and ch <= '9') or (ch >= 'a' and ch <= 'f') or (ch >= 'A' and ch <= 'F') or ch == '_'
            else if (is_binary)
                ch == '0' or ch == '1' or ch == '_'
            else if (is_octal)
                (ch >= '0' and ch <= '7') or ch == '_'
            else
                (ch >= '0' and ch <= '9') or ch == '.' or ch == 'e' or ch == 'E' or ch == '_';

            if (!valid) break;

            if (ch == '.') is_float = true;

            _ = self.buffer.pop();
            self.position += 1;
            self.column += 1;
        }

        const token = ZonToken{
            .span = packSpan(Span{ .start = self.token_start, .end = self.position }),
            .kind = .number_value,
            .depth = self.depth,
            .flags = .{
                .is_float = is_float,
                .is_hex = is_hex,
                .is_binary = is_binary,
                .is_octal = is_octal,
            },
            .data = 0,
        };

        return StreamToken{ .zon = token };
    }

    /// Scan an identifier or keyword
    fn scanIdentifier(self: *ZonStreamLexer) StreamToken {
        while (self.buffer.peek()) |ch| {
            if ((ch >= 'a' and ch <= 'z') or
                (ch >= 'A' and ch <= 'Z') or
                (ch >= '0' and ch <= '9') or
                ch == '_')
            {
                _ = self.buffer.pop();
                self.position += 1;
                self.column += 1;
            } else {
                break;
            }
        }

        // Check for keywords
        const len = self.position - self.token_start;
        const kind: ZonTokenKind = if (len == 4 and self.matchesKeywordAt("true", self.token_start))
            .boolean_true
        else if (len == 5 and self.matchesKeywordAt("false", self.token_start))
            .boolean_false
        else if (len == 4 and self.matchesKeywordAt("null", self.token_start))
            .null_value
        else if (len == 9 and self.matchesKeywordAt("undefined", self.token_start))
            .undefined
        else
            .identifier;

        const token = ZonToken{
            .span = packSpan(Span{ .start = self.token_start, .end = self.position }),
            .kind = kind,
            .depth = self.depth,
            .flags = .{},
            .data = 0,
        };

        return StreamToken{ .zon = token };
    }

    /// Scan a builtin (@import, @field, etc.)
    fn scanBuiltin(self: *ZonStreamLexer) StreamToken {
        _ = self.buffer.pop(); // Consume @
        self.position += 1;
        self.column += 1;

        while (self.buffer.peek()) |ch| {
            if ((ch >= 'a' and ch <= 'z') or
                (ch >= 'A' and ch <= 'Z') or
                ch == '_')
            {
                _ = self.buffer.pop();
                self.position += 1;
                self.column += 1;
            } else {
                break;
            }
        }

        const token = ZonToken{
            .span = packSpan(Span{ .start = self.token_start, .end = self.position }),
            .kind = .import,
            .depth = self.depth,
            .flags = .{},
            .data = 0,
        };

        return StreamToken{ .zon = token };
    }

    /// Scan a field access (.field_name)
    fn scanFieldAccess(self: *ZonStreamLexer) StreamToken {
        while (self.buffer.peek()) |ch| {
            if ((ch >= 'a' and ch <= 'z') or
                (ch >= 'A' and ch <= 'Z') or
                (ch >= '0' and ch <= '9') or
                ch == '_')
            {
                _ = self.buffer.pop();
                self.position += 1;
                self.column += 1;
            } else {
                break;
            }
        }

        const token = ZonToken{
            .span = packSpan(Span{ .start = self.token_start, .end = self.position }),
            .kind = .field_name,
            .depth = self.depth,
            .flags = .{},
            .data = 0,
        };

        return StreamToken{ .zon = token };
    }

    /// Check if buffer matches keyword at position (simplified)
    fn matchesKeywordAt(self: *ZonStreamLexer, keyword: []const u8, start: u32) bool {
        _ = self;
        _ = keyword;
        _ = start;
        // TODO: Implement proper keyword matching with buffer history
        return false;
    }

    /// Create an error token
    fn makeErrorToken(self: *ZonStreamLexer) StreamToken {
        const token = ZonToken{
            .span = packSpan(Span{ .start = self.token_start, .end = self.position }),
            .kind = .err,
            .depth = self.depth,
            .flags = .{},
            .data = 0,
        };
        self.state = .err;
        return StreamToken{ .zon = token };
    }
};

// Tests
test "ZonStreamLexer basic tokenization" {
    const testing = std.testing;

    var lexer = ZonStreamLexer.init(
        \\.{ .name = "test", .value = 42 }
    );

    // .{
    const token1 = lexer.next() orelse return error.UnexpectedNull;
    try testing.expectEqual(ZonTokenKind.struct_start, token1.zon.kind);

    // .name
    const token2 = lexer.next() orelse return error.UnexpectedNull;
    try testing.expectEqual(ZonTokenKind.field_name, token2.zon.kind);

    // =
    const token3 = lexer.next() orelse return error.UnexpectedNull;
    try testing.expectEqual(ZonTokenKind.equals, token3.zon.kind);

    // "test"
    const token4 = lexer.next() orelse return error.UnexpectedNull;
    try testing.expectEqual(ZonTokenKind.string_value, token4.zon.kind);
}

test "ZonStreamLexer zero allocations" {
    const testing = std.testing;

    const input = ".{ .a = 1, .b = 2 }";
    var lexer = ZonStreamLexer.init(input);

    // Stack-allocated lexer
    const lexer_size = @sizeOf(ZonStreamLexer);
    try testing.expect(lexer_size < 5000);

    // Tokenize without allocating
    while (lexer.next()) |token| {
        // Process tokens - no allocations
        if (token.zon.kind == .eof) break;
    }
}

test "ZonStreamLexer multiline strings" {
    const testing = std.testing;

    var lexer = ZonStreamLexer.init(
        \\\\This is a
        \\multiline string\\
    );

    const token = lexer.next() orelse return error.UnexpectedNull;
    try testing.expectEqual(ZonTokenKind.string_value, token.zon.kind);
    try testing.expect(token.zon.flags.multiline_string);
}

test "ZonStreamLexer EOF handling" {
    const testing = std.testing;

    var lexer = ZonStreamLexer.init("42");

    // Get number token
    const token1 = lexer.next() orelse return error.UnexpectedNull;
    try testing.expectEqual(ZonTokenKind.number_value, token1.zon.kind);

    // Get EOF token
    const token2 = lexer.next() orelse return error.UnexpectedNull;
    try testing.expectEqual(ZonTokenKind.eof, token2.zon.kind);

    // After EOF, should return null
    const token3 = lexer.next();
    try testing.expectEqual(@as(?StreamToken, null), token3);

    // Should continue returning null
    const token4 = lexer.next();
    try testing.expectEqual(@as(?StreamToken, null), token4);
}
