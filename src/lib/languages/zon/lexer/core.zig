/// ZON Stream Lexer - Zero-allocation streaming tokenization for Zig Object Notation
/// Implements direct iterator pattern without vtable overhead
/// Performance target: >10MB/sec throughput with 1-2 cycle dispatch
///
/// ARCHITECTURE: Direct dispatch pattern for optimal performance
/// - Primary API: next() method (1-2 cycle dispatch, no vtables)
/// - Stream integration: toDirectStream() when pipeline compatibility needed
/// - Zero allocations: Uses ring buffer for efficient token streaming
const std = @import("std");
const RingBuffer = @import("../../../stream/mod.zig").RingBuffer;
const Token = @import("../../../token/mod.zig").Token;
const ZonToken = @import("../token/types.zig").Token;
const TokenKind = @import("../token/types.zig").TokenKind;
const TokenFlags = @import("../token/types.zig").TokenFlags;
const packSpan = @import("../../../span/mod.zig").packSpan;
const Span = @import("../../../span/mod.zig").Span;

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
pub const Lexer = struct {
    // Ring buffer for lookahead (64KB for large test cases)
    buffer: RingBuffer(u8, 65536),

    // Source text reference for keyword matching
    source: []const u8,

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

    // Container stack to track opening types (increased size for deep nesting support)
    container_stack: [32]TokenKind,

    // Flags for current token
    current_flags: TokenFlags,

    // Error state
    error_msg: ?[]const u8,

    // Peeked token for lookahead
    peeked_token: ?Token,

    /// Initialize lexer with input buffer
    /// This is the primary interface - simple iterator pattern
    pub fn init(input: []const u8) Lexer {
        var lexer = Lexer.initEmpty();
        lexer.source = input;

        // Fill ring buffer with input
        for (input) |byte| {
            _ = lexer.buffer.push(byte) catch break;
        }

        return lexer;
    }

    /// Initialize empty lexer (for streaming from reader)
    pub fn initEmpty() Lexer {
        return .{
            .buffer = RingBuffer(u8, 65536).init(),
            .source = "",
            .state = .start,
            .position = 0,
            .line = 1,
            .column = 1,
            .token_start = 0,
            .token_line = 1,
            .token_column = 1,
            .depth = 0,
            .container_stack = [_]TokenKind{.eof} ** 32,
            .current_flags = .{},
            .error_msg = null,
            .peeked_token = null,
        };
    }

    /// Get next token - Direct iterator interface (no vtable!)
    /// This is 1-2 cycle dispatch vs 3-5 for vtable
    pub fn next(self: *Lexer) ?Token {
        // If we have a peeked token, return it
        if (self.peeked_token) |token| {
            self.peeked_token = null;
            return token;
        }

        return self.nextInternal();
    }

    /// Peek at the next token without consuming it
    pub fn peek(self: *Lexer) ?Token {
        // If we already have a peeked token, return it
        if (self.peeked_token) |token| {
            return token;
        }

        // Get the next token and store it for later
        const token = self.nextInternal();
        self.peeked_token = token;
        return token;
    }

    fn nextInternal(self: *Lexer) ?Token {

        // Return null if already done (after EOF)
        if (self.state == .done) {
            return null;
        }

        // Skip whitespace and comments
        self.skipWhitespaceAndComments();

        // Check for end of input - ANY state can reach EOF, not just .start
        if (self.buffer.isEmpty()) {
            self.state = .done; // Mark as done after EOF
            return Token{ .zon = ZonToken{
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
                // Could be .{} struct, .field, or .@"quoted field"
                _ = self.buffer.pop();
                self.position += 1;
                self.column += 1;

                if (self.buffer.peek()) |next_ch| {
                    if (next_ch == '{') {
                        _ = self.buffer.pop();
                        self.position += 1;
                        self.column += 1;
                        self.depth = @min(self.depth + 1, 255);
                        // Track that this depth opened with struct_start
                        if (self.depth > 0 and self.depth <= 32) {
                            self.container_stack[self.depth - 1] = .struct_start;
                        }
                        return Token{ .zon = ZonToken{
                            .span = packSpan(Span{ .start = self.token_start, .end = self.position }),
                            .kind = .struct_start,
                            .depth = self.depth,
                            .flags = .{},
                            .data = 0,
                        } };
                    } else if (next_ch == '@') {
                        // Handle .@"quoted field" syntax
                        return self.scanQuotedFieldAccess();
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

    /// Skip whitespace and comments
    fn skipWhitespaceAndComments(self: *Lexer) void {
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
                    // Need at least 2 chars to check comment patterns
                    if (self.buffer.len() < 2) return;

                    // Use peekAt to look ahead without consuming
                    const next_ch = self.buffer.peekAt(1) orelse return;

                    if (next_ch == '/') {
                        // Single-line comment: //
                        _ = self.buffer.pop(); // Consume first '/'
                        _ = self.buffer.pop(); // Consume second '/'
                        self.position += 2;
                        self.column += 2;

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
                    } else if (next_ch == '*') {
                        // Block comment: /* */
                        _ = self.buffer.pop(); // Consume '/'
                        _ = self.buffer.pop(); // Consume '*'
                        self.position += 2;
                        self.column += 2;

                        // Look for closing */
                        var found_end = false;
                        while (self.buffer.peek()) |comment_ch| {
                            _ = self.buffer.pop();
                            self.position += 1;

                            if (comment_ch == '*') {
                                // Check for closing /
                                if (self.buffer.peek()) |closing_ch| {
                                    if (closing_ch == '/') {
                                        _ = self.buffer.pop(); // Consume '/'
                                        self.position += 1;
                                        self.column += 1;
                                        found_end = true;
                                        break;
                                    }
                                }
                                self.column += 1;
                            } else if (comment_ch == '\n') {
                                self.line += 1;
                                self.column = 1;
                            } else {
                                self.column += 1;
                            }
                        }

                        // If we didn't find the end, that's an unterminated comment
                        // but we'll let the parser handle the error gracefully
                    } else {
                        // Not a comment (just a standalone '/'), return without consuming
                        return;
                    }
                },
                else => return,
            }
        }
    }

    /// Create a simple single-character token
    fn makeSimpleToken(self: *Lexer, kind: TokenKind, increase_depth: bool) Token {
        _ = self.buffer.pop();
        const end_pos = self.position + 1;
        var final_kind = kind;

        if (increase_depth) {
            self.depth = @min(self.depth + 1, 255);
            // Track opening container type
            if (self.depth > 0 and self.depth <= 32) {
                self.container_stack[self.depth - 1] = kind;
            }
        } else if (kind == .object_end or kind == .array_end or kind == .paren_close) {
            // Check if this should be struct_end instead of object_end
            if (kind == .object_end and self.depth > 0 and self.depth <= 32) {
                const opening_kind = self.container_stack[self.depth - 1];
                if (opening_kind == .struct_start) {
                    final_kind = .struct_end;
                }
            }
            self.depth = if (self.depth > 0) self.depth - 1 else 0;
        }

        const token = ZonToken{
            .span = packSpan(Span{ .start = self.token_start, .end = end_pos }),
            .kind = final_kind,
            .depth = self.depth,
            .flags = .{},
            .data = 0,
        };

        self.position = end_pos;
        self.column += 1;

        return Token{ .zon = token };
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
                    const token = ZonToken{
                        .span = packSpan(Span{ .start = self.token_start, .end = self.position }),
                        .kind = .string_value,
                        .depth = self.depth,
                        .flags = .{ .has_escapes = has_escapes },
                        .data = 0,
                    };
                    return Token{ .zon = token };
                },
                '\\' => {
                    has_escapes = true;

                    // Validate escape sequence
                    if (self.buffer.pop()) |escaped_char| {
                        self.position += 1;
                        self.column += 1;

                        // Handle unicode escapes \u{...}
                        if (escaped_char == 'u') {
                            if (!self.validateUnicodeEscape()) {
                                self.error_msg = "Invalid unicode escape sequence";
                                return self.makeErrorToken();
                            }
                        }
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

    /// Scan a multiline string (each line starts with \\)
    fn scanMultilineString(self: *Lexer) Token {
        // Consume the first backslash that triggered this scan
        _ = self.buffer.pop();
        self.position += 1;
        self.column += 1;

        // Check for second backslash to confirm this is a multiline string line
        if (self.buffer.peek()) |ch| {
            if (ch == '\\') {
                _ = self.buffer.pop();
                self.position += 1;
                self.column += 1;

                // Scan this line's content until newline
                while (self.buffer.peek()) |scan_ch| {
                    if (scan_ch == '\n') {
                        _ = self.buffer.pop();
                        self.position += 1;
                        self.line += 1;
                        self.column = 1;
                        break;
                    } else {
                        _ = self.buffer.pop();
                        self.position += 1;
                        self.column += 1;
                    }
                }

                // Now scan additional lines that start with \\
                while (true) {
                    // Skip whitespace at start of line
                    while (self.buffer.peek()) |space_ch| {
                        if (space_ch == ' ' or space_ch == '\t') {
                            _ = self.buffer.pop();
                            self.position += 1;
                            self.column += 1;
                        } else {
                            break;
                        }
                    }

                    // Check if this line starts with \\
                    if (self.buffer.len() >= 2 and
                        self.buffer.peekAt(0) == '\\' and
                        self.buffer.peekAt(1) == '\\')
                    {
                        // This line is part of the multiline string
                        _ = self.buffer.pop(); // First \
                        _ = self.buffer.pop(); // Second \
                        self.position += 2;
                        self.column += 2;

                        // Scan rest of line
                        while (self.buffer.peek()) |line_ch| {
                            if (line_ch == '\n') {
                                _ = self.buffer.pop();
                                self.position += 1;
                                self.line += 1;
                                self.column = 1;
                                break;
                            } else {
                                _ = self.buffer.pop();
                                self.position += 1;
                                self.column += 1;
                            }
                        }
                    } else {
                        // Line doesn't start with \\, end of multiline string
                        break;
                    }

                    // If we're at end of input, break
                    if (self.buffer.peek() == null) break;
                }

                const token = ZonToken{
                    .span = packSpan(Span{ .start = self.token_start, .end = self.position }),
                    .kind = .string_value,
                    .depth = self.depth,
                    .flags = .{ .multiline_string = true },
                    .data = 0,
                };

                return Token{ .zon = token };
            }
        }

        // Not a multiline string, treat as error
        self.error_msg = "Expected second '\\' for multiline string";
        return self.makeErrorToken();
    }

    /// Scan a number
    fn scanNumber(self: *Lexer) Token {
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

        // Scan number body - ensure we consume at least one digit
        var consumed_digits = false;
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
            if ((ch >= '0' and ch <= '9') or (is_hex and ((ch >= 'a' and ch <= 'f') or (ch >= 'A' and ch <= 'F')))) {
                consumed_digits = true;
            }

            _ = self.buffer.pop();
            self.position += 1;
            self.column += 1;
        }

        // Must have consumed at least one digit
        if (!consumed_digits) {
            self.error_msg = "Expected digits in number";
            return self.makeErrorToken();
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

        return Token{ .zon = token };
    }

    /// Scan an identifier or keyword
    fn scanIdentifier(self: *Lexer) Token {
        // Ensure we consume at least one character (the one that triggered this scan)
        var consumed_any = false;
        while (self.buffer.peek()) |ch| {
            if ((ch >= 'a' and ch <= 'z') or
                (ch >= 'A' and ch <= 'Z') or
                (ch >= '0' and ch <= '9') or
                ch == '_')
            {
                _ = self.buffer.pop();
                self.position += 1;
                self.column += 1;
                consumed_any = true;
            } else {
                break;
            }
        }

        // If we didn't consume any characters, something is wrong
        if (!consumed_any) {
            self.error_msg = "Expected identifier character";
            return self.makeErrorToken();
        }

        // Check for keywords
        const len = self.position - self.token_start;
        const kind: TokenKind = if (len == 4 and self.matchesKeywordAt("true", self.token_start))
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

        return Token{ .zon = token };
    }

    /// Scan a builtin (@import, @field, etc.)
    fn scanBuiltin(self: *Lexer) Token {
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

        return Token{ .zon = token };
    }

    /// Scan a field access (.field_name)
    fn scanFieldAccess(self: *Lexer) Token {
        // Ensure we consume at least one character for field name
        var consumed_any = false;
        while (self.buffer.peek()) |ch| {
            if ((ch >= 'a' and ch <= 'z') or
                (ch >= 'A' and ch <= 'Z') or
                (ch >= '0' and ch <= '9') or
                ch == '_')
            {
                _ = self.buffer.pop();
                self.position += 1;
                self.column += 1;
                consumed_any = true;
            } else {
                break;
            }
        }

        // If no identifier follows the dot, return error
        if (!consumed_any) {
            self.error_msg = "Expected field name after '.'";
            return self.makeErrorToken();
        }

        const token = ZonToken{
            .span = packSpan(Span{ .start = self.token_start, .end = self.position }),
            .kind = .field_name,
            .depth = self.depth,
            .flags = .{},
            .data = 0,
        };

        return Token{ .zon = token };
    }

    /// Scan a quoted field access (.@"field name")
    fn scanQuotedFieldAccess(self: *Lexer) Token {
        // Consume the @ character
        if (self.buffer.peek()) |ch| {
            if (ch == '@') {
                _ = self.buffer.pop();
                self.position += 1;
                self.column += 1;
            }
        }

        // Expect a quoted string after @
        if (self.buffer.peek()) |ch| {
            if (ch == '"') {
                // Consume opening quote
                _ = self.buffer.pop();
                self.position += 1;
                self.column += 1;

                // Scan until closing quote
                var has_escapes = false;
                while (self.buffer.peek()) |string_ch| {
                    _ = self.buffer.pop();
                    self.position += 1;
                    self.column += 1;

                    switch (string_ch) {
                        '"' => {
                            // Found closing quote, create field name token
                            const token = ZonToken{
                                .span = packSpan(Span{ .start = self.token_start, .end = self.position }),
                                .kind = .field_name,
                                .depth = self.depth,
                                .flags = .{
                                    .has_escapes = has_escapes,
                                    .is_quoted_field = true,
                                },
                                .data = 0,
                            };

                            return Token{ .zon = token };
                        },
                        '\\' => {
                            has_escapes = true;

                            // Validate escape sequence
                            if (self.buffer.pop()) |escaped_char| {
                                self.position += 1;
                                self.column += 1;

                                // Handle unicode escapes \u{...}
                                if (escaped_char == 'u') {
                                    if (!self.validateUnicodeEscape()) {
                                        self.error_msg = "Invalid unicode escape sequence";
                                        return self.makeErrorToken();
                                    }
                                }
                            }
                        },
                        '\n' => {
                            self.line += 1;
                            self.column = 1;
                        },
                        else => {},
                    }
                }

                // Unterminated quoted string
                self.error_msg = "Unterminated quoted field name";
                return self.makeErrorToken();
            }
        }

        // Expected quote after @
        self.error_msg = "Expected '\"' after '.@'";
        return self.makeErrorToken();
    }

    /// Check if consumed text matches keyword
    fn matchesKeywordAt(self: *Lexer, keyword: []const u8, start: u32) bool {
        const len = self.position - start;
        if (len != keyword.len) return false;
        if (start + len > self.source.len) return false;

        const consumed_text = self.source[start .. start + len];
        return std.mem.eql(u8, consumed_text, keyword);
    }

    /// Create an error token
    fn makeErrorToken(self: *Lexer) Token {
        const token = ZonToken{
            .span = packSpan(Span{ .start = self.token_start, .end = self.position }),
            .kind = .err,
            .depth = self.depth,
            .flags = .{},
            .data = 0,
        };
        self.state = .err;
        return Token{ .zon = token };
    }

    /// Validate unicode escape sequence \u{...} (Zig-style)
    /// Returns false if the escape sequence is malformed
    fn validateUnicodeEscape(self: *Lexer) bool {
        // Expect opening brace
        if (self.buffer.pop()) |ch| {
            if (ch != '{') return false;
            self.position += 1;
            self.column += 1;
        } else {
            return false;
        }

        var hex_digits: u32 = 0;
        var codepoint: u32 = 0;

        // Parse hex digits
        while (self.buffer.peek()) |ch| {
            switch (ch) {
                '0'...'9' => {
                    codepoint = codepoint * 16 + (ch - '0');
                    hex_digits += 1;
                },
                'a'...'f' => {
                    codepoint = codepoint * 16 + (ch - 'a' + 10);
                    hex_digits += 1;
                },
                'A'...'F' => {
                    codepoint = codepoint * 16 + (ch - 'A' + 10);
                    hex_digits += 1;
                },
                '}' => {
                    _ = self.buffer.pop(); // consume }
                    self.position += 1;
                    self.column += 1;
                    break;
                },
                else => {
                    return false; // Invalid hex digit
                },
            }

            // Consume the hex digit
            _ = self.buffer.pop();
            self.position += 1;
            self.column += 1;

            // Prevent overflow and overly long sequences (max 6 hex digits for 0x10FFFF)
            if (hex_digits > 6) return false;
        }

        // Must have at least 1 hex digit and closing brace
        if (hex_digits == 0) return false;

        // Validate codepoint range (0x0 to 0x10FFFF, excluding surrogates 0xD800-0xDFFF)
        if (codepoint > 0x10FFFF) return false;
        if (codepoint >= 0xD800 and codepoint <= 0xDFFF) return false;

        return true;
    }
};

// Tests
test "Lexer basic tokenization" {
    const testing = std.testing;

    var lexer = Lexer.init(
        \\.{ .name = "test", .value = 42 }
    );

    // .{
    const token1 = lexer.next() orelse return error.UnexpectedNull;
    try testing.expectEqual(TokenKind.struct_start, token1.zon.kind);

    // .name
    const token2 = lexer.next() orelse return error.UnexpectedNull;
    try testing.expectEqual(TokenKind.field_name, token2.zon.kind);

    // =
    const token3 = lexer.next() orelse return error.UnexpectedNull;
    try testing.expectEqual(TokenKind.equals, token3.zon.kind);

    // "test"
    const token4 = lexer.next() orelse return error.UnexpectedNull;
    try testing.expectEqual(TokenKind.string_value, token4.zon.kind);
}

test "Lexer zero allocations" {
    const testing = std.testing;

    const input = ".{ .a = 1, .b = 2 }";
    var lexer = Lexer.init(input);

    // Stack-allocated lexer - verify streaming architecture size expectations
    const lexer_size = @sizeOf(Lexer);
    try testing.expect(lexer_size < 70000); // ~64KB ring buffer + metadata
    try testing.expect(lexer_size > 65000); // Should be dominated by ring buffer

    // Tokenize without allocating
    while (lexer.next()) |token| {
        // Process tokens - no allocations
        if (token.zon.kind == .eof) break;
    }
}

test "Lexer multiline strings" {
    const testing = std.testing;

    var lexer = Lexer.init(
        \\\\This is a
        \\multiline string\\
    );

    const token = lexer.next() orelse return error.UnexpectedNull;
    try testing.expectEqual(TokenKind.string_value, token.zon.kind);
    try testing.expect(token.zon.flags.multiline_string);
}

test "Lexer EOF handling" {
    const testing = std.testing;

    var lexer = Lexer.init("42");

    // Get number token
    const token1 = lexer.next() orelse return error.UnexpectedNull;
    try testing.expectEqual(TokenKind.number_value, token1.zon.kind);

    // Get EOF token
    const token2 = lexer.next() orelse return error.UnexpectedNull;
    try testing.expectEqual(TokenKind.eof, token2.zon.kind);

    // After EOF, should return null
    const token3 = lexer.next();
    try testing.expectEqual(@as(?Token, null), token3);

    // Should continue returning null
    const token4 = lexer.next();
    try testing.expectEqual(@as(?Token, null), token4);
}
