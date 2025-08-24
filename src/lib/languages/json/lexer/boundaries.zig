/// JSON Stream Lexer - Boundary handling functionality
/// Handles tokens that span 4KB boundaries in streaming scenarios
const std = @import("std");
const Lexer = @import("core.zig").Lexer;
const LexerState = @import("core.zig").LexerState;
const Token = @import("../../../token/mod.zig").Token;
const JsonToken = @import("../token/types.zig").Token;
const TokenKind = @import("../token/types.zig").TokenKind;
const packSpan = @import("../../../span/mod.zig").packSpan;
const Span = @import("../../../span/mod.zig").Span;
const TokenBuffer = @import("../token/buffer.zig").TokenBuffer;

/// Feed more data for boundary continuation
pub fn feedData(self: *Lexer, data: []const u8) !void {
    for (data) |byte| {
        _ = self.buffer.push(byte) catch break;
    }
}

/// Peek at next token without consuming
pub fn peek(self: *Lexer) ?Token {
    if (self.peeked_token) |token| return token;
    const token = self.next();
    self.peeked_token = token;
    return token;
}

/// Continue boundary token scanning
pub fn continueBoundaryToken(self: *Lexer) ?Token {
    if (self.token_buffer == null) return null;

    switch (self.state) {
        .in_string => return continueBoundaryString(self),
        else => return null, // Other boundary continuations not fully implemented
    }
}

fn continueBoundaryString(self: *Lexer) ?Token {
    // Simplified boundary string continuation
    if (self.token_buffer) |*buf| {
        while (self.buffer.peek()) |ch| {
            _ = self.buffer.pop();
            self.position += 1;
            self.column += 1;

            buf.appendChar(ch) catch {
                self.error_msg = "Out of memory";
                return makeErrorToken(self);
            };

            if (ch == '"') {
                const completion = buf.completeToken();
                self.state = .start;

                const token = JsonToken{
                    .span = packSpan(Span{ .start = completion.start_position, .end = self.position }),
                    .kind = .string_value,
                    .depth = self.depth,
                    .flags = .{ .has_escapes = completion.has_escapes },
                    .data = 0,
                };
                return Token{ .json = token };
            }
        }
        return makeContinuationToken(self);
    }
    return null;
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
