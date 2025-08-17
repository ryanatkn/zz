const std = @import("std");
const Span = @import("span.zig").Span;
const TokenKind = @import("predicate.zig").TokenKind;

/// Enhanced token representation for stratified parser
/// Includes pre-computed bracket depth for instant bracket matching
/// Optimized for frequent access and minimal memory usage
pub const Token = struct {
    /// Text span this token covers
    span: Span,
    
    /// Classification of this token
    kind: TokenKind,
    
    /// Actual text content (slice into source)
    text: []const u8,
    
    /// Pre-computed bracket depth at this token position
    /// Enables O(1) bracket matching without scanning
    bracket_depth: u16,
    
    /// Additional token flags packed into a single byte
    flags: TokenFlags,

    /// Create a new token with all fields
    pub fn init(
        span: Span,
        kind: TokenKind,
        text: []const u8,
        bracket_depth: u16,
        flags: TokenFlags,
    ) Token {
        return .{
            .span = span,
            .kind = kind,
            .text = text,
            .bracket_depth = bracket_depth,
            .flags = flags,
        };
    }

    /// Create a simple token with no special flags
    pub fn simple(
        span: Span,
        kind: TokenKind,
        text: []const u8,
        bracket_depth: u16,
    ) Token {
        return init(span, kind, text, bracket_depth, TokenFlags{});
    }

    /// Create a token for an opening delimiter
    pub fn openDelimiter(
        span: Span,
        text: []const u8,
        bracket_depth: u16,
    ) Token {
        return init(span, .delimiter, text, bracket_depth, TokenFlags{
            .is_open_delimiter = true,
        });
    }

    /// Create a token for a closing delimiter
    pub fn closeDelimiter(
        span: Span,
        text: []const u8,
        bracket_depth: u16,
    ) Token {
        return init(span, .delimiter, text, bracket_depth, TokenFlags{
            .is_close_delimiter = true,
        });
    }

    /// Create a trivia token (whitespace, comment)
    pub fn trivia(
        span: Span,
        kind: TokenKind,
        text: []const u8,
    ) Token {
        return init(span, kind, text, 0, TokenFlags{
            .is_trivia = true,
        });
    }

    /// Get the length of this token
    pub fn len(self: Token) usize {
        return self.span.len();
    }

    /// Check if this token is empty
    pub fn isEmpty(self: Token) bool {
        return self.span.isEmpty();
    }

    /// Check if this token contains a position
    pub fn contains(self: Token, pos: usize) bool {
        return self.span.contains(pos);
    }

    /// Check if this token overlaps with a span
    pub fn overlaps(self: Token, span: Span) bool {
        return self.span.overlaps(span);
    }

    /// Check if this token is an opening delimiter
    pub fn isOpenDelimiter(self: Token) bool {
        return self.flags.is_open_delimiter;
    }

    /// Check if this token is a closing delimiter
    pub fn isCloseDelimiter(self: Token) bool {
        return self.flags.is_close_delimiter;
    }

    /// Check if this token is trivia (whitespace, comment)
    pub fn isTrivia(self: Token) bool {
        return self.flags.is_trivia;
    }

    /// Check if this token represents an error
    pub fn isError(self: Token) bool {
        return self.flags.is_error;
    }

    /// Check if this token was inserted during error recovery
    pub fn isInserted(self: Token) bool {
        return self.flags.is_inserted;
    }

    /// Check if this token is at the end of a line
    pub fn isEndOfLine(self: Token) bool {
        return self.flags.is_end_of_line;
    }

    /// Check if this token is a specific kind
    pub fn isKind(self: Token, kind: TokenKind) bool {
        return self.kind == kind;
    }

    /// Check if this token's text matches a string
    pub fn textEquals(self: Token, text: []const u8) bool {
        return std.mem.eql(u8, self.text, text);
    }

    /// Check if this token's text starts with a prefix
    pub fn textStartsWith(self: Token, prefix: []const u8) bool {
        return std.mem.startsWith(u8, self.text, prefix);
    }

    /// Check if this token's text ends with a suffix
    pub fn textEndsWith(self: Token, suffix: []const u8) bool {
        return std.mem.endsWith(u8, self.text, suffix);
    }

    /// Get the bracket change this token represents
    /// Returns +1 for opening, -1 for closing, 0 for other tokens
    pub fn bracketDelta(self: Token) i32 {
        if (self.isOpenDelimiter()) return 1;
        if (self.isCloseDelimiter()) return -1;
        return 0;
    }

    /// Check if this token is at a deeper bracket level than another
    pub fn isDeeperThan(self: Token, other: Token) bool {
        return self.bracket_depth > other.bracket_depth;
    }

    /// Check if this token is at the same bracket level as another
    pub fn isSameLevelAs(self: Token, other: Token) bool {
        return self.bracket_depth == other.bracket_depth;
    }

    /// Get the delimiter type for bracket matching
    pub fn getDelimiterType(self: Token) ?DelimiterType {
        if (!self.isKind(.delimiter)) return null;
        if (self.text.len == 0) return null;
        
        return switch (self.text[0]) {
            '(' => .paren,
            ')' => .paren,
            '[' => .bracket,
            ']' => .bracket,
            '{' => .brace,
            '}' => .brace,
            '<' => .angle,
            '>' => .angle,
            else => null,
        };
    }

    /// Check if this token matches another token for bracket pairing
    pub fn isMatchingPair(self: Token, other: Token) bool {
        const self_type = self.getDelimiterType() orelse return false;
        const other_type = other.getDelimiterType() orelse return false;
        
        return self_type == other_type and 
               self.isOpenDelimiter() != other.isOpenDelimiter();
    }

    /// Compare tokens by their spans for ordering
    pub fn order(self: Token, other: Token) std.math.Order {
        return self.span.order(other.span);
    }

    /// Check if two tokens are equal
    pub fn eql(self: Token, other: Token) bool {
        return self.span.eql(other.span) and
               self.kind == other.kind and
               std.mem.eql(u8, self.text, other.text) and
               self.bracket_depth == other.bracket_depth and
               std.meta.eql(self.flags, other.flags);
    }

    /// Calculate hash for this token
    pub fn hash(self: Token) u64 {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(std.mem.asBytes(&self.span.hash()));
        hasher.update(std.mem.asBytes(&self.kind));
        hasher.update(self.text);
        hasher.update(std.mem.asBytes(&self.bracket_depth));
        return hasher.final();
    }

    /// Format token for debugging
    pub fn format(
        self: Token,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        
        try writer.print("Token({s}, \"{s}\", {}, depth={d}", .{
            @tagName(self.kind),
            self.text,
            self.span,
            self.bracket_depth,
        });
        
        if (self.isOpenDelimiter()) try writer.writeAll(", open");
        if (self.isCloseDelimiter()) try writer.writeAll(", close");
        if (self.isTrivia()) try writer.writeAll(", trivia");
        if (self.isError()) try writer.writeAll(", error");
        
        try writer.writeAll(")");
    }
};

/// Flags for additional token properties
pub const TokenFlags = struct {
    /// This token is an opening delimiter
    is_open_delimiter: bool = false,
    
    /// This token is a closing delimiter
    is_close_delimiter: bool = false,
    
    /// This token is trivia (whitespace, comment)
    is_trivia: bool = false,
    
    /// This token represents a parsing error
    is_error: bool = false,
    
    /// This token was inserted during error recovery
    is_inserted: bool = false,
    
    /// This token is at the end of a line
    is_end_of_line: bool = false,
    
    // 2 bits unused for future expansion
};

/// Types of delimiters for bracket matching
pub const DelimiterType = enum {
    paren,   // ( )
    bracket, // [ ]
    brace,   // { }
    angle,   // < >
};

/// Stream of tokens with utilities for processing
pub const TokenStream = struct {
    tokens: std.ArrayList(Token),
    current_index: usize = 0,

    pub fn init(allocator: std.mem.Allocator) TokenStream {
        return .{
            .tokens = std.ArrayList(Token).init(allocator),
        };
    }

    pub fn deinit(self: *TokenStream) void {
        self.tokens.deinit();
    }

    pub fn add(self: *TokenStream, token: Token) !void {
        try self.tokens.append(token);
    }

    pub fn len(self: TokenStream) usize {
        return self.tokens.items.len;
    }

    pub fn get(self: TokenStream, index: usize) ?Token {
        if (index >= self.tokens.items.len) return null;
        return self.tokens.items[index];
    }

    /// Get current token and advance
    pub fn next(self: *TokenStream) ?Token {
        const token = self.peek();
        if (token != null) self.current_index += 1;
        return token;
    }

    /// Peek at current token without advancing
    pub fn peek(self: TokenStream) ?Token {
        return self.get(self.current_index);
    }

    /// Peek ahead by offset tokens
    pub fn peekAhead(self: TokenStream, offset: usize) ?Token {
        return self.get(self.current_index + offset);
    }

    /// Check if at end of stream
    pub fn isAtEnd(self: TokenStream) bool {
        return self.current_index >= self.tokens.items.len;
    }

    /// Reset to beginning of stream
    pub fn reset(self: *TokenStream) void {
        self.current_index = 0;
    }

    /// Find tokens overlapping with a span
    pub fn findOverlapping(self: TokenStream, span: Span, allocator: std.mem.Allocator) ![]Token {
        var result = std.ArrayList(Token).init(allocator);
        
        for (self.tokens.items) |token| {
            if (token.overlaps(span)) {
                try result.append(token);
            }
        }
        
        return result.toOwnedSlice();
    }

    /// Find tokens by kind
    pub fn findByKind(self: TokenStream, kind: TokenKind, allocator: std.mem.Allocator) ![]Token {
        var result = std.ArrayList(Token).init(allocator);
        
        for (self.tokens.items) |token| {
            if (token.isKind(kind)) {
                try result.append(token);
            }
        }
        
        return result.toOwnedSlice();
    }

    /// Find all delimiter tokens for bracket matching
    pub fn findDelimiters(self: TokenStream, allocator: std.mem.Allocator) ![]Token {
        return self.findByKind(.delimiter, allocator);
    }

    /// Filter out trivia tokens
    pub fn skipTrivia(self: TokenStream, allocator: std.mem.Allocator) ![]Token {
        var result = std.ArrayList(Token).init(allocator);
        
        for (self.tokens.items) |token| {
            if (!token.isTrivia()) {
                try result.append(token);
            }
        }
        
        return result.toOwnedSlice();
    }
};

// Tests
const testing = std.testing;

test "Token creation and basic properties" {
    const span = Span.init(0, 5);
    const token = Token.simple(span, .identifier, "hello", 0);

    try testing.expect(token.span.eql(span));
    try testing.expectEqual(TokenKind.identifier, token.kind);
    try testing.expectEqualStrings("hello", token.text);
    try testing.expectEqual(@as(u16, 0), token.bracket_depth);
    try testing.expectEqual(@as(usize, 5), token.len());
    try testing.expect(!token.isEmpty());
}

test "Token delimiter creation" {
    const span = Span.init(10, 11);
    const open_token = Token.openDelimiter(span, "(", 1);
    const close_token = Token.closeDelimiter(span, ")", 0);

    try testing.expect(open_token.isOpenDelimiter());
    try testing.expect(!open_token.isCloseDelimiter());
    try testing.expect(!close_token.isOpenDelimiter());
    try testing.expect(close_token.isCloseDelimiter());
    
    try testing.expectEqual(@as(i32, 1), open_token.bracketDelta());
    try testing.expectEqual(@as(i32, -1), close_token.bracketDelta());
}

test "Token trivia creation" {
    const span = Span.init(5, 10);
    const trivia_token = Token.trivia(span, .whitespace, "     ");

    try testing.expect(trivia_token.isTrivia());
    try testing.expectEqual(TokenKind.whitespace, trivia_token.kind);
    try testing.expectEqualStrings("     ", trivia_token.text);
}

test "Token position operations" {
    const span = Span.init(10, 20);
    const token = Token.simple(span, .keyword, "function", 0);

    try testing.expect(token.contains(15));
    try testing.expect(!token.contains(5));
    try testing.expect(!token.contains(25));

    const overlapping_span = Span.init(15, 25);
    const non_overlapping_span = Span.init(25, 35);
    
    try testing.expect(token.overlaps(overlapping_span));
    try testing.expect(!token.overlaps(non_overlapping_span));
}

test "Token text operations" {
    const span = Span.init(0, 8);
    const token = Token.simple(span, .identifier, "variable", 0);

    try testing.expect(token.textEquals("variable"));
    try testing.expect(!token.textEquals("other"));
    try testing.expect(token.textStartsWith("var"));
    try testing.expect(token.textEndsWith("able"));
    try testing.expect(!token.textStartsWith("xyz"));
}

test "Token bracket operations" {
    const span = Span.init(0, 1);
    const shallow_token = Token.simple(span, .identifier, "x", 1);
    const deep_token = Token.simple(span, .identifier, "y", 3);

    try testing.expect(deep_token.isDeeperThan(shallow_token));
    try testing.expect(!shallow_token.isDeeperThan(deep_token));
    try testing.expect(!shallow_token.isSameLevelAs(deep_token));

    const same_level_token = Token.simple(span, .identifier, "z", 1);
    try testing.expect(shallow_token.isSameLevelAs(same_level_token));
}

test "Token delimiter types and matching" {
    const span = Span.init(0, 1);
    const open_paren = Token.openDelimiter(span, "(", 1);
    const close_paren = Token.closeDelimiter(span, ")", 0);
    const open_brace = Token.openDelimiter(span, "{", 1);

    try testing.expectEqual(DelimiterType.paren, open_paren.getDelimiterType());
    try testing.expectEqual(DelimiterType.paren, close_paren.getDelimiterType());
    try testing.expectEqual(DelimiterType.brace, open_brace.getDelimiterType());

    try testing.expect(open_paren.isMatchingPair(close_paren));
    try testing.expect(!open_paren.isMatchingPair(open_brace));
}

test "Token ordering" {
    const span1 = Span.init(0, 5);
    const span2 = Span.init(10, 15);
    const token1 = Token.simple(span1, .identifier, "first", 0);
    const token2 = Token.simple(span2, .identifier, "second", 0);

    try testing.expectEqual(std.math.Order.lt, token1.order(token2));
    try testing.expectEqual(std.math.Order.gt, token2.order(token1));
}

test "Token equality" {
    const span = Span.init(0, 5);
    const token1 = Token.simple(span, .keyword, "const", 0);
    const token2 = Token.simple(span, .keyword, "const", 0);
    const token3 = Token.simple(span, .identifier, "const", 0);

    try testing.expect(token1.eql(token2));
    try testing.expect(!token1.eql(token3));
}

test "TokenStream operations" {
    var stream = TokenStream.init(testing.allocator);
    defer stream.deinit();

    const span1 = Span.init(0, 5);
    const span2 = Span.init(6, 10);
    const token1 = Token.simple(span1, .identifier, "hello", 0);
    const token2 = Token.trivia(span2, .whitespace, " ");

    try stream.add(token1);
    try stream.add(token2);

    try testing.expectEqual(@as(usize, 2), stream.len());
    try testing.expect(stream.get(0).?.eql(token1));
    try testing.expect(stream.get(1).?.eql(token2));

    // Test iteration
    try testing.expect(stream.peek().?.eql(token1));
    try testing.expect(stream.next().?.eql(token1));
    try testing.expect(stream.next().?.eql(token2));
    try testing.expect(stream.isAtEnd());

    stream.reset();
    try testing.expect(!stream.isAtEnd());

    // Test finding by kind
    const identifiers = try stream.findByKind(.identifier, testing.allocator);
    defer testing.allocator.free(identifiers);
    try testing.expectEqual(@as(usize, 1), identifiers.len);
    try testing.expect(identifiers[0].eql(token1));

    // Test skipping trivia
    const non_trivia = try stream.skipTrivia(testing.allocator);
    defer testing.allocator.free(non_trivia);
    try testing.expectEqual(@as(usize, 1), non_trivia.len);
    try testing.expect(non_trivia[0].eql(token1));
}