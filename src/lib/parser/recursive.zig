/// Recursive descent parsing infrastructure
///
/// Common utilities for building recursive descent parsers.
const std = @import("std");
const Token = @import("../token/token.zig").Token;
const TokenKind = @import("../token/token.zig").TokenKind;
const AST = @import("../ast/node.zig").AST;
const Node = @import("../ast/node.zig").Node;
const Span = @import("../span/span.zig").Span;

/// Parser state for recursive descent
pub const RecursiveParser = struct {
    allocator: std.mem.Allocator,
    tokens: []const Token,
    current: usize = 0,
    errors: std.ArrayList(ParseError),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, tokens: []const Token) Self {
        return .{
            .allocator = allocator,
            .tokens = tokens,
            .errors = std.ArrayList(ParseError).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.errors.deinit();
    }

    /// Current token
    pub fn peek(self: *Self) ?Token {
        if (self.current >= self.tokens.len) return null;
        return self.tokens[self.current];
    }

    /// Look ahead n tokens
    pub fn peekAhead(self: *Self, n: usize) ?Token {
        const index = self.current + n;
        if (index >= self.tokens.len) return null;
        return self.tokens[index];
    }

    /// Consume current token and advance
    pub fn consume(self: *Self) ?Token {
        if (self.current >= self.tokens.len) return null;
        const token = self.tokens[self.current];
        self.current += 1;
        return token;
    }

    /// Consume token if it matches kind
    pub fn consumeIf(self: *Self, kind: TokenKind) ?Token {
        if (self.peek()) |token| {
            if (token.kind == kind) {
                return self.consume();
            }
        }
        return null;
    }

    /// Expect token of specific kind
    pub fn expect(self: *Self, kind: TokenKind) !Token {
        if (self.peek()) |token| {
            if (token.kind == kind) {
                return self.consume().?;
            }
            try self.addError(.{
                .kind = .UnexpectedToken,
                .expected = kind,
                .found = token.kind,
                .span = token.span,
            });
            return error.UnexpectedToken;
        }
        try self.addError(.{
            .kind = .UnexpectedEOF,
            .expected = kind,
            .found = null,
            .span = self.lastSpan(),
        });
        return error.UnexpectedEOF;
    }

    /// Skip tokens until one of the given kinds
    pub fn skipUntil(self: *Self, kinds: []const TokenKind) void {
        while (self.peek()) |token| {
            for (kinds) |kind| {
                if (token.kind == kind) return;
            }
            _ = self.consume();
        }
    }

    /// Check if at end of tokens
    pub fn isEof(self: *Self) bool {
        return self.current >= self.tokens.len;
    }

    /// Mark current position for backtracking
    pub fn mark(self: *Self) usize {
        return self.current;
    }

    /// Restore to marked position
    pub fn restore(self: *Self, mark: usize) void {
        self.current = mark;
    }

    /// Add parse error
    pub fn addError(self: *Self, err: ParseError) !void {
        try self.errors.append(err);
    }

    /// Get span from mark to current
    pub fn spanFrom(self: *Self, mark: usize) Span {
        const start_token = self.tokens[mark];
        const end_token = if (self.current > 0)
            self.tokens[self.current - 1]
        else
            start_token;

        return Span{
            .start = start_token.span.start,
            .end = end_token.span.end,
        };
    }

    fn lastSpan(self: *Self) Span {
        if (self.current > 0) {
            return self.tokens[self.current - 1].span;
        }
        return Span{ .start = 0, .end = 0 };
    }
};

/// Parse error information
pub const ParseError = struct {
    kind: ParseErrorKind,
    expected: ?TokenKind = null,
    found: ?TokenKind = null,
    span: Span,
    message: ?[]const u8 = null,
};

pub const ParseErrorKind = enum {
    UnexpectedToken,
    UnexpectedEOF,
    InvalidSyntax,
    DuplicateKey,
    InvalidExpression,
    MissingDelimiter,
};

/// Common parser combinators
pub const Combinators = struct {
    /// Parse zero or more of something
    pub fn many(
        comptime T: type,
        parser: *RecursiveParser,
        allocator: std.mem.Allocator,
        parseFn: fn (*RecursiveParser) anyerror!T,
    ) ![]T {
        var results = std.ArrayList(T).init(allocator);

        while (!parser.isEof()) {
            const mark = parser.mark();
            if (parseFn(parser)) |result| {
                try results.append(result);
            } else |_| {
                parser.restore(mark);
                break;
            }
        }

        return results.toOwnedSlice();
    }

    /// Parse one or more of something
    pub fn many1(
        comptime T: type,
        parser: *RecursiveParser,
        allocator: std.mem.Allocator,
        parseFn: fn (*RecursiveParser) anyerror!T,
    ) ![]T {
        var results = std.ArrayList(T).init(allocator);

        // First one is required
        try results.append(try parseFn(parser));

        // Rest are optional
        while (!parser.isEof()) {
            const mark = parser.mark();
            if (parseFn(parser)) |result| {
                try results.append(result);
            } else |_| {
                parser.restore(mark);
                break;
            }
        }

        return results.toOwnedSlice();
    }

    /// Parse separated list
    pub fn separated(
        comptime T: type,
        parser: *RecursiveParser,
        allocator: std.mem.Allocator,
        parseFn: fn (*RecursiveParser) anyerror!T,
        separator: TokenKind,
    ) ![]T {
        var results = std.ArrayList(T).init(allocator);

        // Parse first item
        if (parseFn(parser)) |result| {
            try results.append(result);
        } else |err| {
            return err;
        }

        // Parse rest with separators
        while (parser.consumeIf(separator) != null) {
            try results.append(try parseFn(parser));
        }

        return results.toOwnedSlice();
    }

    /// Optional parse
    pub fn optional(
        comptime T: type,
        parser: *RecursiveParser,
        parseFn: fn (*RecursiveParser) anyerror!T,
    ) ?T {
        const mark = parser.mark();
        if (parseFn(parser)) |result| {
            return result;
        } else |_| {
            parser.restore(mark);
            return null;
        }
    }
};
