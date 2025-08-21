const std = @import("std");
const Token = @import("../../parser_old/foundation/types/token.zig").Token;
const TokenKind = @import("../../parser_old/foundation/types/predicate.zig").TokenKind;
const Span = @import("../../parser_old/foundation/types/span.zig").Span;

/// Generic streaming token that wraps language-specific tokens using vtable dispatch
/// This eliminates hardcoded union types while maintaining zero-copy performance
/// via interface-based dispatch.
pub const GenericStreamToken = struct {
    /// Opaque pointer to language-specific token
    token_ptr: *anyopaque,

    /// Function table for token operations
    vtable: *const VTable,

    const Self = @This();

    /// Virtual function table for language-agnostic token operations
    pub const VTable = struct {
        /// Get token span (zero-cost)
        getSpanFn: *const fn (token_ptr: *anyopaque) Span,

        /// Get generic token kind (fast mapping)
        getKindFn: *const fn (token_ptr: *anyopaque) TokenKind,

        /// Get token text slice (zero-cost)
        getTextFn: *const fn (token_ptr: *anyopaque) []const u8,

        /// Get nesting depth
        getDepthFn: *const fn (token_ptr: *anyopaque) u16,

        /// Check if token is trivia (whitespace/comments)
        isTriviaFn: *const fn (token_ptr: *anyopaque) bool,

        /// Check if token is opening delimiter
        isOpenDelimiterFn: *const fn (token_ptr: *anyopaque) bool,

        /// Check if token is closing delimiter
        isCloseDelimiterFn: *const fn (token_ptr: *anyopaque) bool,

        /// Check if token represents an error
        isErrorFn: *const fn (token_ptr: *anyopaque) bool,

        /// Convert to generic token (slow path - avoid if possible)
        toGenericTokenFn: *const fn (token_ptr: *anyopaque, source: []const u8) Token,

        /// Get debug information for the token
        getDebugInfoFn: ?*const fn (token_ptr: *anyopaque) []const u8 = null,
    };

    /// Create generic stream token from language-specific token
    pub fn init(token_ptr: *anyopaque, vtable: *const VTable) Self {
        return Self{
            .token_ptr = token_ptr,
            .vtable = vtable,
        };
    }

    /// Get token span without conversion (zero-cost)
    pub inline fn span(self: Self) Span {
        return self.vtable.getSpanFn(self.token_ptr);
    }

    /// Get token kind with fast mapping
    pub inline fn kind(self: Self) TokenKind {
        return self.vtable.getKindFn(self.token_ptr);
    }

    /// Get text slice without conversion
    pub inline fn text(self: Self) []const u8 {
        return self.vtable.getTextFn(self.token_ptr);
    }

    /// Get depth/nesting level
    pub inline fn depth(self: Self) u16 {
        return self.vtable.getDepthFn(self.token_ptr);
    }

    /// Check if token is trivia (whitespace/comments)
    pub inline fn isTrivia(self: Self) bool {
        return self.vtable.isTriviaFn(self.token_ptr);
    }

    /// Check if token is an opening delimiter
    pub inline fn isOpenDelimiter(self: Self) bool {
        return self.vtable.isOpenDelimiterFn(self.token_ptr);
    }

    /// Check if token is a closing delimiter
    pub inline fn isCloseDelimiter(self: Self) bool {
        return self.vtable.isCloseDelimiterFn(self.token_ptr);
    }

    /// Check if token represents an error
    pub inline fn isError(self: Self) bool {
        return self.vtable.isErrorFn(self.token_ptr);
    }

    /// Convert to generic token only when absolutely necessary
    /// This is the slow path - avoid if possible
    pub fn toGenericToken(self: Self, source: []const u8) Token {
        return self.vtable.toGenericTokenFn(self.token_ptr, source);
    }

    /// Get debug information (if available)
    pub fn getDebugInfo(self: Self) ?[]const u8 {
        if (self.vtable.getDebugInfoFn) |debug_fn| {
            return debug_fn(self.token_ptr);
        }
        return null;
    }
};

/// Buffer for streaming tokens with efficient allocation strategy
pub const GenericStreamTokenBuffer = struct {
    tokens: std.ArrayList(GenericStreamToken),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .tokens = std.ArrayList(GenericStreamToken).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.tokens.deinit();
    }

    /// Add token to buffer
    pub fn append(self: *Self, token: GenericStreamToken) !void {
        try self.tokens.append(token);
    }

    /// Add multiple tokens to buffer
    pub fn appendSlice(self: *Self, tokens: []const GenericStreamToken) !void {
        try self.tokens.appendSlice(tokens);
    }

    /// Get token at index
    pub fn get(self: *Self, index: usize) ?GenericStreamToken {
        if (index >= self.tokens.items.len) return null;
        return self.tokens.items[index];
    }

    /// Get all tokens
    pub fn items(self: *Self) []GenericStreamToken {
        return self.tokens.items;
    }

    /// Clear buffer, retaining capacity
    pub fn clear(self: *Self) void {
        self.tokens.clearRetainingCapacity();
    }

    /// Get number of tokens
    pub fn len(self: *Self) usize {
        return self.tokens.items.len;
    }

    /// Reserve capacity for tokens
    pub fn ensureCapacity(self: *Self, capacity: usize) !void {
        try self.tokens.ensureTotalCapacity(capacity);
    }
};

/// Helper functions to create VTables for common language-specific tokens
pub const VTableHelpers = struct {
    /// Create VTable for generic Token (fallback)
    pub fn createGenericTokenVTable() GenericStreamToken.VTable {
        return GenericStreamToken.VTable{
            .getSpanFn = getGenericSpan,
            .getKindFn = getGenericKind,
            .getTextFn = getGenericText,
            .getDepthFn = getGenericDepth,
            .isTriviaFn = isGenericTrivia,
            .isOpenDelimiterFn = isGenericOpenDelimiter,
            .isCloseDelimiterFn = isGenericCloseDelimiter,
            .isErrorFn = isGenericError,
            .toGenericTokenFn = toGenericFromGeneric,
        };
    }

    // Generic Token vtable implementations
    fn getGenericSpan(token_ptr: *anyopaque) Span {
        const token: *Token = @ptrCast(@alignCast(token_ptr));
        return token.span;
    }

    fn getGenericKind(token_ptr: *anyopaque) TokenKind {
        const token: *Token = @ptrCast(@alignCast(token_ptr));
        return token.kind;
    }

    fn getGenericText(token_ptr: *anyopaque) []const u8 {
        const token: *Token = @ptrCast(@alignCast(token_ptr));
        return token.text;
    }

    fn getGenericDepth(token_ptr: *anyopaque) u16 {
        const token: *Token = @ptrCast(@alignCast(token_ptr));
        return token.bracket_depth;
    }

    fn isGenericTrivia(token_ptr: *anyopaque) bool {
        const token: *Token = @ptrCast(@alignCast(token_ptr));
        return token.isTrivia();
    }

    fn isGenericOpenDelimiter(token_ptr: *anyopaque) bool {
        const token: *Token = @ptrCast(@alignCast(token_ptr));
        return token.isOpenDelimiter();
    }

    fn isGenericCloseDelimiter(token_ptr: *anyopaque) bool {
        const token: *Token = @ptrCast(@alignCast(token_ptr));
        return token.isCloseDelimiter();
    }

    fn isGenericError(token_ptr: *anyopaque) bool {
        const token: *Token = @ptrCast(@alignCast(token_ptr));
        return token.isError();
    }

    fn toGenericFromGeneric(token_ptr: *anyopaque, source: []const u8) Token {
        _ = source; // unused for generic tokens
        const token: *Token = @ptrCast(@alignCast(token_ptr));
        return token.*;
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "GenericStreamToken - vtable dispatch" {
    // Create a generic token
    var token = Token{
        .kind = .string_literal,
        .span = Span{ .start = 0, .end = 5 },
        .text = "test",
        .bracket_depth = 0,
        .flags = .{},
    };

    // Create vtable
    const vtable = VTableHelpers.createGenericTokenVTable();

    // Create generic stream token
    const stream_token = GenericStreamToken.init(&token, &vtable);

    // Test vtable dispatch
    try testing.expectEqual(TokenKind.string_literal, stream_token.kind());
    try testing.expectEqual(@as(usize, 0), stream_token.span().start);
    try testing.expectEqual(@as(usize, 5), stream_token.span().end);
    try testing.expectEqualStrings("test", stream_token.text());
    try testing.expectEqual(@as(u16, 0), stream_token.depth());
    try testing.expect(!stream_token.isTrivia());
    try testing.expect(!stream_token.isError());
}

test "GenericStreamTokenBuffer - basic operations" {
    var buffer = GenericStreamTokenBuffer.init(testing.allocator);
    defer buffer.deinit();

    // Create test token
    var token = Token{
        .kind = .identifier,
        .span = Span{ .start = 0, .end = 3 },
        .text = "foo",
        .bracket_depth = 0,
        .flags = .{},
    };

    const vtable = VTableHelpers.createGenericTokenVTable();
    const stream_token = GenericStreamToken.init(&token, &vtable);

    // Test buffer operations
    try buffer.append(stream_token);
    try testing.expectEqual(@as(usize, 1), buffer.len());

    const retrieved = buffer.get(0).?;
    try testing.expectEqualStrings("foo", retrieved.text());

    buffer.clear();
    try testing.expectEqual(@as(usize, 0), buffer.len());
}
