/// JSON Stream Lexer - Core functionality
/// Zero-allocation streaming tokenization with 1-2 cycle dispatch
///
/// This module contains:
/// - Core lexer structure and initialization
/// - Main token processing logic
/// - Scanning methods (string, number, keyword, comment)
/// - Utility methods
const std = @import("std");
const RingBuffer = @import("../../../stream/mod.zig").RingBuffer;
const Token = @import("../../../token/mod.zig").Token;
const JsonToken = @import("../token/types.zig").Token;
const TokenKind = @import("../token/types.zig").TokenKind;
const TokenFlags = @import("../token/types.zig").TokenFlags;
const packSpan = @import("../../../span/mod.zig").packSpan;
const Span = @import("../../../span/mod.zig").Span;
const TokenBuffer = @import("../token/buffer.zig").TokenBuffer;
const TokenState = @import("../token/buffer.zig").TokenState;

// Re-export boundary functionality
const boundary = @import("boundaries.zig");
pub const feedData = boundary.feedData;
pub const peek = boundary.peek;
pub const continueBoundaryToken = boundary.continueBoundaryToken;

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

/// JSON stream lexer with boundary-aware token handling
pub const Lexer = struct {
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

    // Context tracking: stack of contexts (object/array) for each depth level
    context_stack: u32, // Each bit indicates: 0=array, 1=object

    // Context for determining property names vs string values
    expecting_property_key: bool,

    // Flags for current token being built
    current_flags: TokenFlags,

    // Error state
    error_msg: ?[]const u8,

    // Dynamic token buffer for handling 4KB boundary crossings
    token_buffer: ?TokenBuffer,
    allocator: ?std.mem.Allocator,

    // Peeked token for lookahead
    peeked_token: ?Token,

    /// Initialize lexer with input buffer - primary interface
    pub fn init(input: []const u8) Lexer {
        var lexer = Lexer.initEmpty();
        for (input) |byte| {
            _ = lexer.buffer.push(byte) catch break;
        }
        return lexer;
    }

    /// Initialize boundary-aware lexer with allocator
    pub fn initWithAllocator(allocator: std.mem.Allocator) Lexer {
        return Lexer{
            .buffer = RingBuffer(u8, 4096).init(),
            .state = .start,
            .position = 0,
            .line = 1,
            .column = 1,
            .token_start = 0,
            .token_line = 1,
            .token_column = 1,
            .depth = 0,
            .context_stack = 0,
            .expecting_property_key = false,
            .current_flags = .{},
            .error_msg = null,
            .token_buffer = null,
            .allocator = allocator,
            .peeked_token = null,
        };
    }

    /// Initialize empty lexer for streaming
    pub fn initEmpty() Lexer {
        return Lexer{
            .buffer = RingBuffer(u8, 4096).init(),
            .state = .start,
            .position = 0,
            .line = 1,
            .column = 1,
            .token_start = 0,
            .token_line = 1,
            .token_column = 1,
            .depth = 0,
            .context_stack = 0,
            .expecting_property_key = false,
            .current_flags = .{},
            .error_msg = null,
            .token_buffer = null,
            .allocator = null,
            .peeked_token = null,
        };
    }

    /// Clean up dynamic resources
    pub fn deinit(self: *Lexer) void {
        if (self.token_buffer) |*buf| {
            buf.deinit();
        }
    }

    /// Get next token - Direct iterator interface (1-2 cycle dispatch)
    pub fn next(self: *Lexer) ?Token {
        if (self.peeked_token) |token| {
            self.peeked_token = null;
            return token;
        }
        return self.nextInternal();
    }

    fn nextInternal(self: *Lexer) ?Token {
        if (self.state == .done) return null;

        self.skipWhitespace();

        if (self.buffer.isEmpty()) {
            self.state = .done;
            return Token{ .json = .{
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

        const ch = self.buffer.peek() orelse return null;

        // Dispatch to appropriate scanner
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

    /// Peek at next token without consuming (method interface for compatibility)
    pub fn peek(self: *Lexer) ?Token {
        return boundary.peek(self);
    }

    /// Feed more data for boundary continuation (method interface for compatibility)
    pub fn feedData(self: *Lexer, data: []const u8) !void {
        return boundary.feedData(self, data);
    }

    /// Convert to DirectStream for pipeline integration
    pub fn toDirectStream(self: *Lexer) @import("../../../stream/mod.zig").DirectStream(Token) {
        const DirectStream = @import("../../../stream/mod.zig").DirectStream;
        const GeneratorStream = @import("../../../stream/mod.zig").GeneratorStream;

        const gen = GeneratorStream(Token).init(
            @ptrCast(self),
            struct {
                fn generate(ctx: *anyopaque) ?Token {
                    const lexer: *Lexer = @ptrCast(@alignCast(ctx));
                    return lexer.next();
                }
            }.generate,
        );

        return DirectStream(Token){ .generator = gen };
    }

    /// Scan a string literal
    fn scanString(self: *Lexer) Token {
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
                    // End of string found
                    const kind: TokenKind = if (self.expecting_property_key) .property_name else .string_value;

                    if (self.expecting_property_key) {
                        self.expecting_property_key = false;
                    }

                    const token = JsonToken{
                        .span = packSpan(Span{ .start = self.token_start, .end = self.position }),
                        .kind = kind,
                        .depth = self.depth,
                        .flags = .{ .has_escapes = has_escapes },
                        .data = 0,
                    };
                    return Token{ .json = token };
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

        // Handle boundary case
        if (self.allocator) |allocator| {
            if (self.token_buffer == null) {
                self.token_buffer = TokenBuffer.init(allocator);
            }

            if (self.token_buffer) |*buf| {
                buf.startToken(.in_string, self.token_start, self.token_line, self.token_column) catch {
                    self.error_msg = "Out of memory for boundary token";
                    return self.makeErrorToken();
                };
                buf.setStringFlags(has_escapes, false);
                self.state = .in_string;
                return self.makeContinuationToken();
            }
        }

        self.error_msg = "Unterminated string";
        return self.makeErrorToken();
    }

    /// Scan a number
    fn scanNumber(self: *Lexer) Token {
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

        // RFC8259 validation for leading zeros
        if (self.buffer.peek()) |first_ch| {
            if (first_ch == '0') {
                _ = self.buffer.pop();
                self.position += 1;
                self.column += 1;

                if (self.buffer.peek()) |second_ch| {
                    if (second_ch >= '0' and second_ch <= '9') {
                        return self.makeErrorToken(); // Leading zero error
                    }
                }
            } else {
                // Scan integer part
                while (self.buffer.peek()) |ch| {
                    if (ch >= '0' and ch <= '9') {
                        _ = self.buffer.pop();
                        self.position += 1;
                        self.column += 1;
                    } else {
                        break;
                    }
                }
            }
        }

        // Scan fractional and exponential parts
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
                    // Handle optional +/-
                    if (self.buffer.peek()) |next_ch| {
                        if (next_ch == '+' or next_ch == '-') {
                            _ = self.buffer.pop();
                            self.position += 1;
                            self.column += 1;
                        }
                    }
                    // Scan exponent digits with leading zero validation
                    if (self.buffer.peek()) |exp_first| {
                        if (exp_first == '0') {
                            _ = self.buffer.pop();
                            self.position += 1;
                            self.column += 1;
                            if (self.buffer.peek()) |exp_second| {
                                if (exp_second >= '0' and exp_second <= '9') {
                                    return self.makeErrorToken();
                                }
                            }
                        } else {
                            while (self.buffer.peek()) |exp_ch| {
                                if (exp_ch >= '0' and exp_ch <= '9') {
                                    _ = self.buffer.pop();
                                    self.position += 1;
                                    self.column += 1;
                                } else {
                                    break;
                                }
                            }
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

        return Token{ .json = token };
    }

    /// Scan a keyword (true, false, null)
    fn scanKeyword(self: *Lexer) Token {
        const start_ch = self.buffer.peek() orelse return self.makeErrorToken();

        const kind: TokenKind = switch (start_ch) {
            't' => blk: {
                if (self.matchKeyword("true")) break :blk .boolean_true;
                break :blk .err;
            },
            'f' => blk: {
                if (self.matchKeyword("false")) break :blk .boolean_false;
                break :blk .err;
            },
            'n' => blk: {
                if (self.matchKeyword("null")) break :blk .null_value;
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

        return Token{ .json = token };
    }

    /// Scan a comment (non-standard but common)
    fn scanComment(self: *Lexer) Token {
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

                    if (prev == '*' and ch == '/') break;
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

        return Token{ .json = token };
    }

    fn skipWhitespace(self: *Lexer) void {
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

    fn makeSimpleToken(self: *Lexer, kind: TokenKind, increase_depth: bool) Token {
        _ = self.buffer.pop();
        const end_pos = self.position + 1;

        // Update depth and context
        if (increase_depth) {
            self.depth = @min(self.depth + 1, 255);
            if (self.depth < 32) {
                if (kind == .object_start) {
                    self.context_stack |= (@as(u32, 1) << @as(u5, @intCast(self.depth - 1)));
                } else {
                    self.context_stack &= ~(@as(u32, 1) << @as(u5, @intCast(self.depth - 1)));
                }
            }
        } else if (kind == .object_end or kind == .array_end) {
            if (self.depth > 0) {
                if (self.depth <= 32) {
                    self.context_stack &= ~(@as(u32, 1) << @as(u5, @intCast(self.depth - 1)));
                }
                self.depth -= 1;
            }
        }

        // Update context for property name detection
        switch (kind) {
            .object_start => self.expecting_property_key = true,
            .comma => {
                const in_object = if (self.depth > 0 and self.depth <= 32)
                    (self.context_stack & (@as(u32, 1) << @as(u5, @intCast(self.depth - 1)))) != 0
                else
                    false;
                self.expecting_property_key = in_object;
            },
            .colon => self.expecting_property_key = false,
            .array_start => self.expecting_property_key = false,
            else => {},
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
        return Token{ .json = token };
    }

    fn matchKeyword(self: *Lexer, keyword: []const u8) bool {
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

    fn makeErrorToken(self: *Lexer) Token {
        const token = JsonToken{
            .span = packSpan(Span{ .start = self.token_start, .end = self.position }),
            .kind = .err,
            .depth = self.depth,
            .flags = .{},
            .data = 0,
        };
        self.state = .err;
        return Token{ .json = token };
    }

    fn makeContinuationToken(self: *Lexer) Token {
        const token = JsonToken{
            .span = packSpan(Span{ .start = self.position, .end = self.position }),
            .kind = .continuation,
            .depth = self.depth,
            .flags = .{ .continuation = true },
            .data = 0,
        };
        return Token{ .json = token };
    }
};

// Tests
test "Lexer basic tokenization" {
    const testing = std.testing;

    var lexer = Lexer.init(
        \\{"name": "test", "value": 42}
    );

    // Test token sequence
    const token1 = lexer.next() orelse return error.UnexpectedNull;
    try testing.expectEqual(TokenKind.object_start, token1.json.kind);

    const token2 = lexer.next() orelse return error.UnexpectedNull;
    try testing.expectEqual(TokenKind.property_name, token2.json.kind);

    const token3 = lexer.next() orelse return error.UnexpectedNull;
    try testing.expectEqual(TokenKind.colon, token3.json.kind);

    const token4 = lexer.next() orelse return error.UnexpectedNull;
    try testing.expectEqual(TokenKind.string_value, token4.json.kind);

    const token5 = lexer.next() orelse return error.UnexpectedNull;
    try testing.expectEqual(TokenKind.comma, token5.json.kind);

    const token6 = lexer.next() orelse return error.UnexpectedNull;
    try testing.expectEqual(TokenKind.property_name, token6.json.kind);

    const token7 = lexer.next() orelse return error.UnexpectedNull;
    try testing.expectEqual(TokenKind.colon, token7.json.kind);

    const token8 = lexer.next() orelse return error.UnexpectedNull;
    try testing.expectEqual(TokenKind.number_value, token8.json.kind);

    const token9 = lexer.next() orelse return error.UnexpectedNull;
    try testing.expectEqual(TokenKind.object_end, token9.json.kind);

    const token10 = lexer.next() orelse return error.UnexpectedNull;
    try testing.expectEqual(TokenKind.eof, token10.json.kind);

    try testing.expectEqual(@as(?Token, null), lexer.next());
}
