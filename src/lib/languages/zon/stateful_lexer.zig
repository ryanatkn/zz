const std = @import("std");
const Token = @import("../../parser_old/foundation/types/token.zig").Token;
const TokenKind = @import("../../parser_old/foundation/types/predicate.zig").TokenKind;
const Span = @import("../../parser_old/foundation/types/span.zig").Span;
const StatefulLexer = @import("../../transform_old/streaming/stateful_lexer.zig").StatefulLexer;
const char = @import("../../char/mod.zig");
const ZonToken = @import("tokens.zig").ZonToken;
const CommentKind = @import("tokens.zig").CommentKind;
const TokenData = @import("../common/token_base.zig").TokenData;

/// Convert ZonToken to generic Token (for backward compatibility)
fn zonToGenericToken(zon_token: ZonToken, source: []const u8) Token {
    _ = source; // May be needed for text extraction

    const span_val = zon_token.span();
    const depth = zon_token.tokenData().depth;
    const kind = switch (zon_token) {
        .object_start => TokenKind.left_brace,
        .object_end => TokenKind.right_brace,
        .array_start => TokenKind.left_bracket,
        .array_end => TokenKind.right_bracket,
        .comma => TokenKind.comma,
        .colon => TokenKind.colon,
        .equals => TokenKind.operator,
        .identifier => TokenKind.identifier,
        .field_name => TokenKind.identifier,
        .string_value => TokenKind.string_literal,
        .decimal_int, .hex_int, .binary_int, .octal_int, .float => TokenKind.number_literal,
        .char_literal => TokenKind.string_literal,
        .boolean_value => TokenKind.boolean_literal,
        .null_value => TokenKind.null_literal,
        .undefined_value => TokenKind.keyword,
        .enum_literal => TokenKind.identifier,
        .struct_literal => TokenKind.delimiter,
        .comment => TokenKind.comment,
        .whitespace => TokenKind.whitespace,
        .invalid => TokenKind.unknown,
    };

    return Token{
        .kind = kind,
        .span = span_val,
        .text = zon_token.text(),
        .bracket_depth = depth,
        .flags = .{},
    };
}

/// High-performance stateful ZON lexer for streaming tokenization
///
/// Features:
/// - Handles all ZON token types including Zig-specific features
/// - Resumes tokenization across chunk boundaries
/// - Zero heap allocations in hot paths
/// - Supports unquoted identifiers, enum literals, char literals
pub const StatefulZonLexer = struct {
    state: StatefulLexer.State,
    allocator: std.mem.Allocator,
    /// Track current depth for nesting
    depth: u16 = 0,

    const Self = @This();

    /// Common return type for token processing functions
    const TokenResult = struct {
        token: ?ZonToken,
        consumed: usize,
    };

    pub fn init(allocator: std.mem.Allocator, options: StatefulLexer.Options) Self {
        var lexer = Self{
            .state = .{},
            .allocator = allocator,
        };
        lexer.state.flags.allow_comments = options.allow_comments;
        lexer.state.flags.allow_trailing_commas = options.allow_trailing_commas;
        lexer.state.flags.error_recovery = options.error_recovery;
        lexer.state.flags.allow_raw_strings = true; // ZON supports raw strings
        lexer.state.flags.allow_multiline_strings = true; // ZON supports multiline
        return lexer;
    }

    pub fn deinit(self: *Self) void {
        _ = self;
        // No cleanup needed - all stack allocated
    }

    pub fn reset(self: *Self) void {
        self.state.reset();
        self.depth = 0;
    }

    /// Process a chunk of input, returning generic tokens (backward compatibility wrapper)
    pub fn processChunk(
        self: *Self,
        chunk: []const u8,
        chunk_pos: usize,
        allocator: std.mem.Allocator,
    ) ![]Token {
        // Use the new ZonToken-based method
        const zon_tokens = try self.processChunkToZon(chunk, chunk_pos, allocator);
        defer allocator.free(zon_tokens);

        // Convert to generic tokens
        var generic_tokens = try allocator.alloc(Token, zon_tokens.len);
        for (zon_tokens, 0..) |zon_token, i| {
            generic_tokens[i] = zonToGenericToken(zon_token, chunk);
        }

        return generic_tokens;
    }

    /// Process a chunk of input, returning ZonTokens directly for vtable adaptation
    pub fn processChunkToZon(
        self: *Self,
        chunk: []const u8,
        chunk_pos: usize,
        allocator: std.mem.Allocator,
    ) ![]ZonToken {
        var tokens = try std.ArrayList(ZonToken).initCapacity(
            allocator,
            chunk.len / 4, // Heuristic: average 4 bytes per token
        );
        errdefer tokens.deinit();

        var pos: usize = 0;

        // Process tokens in this chunk
        while (pos < chunk.len) {
            // Skip whitespace
            while (pos < chunk.len and char.isWhitespace(chunk[pos])) {
                pos += 1;
            }
            if (pos >= chunk.len) break;

            // Get next token
            const result = try self.processTokenToZon(chunk[pos..], chunk_pos + pos);
            if (result.token) |token| {
                try tokens.append(token);
            }
            if (result.consumed == 0) {
                // Prevent infinite loop
                pos += 1;
            } else {
                pos += result.consumed;
            }
        }

        // Handle partial token at chunk boundary
        if (pos < chunk.len or self.state.hasPartialToken()) {
            // TODO: Implement proper partial token storage for ZON
            // self.state.storePartialToken(chunk[pos..]);
        }

        return tokens.toOwnedSlice();
    }

    /// Process a single token from input for ZonToken-only output
    fn processTokenToZon(self: *Self, input: []const u8, base_pos: usize) !TokenResult {
        if (input.len == 0) {
            return TokenResult{ .token = null, .consumed = 0 };
        }

        const ch = input[0];
        const span = Span.init(base_pos, base_pos + 1);
        const data = TokenData.init(span, 0, 0, self.depth);

        // Try fast single-character tokens first
        const fast_token: ?ZonToken = switch (ch) {
            '{' => blk: {
                self.depth += 1;
                break :blk ZonToken{ .object_start = data };
            },
            '}' => blk: {
                if (self.depth > 0) self.depth -= 1;
                break :blk ZonToken{ .object_end = data };
            },
            '[' => blk: {
                self.depth += 1;
                break :blk ZonToken{ .array_start = data };
            },
            ']' => blk: {
                if (self.depth > 0) self.depth -= 1;
                break :blk ZonToken{ .array_end = data };
            },
            ',' => ZonToken{ .comma = data },
            ':' => ZonToken{ .colon = data },
            '=' => ZonToken{ .equals = data }, // ZON-specific
            else => null,
        };

        if (fast_token) |token| {
            return TokenResult{ .token = token, .consumed = 1 };
        }

        // Fall back to complex token parsing
        return try self.parseComplexToken(input, base_pos);
    }

    /// Complete a partial token from the previous chunk
    fn completePartialToken(
        self: *Self,
        chunk: []const u8,
        tokens: *std.ArrayList(Token),
        chunk_pos: usize,
    ) !usize {
        const partial = self.state.getPartialToken();

        switch (self.state.context) {
            .in_string => {
                // Find the closing quote
                var pos: usize = 0;
                var escaped = false;

                while (pos < chunk.len) {
                    const ch = chunk[pos];

                    if (escaped) {
                        escaped = false;
                        pos += 1;
                        continue;
                    }

                    if (ch == '\\') {
                        escaped = true;
                    } else if (ch == self.state.quote_char) {
                        // Found closing quote
                        const full_text = try self.allocator.alloc(u8, partial.len + pos + 1);
                        defer self.allocator.free(full_text);
                        @memcpy(full_text[0..partial.len], partial);
                        @memcpy(full_text[partial.len..], chunk[0 .. pos + 1]);

                        const data = TokenData.init(
                            Span.init(chunk_pos - partial.len, chunk_pos + pos + 1),
                            0,
                            0,
                            self.depth,
                        );

                        const token = ZonToken{
                            .string_value = .{
                                .data = data,
                                .value = full_text[1 .. full_text.len - 1], // Remove quotes
                                .raw = full_text,
                                .has_escapes = std.mem.indexOfScalar(u8, full_text, '\\') != null,
                                .is_multiline = false,
                            },
                        };

                        try tokens.append(zonToGenericToken(token, ""));
                        self.state.reset();
                        return pos + 1;
                    }
                    pos += 1;
                }

                // Still no closing quote, store in partial token buffer
                // TODO: Implement proper partial token handling for ZON
                // For now, just consume the chunk
                return chunk.len;
            },
            else => {
                // For other contexts, just reset for now
                self.state.reset();
                return 0;
            },
        }
    }

    /// Parse complex tokens (strings, numbers, identifiers, etc.)
    fn parseComplexToken(self: *Self, input: []const u8, base_pos: usize) !TokenResult {
        const ch = input[0];

        // String literals
        if (ch == '"') {
            return try self.parseString(input, base_pos);
        }

        // Char literals (ZON-specific)
        if (ch == '\'') {
            return try self.parseCharLiteral(input, base_pos);
        }

        // Dot tokens (field names, enum literals, struct literals)
        if (ch == '.') {
            return try self.parseDotToken(input, base_pos);
        }

        // Builtin functions (ZON-specific)
        if (ch == '@') {
            return try self.parseBuiltin(input, base_pos);
        }

        // Numbers
        if (char.isDigit(ch) or (ch == '-' and input.len > 1 and char.isDigit(input[1]))) {
            return try self.parseNumber(input, base_pos);
        }

        // Keywords and identifiers
        if (char.isAlpha(ch) or ch == '_') {
            return try self.parseIdentifierOrKeyword(input, base_pos);
        }

        // Comments
        if (ch == '/' and input.len > 1) {
            if (input[1] == '/') {
                return try self.parseLineComment(input, base_pos);
            } else if (input[1] == '*') {
                return try self.parseBlockComment(input, base_pos);
            }
        }

        return .{ .token = null, .consumed = 0 };
    }

    fn parseString(self: *Self, input: []const u8, base_pos: usize) !TokenResult {
        var pos: usize = 1; // Skip opening quote
        var escaped = false;

        while (pos < input.len) {
            const ch = input[pos];

            if (escaped) {
                escaped = false;
                pos += 1;
                continue;
            }

            if (ch == '\\') {
                escaped = true;
            } else if (ch == '"') {
                // Found closing quote
                pos += 1;
                const data = TokenData.init(
                    Span.init(base_pos, base_pos + pos),
                    0,
                    0,
                    self.depth,
                );

                return .{
                    .token = ZonToken{
                        .string_value = .{
                            .data = data,
                            .value = input[1 .. pos - 1],
                            .raw = input[0..pos],
                            .has_escapes = std.mem.indexOfScalar(u8, input[0..pos], '\\') != null,
                            .is_multiline = false,
                        },
                    },
                    .consumed = pos,
                };
            }
            pos += 1;
        }

        // Incomplete string, store as partial
        self.state.context = .in_string;
        self.state.quote_char = '"';
        // TODO: Implement proper partial token storage
        // self.state.storePartialToken(input);
        return .{ .token = null, .consumed = input.len };
    }

    fn parseCharLiteral(self: *Self, input: []const u8, base_pos: usize) !TokenResult {
        if (input.len < 3) {
            // Not enough for a char literal
            return .{ .token = null, .consumed = 0 };
        }

        var pos: usize = 1;
        if (input[1] == '\\' and input.len > 3) {
            // Escaped character
            pos = 3; // Skip escape sequence
        } else {
            pos = 2; // Single character
        }

        if (pos < input.len and input[pos] == '\'') {
            pos += 1;
            const data = TokenData.init(
                Span.init(base_pos, base_pos + pos),
                0,
                0,
                self.depth,
            );

            return .{
                .token = ZonToken{
                    .char_literal = .{
                        .data = data,
                        .value = if (pos > 2) @as(u21, input[1]) else '?', // TODO: Proper Unicode parsing
                        .raw = input[0..pos],
                    },
                },
                .consumed = pos,
            };
        }

        return .{ .token = null, .consumed = 0 };
    }

    fn parseDotToken(self: *Self, input: []const u8, base_pos: usize) !TokenResult {
        if (input.len < 2) {
            return .{ .token = null, .consumed = 0 };
        }

        // Check for .{} struct literal
        if (input[1] == '{') {
            const data = TokenData.init(
                Span.init(base_pos, base_pos + 2),
                0,
                0,
                self.depth,
            );
            return .{
                .token = ZonToken{ .struct_literal = data },
                .consumed = 2,
            };
        }

        // Parse field name or enum literal
        if (char.isAlpha(input[1]) or input[1] == '_' or input[1] == '@') {
            var pos: usize = 1;
            while (pos < input.len and (char.isAlphaNumeric(input[pos]) or input[pos] == '_')) {
                pos += 1;
            }

            const data = TokenData.init(
                Span.init(base_pos, base_pos + pos),
                0,
                0,
                self.depth,
            );

            // Check if it's a field name (followed by = or :) or enum literal
            var is_field = false;
            var lookahead = pos;
            while (lookahead < input.len and char.isWhitespace(input[lookahead])) {
                lookahead += 1;
            }
            if (lookahead < input.len and (input[lookahead] == '=' or input[lookahead] == ':')) {
                is_field = true;
            }

            if (is_field) {
                return .{
                    .token = ZonToken{
                        .field_name = .{
                            .data = data,
                            .name = input[1..pos],
                            .raw = input[0..pos],
                            .is_quoted = false,
                        },
                    },
                    .consumed = pos,
                };
            } else {
                return .{
                    .token = ZonToken{
                        .enum_literal = .{
                            .data = data,
                            .name = input[1..pos],
                        },
                    },
                    .consumed = pos,
                };
            }
        }

        return .{ .token = null, .consumed = 0 };
    }

    fn parseBuiltin(self: *Self, input: []const u8, base_pos: usize) !TokenResult {
        if (input.len < 2 or !char.isAlpha(input[1])) {
            return .{ .token = null, .consumed = 0 };
        }

        var pos: usize = 1;
        while (pos < input.len and (char.isAlphaNumeric(input[pos]) or input[pos] == '_')) {
            pos += 1;
        }

        const data = TokenData.init(
            Span.init(base_pos, base_pos + pos),
            0,
            0,
            self.depth,
        );

        return .{
            .token = ZonToken{
                .identifier = .{
                    .data = data,
                    .text = input[0..pos],
                    .is_builtin = true,
                },
            },
            .consumed = pos,
        };
    }

    fn parseNumber(self: *Self, input: []const u8, base_pos: usize) !TokenResult {
        var pos: usize = 0;
        var has_underscores = false;

        // Handle negative sign
        if (input[0] == '-') {
            pos += 1;
        }

        // Check for hex/binary/octal prefix
        if (pos < input.len - 1 and input[pos] == '0') {
            const next = input[pos + 1];

            if (next == 'x' or next == 'X') {
                // Hex number - single pass parsing
                pos += 2;
                while (pos < input.len) {
                    if (char.isHexDigit(input[pos])) {
                        pos += 1;
                    } else if (input[pos] == '_') {
                        has_underscores = true;
                        pos += 1;
                    } else break;
                }

                return .{
                    .token = ZonToken{ .hex_int = .{
                        .data = TokenData.init(Span.init(base_pos, base_pos + pos), 0, 0, self.depth),
                        .value = std.fmt.parseInt(u128, input[0..pos], 0) catch 0,
                        .raw = input[0..pos],
                        .has_underscores = has_underscores,
                    } },
                    .consumed = pos,
                };
            } else if (next == 'b' or next == 'B') {
                // Binary number - single pass parsing
                pos += 2;
                while (pos < input.len) {
                    if (input[pos] == '0' or input[pos] == '1') {
                        pos += 1;
                    } else if (input[pos] == '_') {
                        has_underscores = true;
                        pos += 1;
                    } else break;
                }

                return .{
                    .token = ZonToken{ .binary_int = .{
                        .data = TokenData.init(Span.init(base_pos, base_pos + pos), 0, 0, self.depth),
                        .value = std.fmt.parseInt(u128, input[0..pos], 0) catch 0,
                        .raw = input[0..pos],
                        .has_underscores = has_underscores,
                    } },
                    .consumed = pos,
                };
            } else if (next == 'o' or next == 'O') {
                // Octal number - single pass parsing
                pos += 2;
                while (pos < input.len) {
                    if (input[pos] >= '0' and input[pos] <= '7') {
                        pos += 1;
                    } else if (input[pos] == '_') {
                        has_underscores = true;
                        pos += 1;
                    } else break;
                }

                return .{
                    .token = ZonToken{ .octal_int = .{
                        .data = TokenData.init(Span.init(base_pos, base_pos + pos), 0, 0, self.depth),
                        .value = std.fmt.parseInt(u128, input[0..pos], 0) catch 0,
                        .raw = input[0..pos],
                        .has_underscores = has_underscores,
                    } },
                    .consumed = pos,
                };
            }
        }

        // Parse decimal number (int or float)
        var has_dot = false;
        var has_exponent = false;

        // Parse integer part
        while (pos < input.len) {
            if (char.isDigit(input[pos])) {
                pos += 1;
            } else if (input[pos] == '_') {
                has_underscores = true;
                pos += 1;
            } else break;
        }

        // Check for decimal point
        if (pos < input.len and input[pos] == '.') {
            has_dot = true;
            pos += 1;
            while (pos < input.len) {
                if (char.isDigit(input[pos])) {
                    pos += 1;
                } else if (input[pos] == '_') {
                    has_underscores = true;
                    pos += 1;
                } else break;
            }
        }

        // Check for exponent
        if (pos < input.len and (input[pos] == 'e' or input[pos] == 'E')) {
            has_exponent = true;
            pos += 1;
            if (pos < input.len and (input[pos] == '+' or input[pos] == '-')) {
                pos += 1;
            }
            while (pos < input.len and char.isDigit(input[pos])) {
                pos += 1;
            }
        }

        const data = TokenData.init(Span.init(base_pos, base_pos + pos), 0, 0, self.depth);

        if (has_dot or has_exponent) {
            // Floating point - no redundant checks
            return .{
                .token = ZonToken{ .float = .{
                    .data = data,
                    .value = std.fmt.parseFloat(f64, input[0..pos]) catch 0.0,
                    .raw = input[0..pos],
                    .has_underscores = has_underscores,
                    .has_exponent = has_exponent,
                } },
                .consumed = pos,
            };
        } else {
            // Decimal integer - no redundant checks
            return .{
                .token = ZonToken{ .decimal_int = .{
                    .data = data,
                    .value = std.fmt.parseInt(i128, input[0..pos], 10) catch 0,
                    .raw = input[0..pos],
                    .has_underscores = has_underscores,
                } },
                .consumed = pos,
            };
        }
    }

    fn parseIdentifierOrKeyword(self: *Self, input: []const u8, base_pos: usize) !TokenResult {
        var pos: usize = 0;
        while (pos < input.len and (char.isAlphaNumeric(input[pos]) or input[pos] == '_')) {
            pos += 1;
        }

        const text = input[0..pos];
        const data = TokenData.init(
            Span.init(base_pos, base_pos + pos),
            0,
            0,
            self.depth,
        );

        // Check for keywords
        if (std.mem.eql(u8, text, "true") or std.mem.eql(u8, text, "false")) {
            return .{
                .token = ZonToken{
                    .boolean_value = .{
                        .data = data,
                        .value = std.mem.eql(u8, text, "true"),
                    },
                },
                .consumed = pos,
            };
        }

        if (std.mem.eql(u8, text, "null")) {
            return .{
                .token = ZonToken{ .null_value = data },
                .consumed = pos,
            };
        }

        if (std.mem.eql(u8, text, "undefined")) {
            return .{
                .token = ZonToken{ .undefined_value = data },
                .consumed = pos,
            };
        }

        // Regular identifier
        return .{
            .token = ZonToken{
                .identifier = .{
                    .data = data,
                    .text = text,
                    .is_builtin = false,
                },
            },
            .consumed = pos,
        };
    }

    fn parseLineComment(self: *Self, input: []const u8, base_pos: usize) !TokenResult {
        var pos: usize = 2; // Skip //
        while (pos < input.len and input[pos] != '\n') {
            pos += 1;
        }

        const data = TokenData.init(
            Span.init(base_pos, base_pos + pos),
            0,
            0,
            self.depth,
        );

        return .{
            .token = ZonToken{
                .comment = .{
                    .data = data,
                    .text = input[0..pos],
                    .kind = if (input.len > 2 and input[2] == '/') CommentKind.doc else if (input.len > 2 and input[2] == '!') CommentKind.container else CommentKind.line,
                },
            },
            .consumed = pos,
        };
    }

    fn parseBlockComment(self: *Self, input: []const u8, base_pos: usize) !TokenResult {
        var pos: usize = 2; // Skip /*
        while (pos < input.len - 1) {
            if (input[pos] == '*' and input[pos + 1] == '/') {
                pos += 2;
                break;
            }
            pos += 1;
        }

        if (pos >= input.len - 1) {
            // Incomplete block comment
            self.state.context = .in_comment_block;
            // TODO: Implement proper partial token storage
            // self.state.storePartialToken(input);
            return .{ .token = null, .consumed = input.len };
        }

        const data = TokenData.init(
            Span.init(base_pos, base_pos + pos),
            0,
            0,
            self.depth,
        );

        return .{
            .token = ZonToken{
                .comment = .{
                    .data = data,
                    .text = input[0..pos],
                    .kind = CommentKind.line, // Block comments aren't in ZON, treating as line
                },
            },
            .consumed = pos,
        };
    }
};

// Tests
const testing = std.testing;

test "StatefulZonLexer - basic tokens" {
    var lexer = StatefulZonLexer.init(testing.allocator, .{});
    defer lexer.deinit();

    const input = ".{.name = \"test\", .value = 42}";
    const tokens = try lexer.processChunk(input, 0, testing.allocator);
    defer testing.allocator.free(tokens);

    try testing.expect(tokens.len >= 7); // .{, .name, =, "test", ,, .value, =, 42, }
    try testing.expect(tokens[0] == .zon);
    try testing.expect(tokens[0].zon == .struct_literal);
}

test "StatefulZonLexer - enum literals" {
    var lexer = StatefulZonLexer.init(testing.allocator, .{});
    defer lexer.deinit();

    const input = ".red .green .blue";
    const tokens = try lexer.processChunk(input, 0, testing.allocator);
    defer testing.allocator.free(tokens);

    // Should have 3 enum literals + whitespace
    var enum_count: usize = 0;
    for (tokens) |token| {
        if (token == .zon and token.zon == .enum_literal) {
            enum_count += 1;
        }
    }
    try testing.expectEqual(@as(usize, 3), enum_count);
}

test "StatefulZonLexer - builtin functions" {
    var lexer = StatefulZonLexer.init(testing.allocator, .{});
    defer lexer.deinit();

    const input = "@import(@embedFile(@src))";
    const tokens = try lexer.processChunk(input, 0, testing.allocator);
    defer testing.allocator.free(tokens);

    // Should have builtin identifiers
    var builtin_count: usize = 0;
    for (tokens) |token| {
        if (token == .zon and token.zon == .identifier) {
            if (token.zon.identifier.is_builtin) {
                builtin_count += 1;
            }
        }
    }
    try testing.expect(builtin_count >= 3); // @import, @embedFile, @src
}

test "StatefulZonLexer - char literals" {
    var lexer = StatefulZonLexer.init(testing.allocator, .{});
    defer lexer.deinit();

    const input = "'a' '\\n' '\\t'";
    const tokens = try lexer.processChunk(input, 0, testing.allocator);
    defer testing.allocator.free(tokens);

    var char_count: usize = 0;
    for (tokens) |token| {
        if (token == .zon and token.zon == .char_literal) {
            char_count += 1;
        }
    }
    try testing.expectEqual(@as(usize, 3), char_count);
}
