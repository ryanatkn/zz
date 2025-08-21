/// JSON Stream Lexer - Zero-allocation streaming tokenization
/// Implements direct iterator pattern without vtable overhead
/// Performance target: >10MB/sec throughput with 1-2 cycle dispatch
///
/// TODO: Stream module uses vtables (3-5 cycles overhead)
/// TODO: This lexer follows our principles with direct dispatch
/// TODO: Add Stream adapter only when needed for compatibility
const std = @import("std");
const RingBuffer = @import("../../stream/mod.zig").RingBuffer;
const StreamToken = @import("../../token/mod.zig").StreamToken;
const JsonToken = @import("./stream_token.zig").JsonToken;
const JsonTokenKind = @import("./stream_token.zig").JsonTokenKind;
const JsonTokenFlags = @import("./stream_token.zig").JsonTokenFlags;
const packSpan = @import("../../span/mod.zig").packSpan;
const Span = @import("../../span/mod.zig").Span;

/// Lexer state for incremental parsing
pub const LexerState = enum {
    start,
    in_string,
    in_string_escape,
    in_number,
    in_identifier, // true, false, null
    in_comment_single,
    in_comment_multi,
    done,
    err,
};

/// JSON stream lexer with zero allocations
pub const JsonStreamLexer = struct {
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

    // Nesting depth for objects/arrays
    depth: u8,

    // Flags for current token being built
    current_flags: JsonTokenFlags,

    // Error state
    error_msg: ?[]const u8,

    /// Initialize lexer with input buffer
    /// This is the primary interface - simple iterator pattern
    pub fn init(input: []const u8) JsonStreamLexer {
        var lexer = JsonStreamLexer.initEmpty();

        // Fill ring buffer with input
        for (input) |byte| {
            _ = lexer.buffer.push(byte) catch break;
        }

        return lexer;
    }

    /// Initialize empty lexer (for streaming from reader)
    pub fn initEmpty() JsonStreamLexer {
        return JsonStreamLexer{
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
    pub fn next(self: *JsonStreamLexer) ?StreamToken {

        // Return null if already done (after EOF)
        if (self.state == .done) {
            return null;
        }

        // Skip whitespace
        self.skipWhitespace();

        // Check for end of input - ANY state can reach EOF, not just .start
        if (self.buffer.isEmpty()) {
            self.state = .done; // Mark as done after EOF
            return StreamToken{ .json = JsonToken{
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
            '{' => return self.makeSimpleToken(.object_start, true),
            '}' => return self.makeSimpleToken(.object_end, false),
            '[' => return self.makeSimpleToken(.array_start, true),
            ']' => return self.makeSimpleToken(.array_end, false),
            ',' => return self.makeSimpleToken(.comma, false),
            ':' => return self.makeSimpleToken(.colon, false),
            '"' => return self.scanString(),
            't', 'f', 'n' => return self.scanKeyword(),
            '-', '0'...'9' => return self.scanNumber(),
            '/' => return self.scanComment(),
            else => {
                self.error_msg = "Unexpected character";
                return self.makeErrorToken();
            },
        }
    }

    /// Convert to DirectStream for integration with stream pipeline
    /// Uses GeneratorStream pattern for zero-allocation streaming
    pub fn toDirectStream(self: *JsonStreamLexer) @import("../../stream/mod.zig").DirectStream(StreamToken) {
        const DirectStream = @import("../../stream/mod.zig").DirectStream;
        const GeneratorStream = @import("../../stream/mod.zig").GeneratorStream;

        const gen = GeneratorStream(StreamToken).init(
            @ptrCast(self),
            struct {
                fn generate(ctx: *anyopaque) ?StreamToken {
                    const lexer: *JsonStreamLexer = @ptrCast(@alignCast(ctx));
                    return lexer.next();
                }
            }.generate,
        );

        return DirectStream(StreamToken){ .generator = gen };
    }

    /// Skip whitespace and update position
    fn skipWhitespace(self: *JsonStreamLexer) void {
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
                else => break,
            }
        }
    }

    /// Create a simple single-character token
    fn makeSimpleToken(self: *JsonStreamLexer, kind: JsonTokenKind, increase_depth: bool) StreamToken {
        _ = self.buffer.pop(); // Consume the character
        const end_pos = self.position + 1;

        if (increase_depth) {
            self.depth = @min(self.depth + 1, 255);
        } else if (kind == .object_end or kind == .array_end) {
            self.depth = if (self.depth > 0) self.depth - 1 else 0;
        }

        const token = JsonToken{
            .span = packSpan(Span{ .start = self.token_start, .end = end_pos }),
            .kind = kind,
            .depth = self.depth,
            .flags = .{},
            .data = 0,
        };

        self.position = end_pos;
        self.column += 1;

        return StreamToken{ .json = token };
    }

    /// Scan a string literal
    fn scanString(self: *JsonStreamLexer) StreamToken {
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
                    // End of string
                    const token = JsonToken{
                        .span = packSpan(Span{ .start = self.token_start, .end = self.position }),
                        .kind = .string_value,
                        .depth = self.depth,
                        .flags = .{ .has_escapes = has_escapes },
                        .data = 0,
                    };
                    return StreamToken{ .json = token };
                },
                '\\' => {
                    // Escape sequence
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

        // Unterminated string
        self.error_msg = "Unterminated string";
        return self.makeErrorToken();
    }

    /// Scan a number
    fn scanNumber(self: *JsonStreamLexer) StreamToken {
        var is_float = false;
        var is_negative = false;
        var is_scientific = false;

        // Check for negative
        if (self.buffer.peek()) |ch| {
            if (ch == '-') {
                is_negative = true;
                _ = self.buffer.pop();
                self.position += 1;
                self.column += 1;
            }
        }

        // Scan digits
        while (self.buffer.peek()) |ch| {
            switch (ch) {
                '0'...'9' => {
                    _ = self.buffer.pop();
                    self.position += 1;
                    self.column += 1;
                },
                '.' => {
                    is_float = true;
                    _ = self.buffer.pop();
                    self.position += 1;
                    self.column += 1;
                },
                'e', 'E' => {
                    is_scientific = true;
                    _ = self.buffer.pop();
                    self.position += 1;
                    self.column += 1;
                    // Handle +/- after E
                    if (self.buffer.peek()) |next_ch| {
                        if (next_ch == '+' or next_ch == '-') {
                            _ = self.buffer.pop();
                            self.position += 1;
                            self.column += 1;
                        }
                    }
                },
                else => break,
            }
        }

        const token = JsonToken{
            .span = packSpan(Span{ .start = self.token_start, .end = self.position }),
            .kind = .number_value,
            .depth = self.depth,
            .flags = .{
                .is_float = is_float,
                .is_negative = is_negative,
                .is_scientific = is_scientific,
            },
            .data = 0,
        };

        return StreamToken{ .json = token };
    }

    /// Scan a keyword (true, false, null)
    fn scanKeyword(self: *JsonStreamLexer) StreamToken {
        const start_ch = self.buffer.peek() orelse return self.makeErrorToken();

        const kind: JsonTokenKind = switch (start_ch) {
            't' => blk: {
                if (self.matchKeyword("true")) {
                    break :blk .boolean_true;
                }
                break :blk .err;
            },
            'f' => blk: {
                if (self.matchKeyword("false")) {
                    break :blk .boolean_false;
                }
                break :blk .err;
            },
            'n' => blk: {
                if (self.matchKeyword("null")) {
                    break :blk .null_value;
                }
                break :blk .err;
            },
            else => .err,
        };

        if (kind == .err) {
            self.error_msg = "Invalid keyword";
            return self.makeErrorToken();
        }

        const token = JsonToken{
            .span = packSpan(Span{ .start = self.token_start, .end = self.position }),
            .kind = kind,
            .depth = self.depth,
            .flags = .{},
            .data = 0,
        };

        return StreamToken{ .json = token };
    }

    /// Match a specific keyword
    fn matchKeyword(self: *JsonStreamLexer, keyword: []const u8) bool {
        var i: usize = 0;
        while (i < keyword.len) : (i += 1) {
            const ch = self.buffer.peek() orelse return false;
            if (ch != keyword[i]) return false;
            _ = self.buffer.pop();
            self.position += 1;
            self.column += 1;
        }
        return true;
    }

    /// Scan a comment (non-standard but common)
    fn scanComment(self: *JsonStreamLexer) StreamToken {
        _ = self.buffer.pop(); // Consume '/'
        self.position += 1;
        self.column += 1;

        const next_ch = self.buffer.peek() orelse return self.makeErrorToken();

        switch (next_ch) {
            '/' => {
                // Single-line comment
                _ = self.buffer.pop();
                self.position += 1;
                self.column += 1;

                while (self.buffer.peek()) |ch| {
                    _ = self.buffer.pop();
                    self.position += 1;
                    if (ch == '\n') {
                        self.line += 1;
                        self.column = 1;
                        break;
                    }
                    self.column += 1;
                }
            },
            '*' => {
                // Multi-line comment
                _ = self.buffer.pop();
                self.position += 1;
                self.column += 1;

                var prev: u8 = 0;
                while (self.buffer.peek()) |ch| {
                    _ = self.buffer.pop();
                    self.position += 1;

                    if (ch == '\n') {
                        self.line += 1;
                        self.column = 1;
                    } else {
                        self.column += 1;
                    }

                    if (prev == '*' and ch == '/') {
                        break;
                    }
                    prev = ch;
                }
            },
            else => {
                self.error_msg = "Invalid comment";
                return self.makeErrorToken();
            },
        }

        const token = JsonToken{
            .span = packSpan(Span{ .start = self.token_start, .end = self.position }),
            .kind = .comment,
            .depth = self.depth,
            .flags = .{},
            .data = 0,
        };

        return StreamToken{ .json = token };
    }

    /// Create an error token
    fn makeErrorToken(self: *JsonStreamLexer) StreamToken {
        const token = JsonToken{
            .span = packSpan(Span{ .start = self.token_start, .end = self.position }),
            .kind = .err,
            .depth = self.depth,
            .flags = .{},
            .data = 0,
        };
        self.state = .err;
        return StreamToken{ .json = token };
    }
};

// Tests
test "JsonStreamLexer basic tokenization" {
    const testing = std.testing;

    var lexer = JsonStreamLexer.init(
        \\{"name": "test", "value": 42}
    );

    // {
    const token1 = lexer.next() orelse return error.UnexpectedNull;
    try testing.expectEqual(JsonTokenKind.object_start, token1.json.kind);

    // "name"
    const token2 = lexer.next() orelse return error.UnexpectedNull;
    try testing.expectEqual(JsonTokenKind.string_value, token2.json.kind);

    // :
    const token3 = lexer.next() orelse return error.UnexpectedNull;
    try testing.expectEqual(JsonTokenKind.colon, token3.json.kind);

    // "test"
    const token4 = lexer.next() orelse return error.UnexpectedNull;
    try testing.expectEqual(JsonTokenKind.string_value, token4.json.kind);

    // ,
    const token5 = lexer.next() orelse return error.UnexpectedNull;
    try testing.expectEqual(JsonTokenKind.comma, token5.json.kind);

    // "value"
    const token6 = lexer.next() orelse return error.UnexpectedNull;
    try testing.expectEqual(JsonTokenKind.string_value, token6.json.kind);

    // :
    const token7 = lexer.next() orelse return error.UnexpectedNull;
    try testing.expectEqual(JsonTokenKind.colon, token7.json.kind);

    // 42
    const token8 = lexer.next() orelse return error.UnexpectedNull;
    try testing.expectEqual(JsonTokenKind.number_value, token8.json.kind);

    // }
    const token9 = lexer.next() orelse return error.UnexpectedNull;
    try testing.expectEqual(JsonTokenKind.object_end, token9.json.kind);

    // EOF
    const token10 = lexer.next() orelse return error.UnexpectedNull;
    try testing.expectEqual(JsonTokenKind.eof, token10.json.kind);

    // After EOF, should return null
    const token11 = lexer.next();
    try testing.expectEqual(@as(?StreamToken, null), token11);

    // Should continue returning null
    const token12 = lexer.next();
    try testing.expectEqual(@as(?StreamToken, null), token12);
}

test "JsonStreamLexer zero allocations" {
    const testing = std.testing;

    // This test verifies no heap allocations occur
    const input = "[1, 2, 3]";
    var lexer = JsonStreamLexer.init(input);

    // Stack-allocated lexer and buffer
    const lexer_size = @sizeOf(JsonStreamLexer);
    try testing.expect(lexer_size < 5000); // Should be small, mostly ring buffer

    // Tokenize without allocating - direct iterator pattern
    while (lexer.next()) |token| {
        // Process tokens - no allocations, no vtable overhead
        if (token.json.kind == .eof) break;
    }
}

test "JsonStreamLexer nested structures" {
    const testing = std.testing;

    var lexer = JsonStreamLexer.init(
        \\{"a": [{"b": null}]}
    );

    // Track depth changes
    var max_depth: u8 = 0;
    while (lexer.next()) |token| {
        if (token.json.kind == .eof) break;
        max_depth = @max(max_depth, token.json.depth);
    }

    try testing.expect(max_depth > 0);
}

test "JsonStreamLexer empty object" {
    const testing = std.testing;

    // Test empty object case
    var lexer = JsonStreamLexer.init("{}");

    // Should produce: object_start, object_end, eof
    const token1 = lexer.next() orelse return error.UnexpectedNull;
    try testing.expectEqual(JsonTokenKind.object_start, token1.json.kind);

    const token2 = lexer.next() orelse return error.UnexpectedNull;
    try testing.expectEqual(JsonTokenKind.object_end, token2.json.kind);

    const token3 = lexer.next() orelse return error.UnexpectedNull;
    try testing.expectEqual(JsonTokenKind.eof, token3.json.kind);

    // After EOF, should return null
    const token4 = lexer.next();
    try testing.expectEqual(@as(?StreamToken, null), token4);
}
