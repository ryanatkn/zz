/// Token buffering for parsing
///
/// Provides efficient buffering for tokens during parsing operations.
const std = @import("std");
const Token = @import("token.zig").Token;

/// Ring buffer for tokens
pub const TokenBuffer = struct {
    tokens: []Token,
    capacity: usize,
    head: usize = 0,
    tail: usize = 0,
    count: usize = 0,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, capacity: usize) !Self {
        return .{
            .tokens = try allocator.alloc(Token, capacity),
            .capacity = capacity,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.tokens);
    }

    /// Add token to buffer
    pub fn push(self: *Self, token: Token) !void {
        if (self.count >= self.capacity) {
            return error.BufferFull;
        }

        self.tokens[self.tail] = token;
        self.tail = (self.tail + 1) % self.capacity;
        self.count += 1;
    }

    /// Remove token from buffer
    pub fn pop(self: *Self) ?Token {
        if (self.count == 0) return null;

        const token = self.tokens[self.head];
        self.head = (self.head + 1) % self.capacity;
        self.count -= 1;
        return token;
    }

    /// Peek at next token without removing
    pub fn peek(self: *Self) ?Token {
        if (self.count == 0) return null;
        return self.tokens[self.head];
    }

    /// Peek ahead n tokens
    pub fn peekAhead(self: *Self, n: usize) ?Token {
        if (n >= self.count) return null;
        const index = (self.head + n) % self.capacity;
        return self.tokens[index];
    }

    /// Clear buffer
    pub fn clear(self: *Self) void {
        self.head = 0;
        self.tail = 0;
        self.count = 0;
    }

    /// Check if buffer is empty
    pub fn isEmpty(self: *Self) bool {
        return self.count == 0;
    }

    /// Check if buffer is full
    pub fn isFull(self: *Self) bool {
        return self.count >= self.capacity;
    }

    /// Get number of tokens in buffer
    pub fn len(self: *Self) usize {
        return self.count;
    }
};

/// Lookahead buffer for predictive parsing
pub const LookaheadBuffer = struct {
    tokens: std.ArrayList(Token),
    position: usize = 0,
    mark_stack: std.ArrayList(usize),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .tokens = std.ArrayList(Token).init(allocator),
            .mark_stack = std.ArrayList(usize).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.tokens.deinit();
        self.mark_stack.deinit();
    }

    /// Add tokens to buffer
    pub fn addTokens(self: *Self, tokens: []const Token) !void {
        try self.tokens.appendSlice(tokens);
    }

    /// Get current token
    pub fn current(self: *Self) ?Token {
        if (self.position >= self.tokens.items.len) return null;
        return self.tokens.items[self.position];
    }

    /// Look ahead n tokens
    pub fn lookahead(self: *Self, n: usize) ?Token {
        const pos = self.position + n;
        if (pos >= self.tokens.items.len) return null;
        return self.tokens.items[pos];
    }

    /// Advance to next token
    pub fn advance(self: *Self) void {
        if (self.position < self.tokens.items.len) {
            self.position += 1;
        }
    }

    /// Skip n tokens
    pub fn skip(self: *Self, n: usize) void {
        self.position = @min(self.position + n, self.tokens.items.len);
    }

    /// Mark current position for backtracking
    pub fn pushMark(self: *Self) !void {
        try self.mark_stack.append(self.position);
    }

    /// Restore to marked position
    pub fn popMark(self: *Self, restore: bool) void {
        if (self.mark_stack.items.len > 0) {
            const mark = self.mark_stack.pop();
            if (restore) {
                self.position = mark;
            }
        }
    }

    /// Reset to beginning
    pub fn reset(self: *Self) void {
        self.position = 0;
        self.mark_stack.clearRetainingCapacity();
    }

    /// Check if at end
    pub fn isEof(self: *Self) bool {
        return self.position >= self.tokens.items.len;
    }

    /// Get remaining tokens
    pub fn remaining(self: *Self) []const Token {
        if (self.position >= self.tokens.items.len) return &.{};
        return self.tokens.items[self.position..];
    }
};
