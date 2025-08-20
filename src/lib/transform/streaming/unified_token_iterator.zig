const std = @import("std");
const Token = @import("../../parser/foundation/types/token.zig").Token;
const JsonToken = @import("../../languages/json/tokens.zig").JsonToken;
const ZonToken = @import("../../languages/zon/tokens.zig").ZonToken;
const TokenConverter = @import("token_converter.zig").TokenConverter;
const StatefulJsonLexer = @import("../../languages/json/stateful_lexer.zig").StatefulJsonLexer;
const StatefulLexer = @import("stateful_lexer.zig").StatefulLexer;

/// Unified token iterator that supports multiple language lexers
/// Provides a consistent interface for streaming tokenization across languages
pub const UnifiedTokenIterator = struct {
    allocator: std.mem.Allocator,
    lexer: LexerKind,
    source: []const u8,
    position: usize,
    chunk_size: usize,
    buffer: std.ArrayList(Token),
    buffer_index: usize,
    
    const Self = @This();
    const DEFAULT_CHUNK_SIZE = 4096;
    
    /// Supported lexer types
    pub const LexerKind = union(enum) {
        json: *StatefulJsonLexer,
        // zon: *StatefulZonLexer,  // TODO: Add when ZON stateful lexer is ready
        // typescript: *StatefulTypeScriptLexer,  // Future
        // zig: *StatefulZigLexer,  // Future
    };
    
    /// Language type enum for initialization
    pub const Language = enum {
        json,
        zon,
        typescript,
        zig,
    };
    
    /// Options for creating the iterator
    pub const Options = struct {
        chunk_size: usize = DEFAULT_CHUNK_SIZE,
        allow_comments: bool = false,
        allow_trailing_commas: bool = false,
        json5_mode: bool = false,
        error_recovery: bool = true,
    };
    
    /// Initialize with language and options
    pub fn init(
        allocator: std.mem.Allocator,
        source: []const u8,
        language: Language,
        options: Options,
    ) !Self {
        const lexer = switch (language) {
            .json => blk: {
                const stateful_options = StatefulLexer.Options{
                    .allow_comments = options.allow_comments,
                    .allow_trailing_commas = options.allow_trailing_commas,
                    .json5_mode = options.json5_mode,
                    .error_recovery = options.error_recovery,
                };
                const json_lexer = try allocator.create(StatefulJsonLexer);
                json_lexer.* = StatefulJsonLexer.init(allocator, stateful_options);
                break :blk LexerKind{ .json = json_lexer };
            },
            else => return error.UnsupportedLanguage,
        };
        
        return Self{
            .allocator = allocator,
            .lexer = lexer,
            .source = source,
            .position = 0,
            .chunk_size = options.chunk_size,
            .buffer = std.ArrayList(Token).init(allocator),
            .buffer_index = 0,
        };
    }
    
    pub fn deinit(self: *Self) void {
        switch (self.lexer) {
            .json => |lexer| {
                lexer.deinit();
                self.allocator.destroy(lexer);
            },
        }
        self.buffer.deinit();
    }
    
    /// Get the next token
    pub fn next(self: *Self) !?Token {
        // If we have buffered tokens, return from buffer
        if (self.buffer_index < self.buffer.items.len) {
            const token = self.buffer.items[self.buffer_index];
            self.buffer_index += 1;
            return token;
        }
        
        // Check if we've processed all input
        if (self.position >= self.source.len) {
            return null;
        }
        
        // Clear buffer and refill
        self.buffer.clearRetainingCapacity();
        self.buffer_index = 0;
        
        // Process next chunk
        const chunk_end = @min(self.position + self.chunk_size, self.source.len);
        const chunk = self.source[self.position..chunk_end];
        
        // Get tokens based on lexer type
        const tokens = try self.processChunk(chunk, self.position);
        defer self.allocator.free(tokens);
        
        // Add to buffer
        try self.buffer.appendSlice(tokens);
        
        // Update position
        self.position = chunk_end;
        
        // Return first token from new buffer
        if (self.buffer.items.len > 0) {
            const token = self.buffer.items[0];
            self.buffer_index = 1;
            return token;
        }
        
        return null;
    }
    
    /// Process a chunk with the appropriate lexer
    fn processChunk(self: *Self, chunk: []const u8, chunk_pos: usize) ![]Token {
        switch (self.lexer) {
            .json => |lexer| {
                // Get JSON tokens
                const json_tokens = try lexer.processChunk(chunk, chunk_pos, self.allocator);
                defer self.allocator.free(json_tokens);
                
                // Convert to generic tokens
                return try TokenConverter.convertMany(
                    JsonToken,
                    json_tokens,
                    self.source,
                    self.allocator,
                );
            },
        }
    }
    
    /// Peek at the next token without consuming
    pub fn peek(self: *Self) !?Token {
        // If we have buffered tokens, peek from buffer
        if (self.buffer_index < self.buffer.items.len) {
            return self.buffer.items[self.buffer_index];
        }
        
        // Check if we've processed all input
        if (self.position >= self.source.len) {
            return null;
        }
        
        // We need to fill the buffer
        const token = try self.next();
        if (token) |t| {
            // Put it back
            self.buffer_index -= 1;
            return t;
        }
        
        return null;
    }
    
    /// Reset to the beginning
    pub fn reset(self: *Self) void {
        self.position = 0;
        self.buffer.clearRetainingCapacity();
        self.buffer_index = 0;
        
        switch (self.lexer) {
            .json => |lexer| lexer.reset(),
        }
    }
    
    /// Skip trivia tokens (whitespace and comments)
    pub fn skipTrivia(self: *Self) !void {
        while (try self.peek()) |token| {
            if (!token.isTrivia()) break;
            _ = try self.next();
        }
    }
    
    /// Collect all remaining tokens
    pub fn collectAll(self: *Self, allocator: std.mem.Allocator) ![]Token {
        var result = std.ArrayList(Token).init(allocator);
        errdefer result.deinit();
        
        while (try self.next()) |token| {
            try result.append(token);
        }
        
        return result.toOwnedSlice();
    }
    
    /// Collect tokens up to a specific kind
    pub fn collectUntil(
        self: *Self,
        kind: @import("../../parser/foundation/types/predicate.zig").TokenKind,
        allocator: std.mem.Allocator,
    ) ![]Token {
        var result = std.ArrayList(Token).init(allocator);
        errdefer result.deinit();
        
        while (try self.peek()) |token| {
            if (token.kind == kind) break;
            if (try self.next()) |t| {
                try result.append(t);
            }
        }
        
        return result.toOwnedSlice();
    }
};

// Tests
const testing = std.testing;

test "UnifiedTokenIterator - JSON basic" {
    const source = "{\"test\": 123}";
    var iter = try UnifiedTokenIterator.init(
        testing.allocator,
        source,
        .json,
        .{},
    );
    defer iter.deinit();
    
    // First token should be {
    const first = try iter.next();
    try testing.expect(first != null);
    try testing.expectEqual(@import("../../parser/foundation/types/predicate.zig").TokenKind.left_brace, first.?.kind);
    
    // Collect remaining tokens
    const remaining = try iter.collectAll(testing.allocator);
    defer testing.allocator.free(remaining);
    
    // Should have at least: string, colon, number, }
    try testing.expect(remaining.len >= 4);
}

test "UnifiedTokenIterator - peek" {
    const source = "[1, 2, 3]";
    var iter = try UnifiedTokenIterator.init(
        testing.allocator,
        source,
        .json,
        .{},
    );
    defer iter.deinit();
    
    // Peek should not consume
    const peeked = try iter.peek();
    try testing.expect(peeked != null);
    
    const next = try iter.next();
    try testing.expect(next != null);
    
    // Should be the same token
    try testing.expect(peeked.?.span.eql(next.?.span));
}

test "UnifiedTokenIterator - chunk boundary" {
    const source = "{\"a_very_long_property_name_that_spans_chunks\": \"value\"}";
    var iter = try UnifiedTokenIterator.init(
        testing.allocator,
        source,
        .json,
        .{ .chunk_size = 10 }, // Small chunks to test boundaries
    );
    defer iter.deinit();
    
    const all_tokens = try iter.collectAll(testing.allocator);
    defer testing.allocator.free(all_tokens);
    
    // Should handle chunk boundaries correctly
    try testing.expect(all_tokens.len > 0);
    try testing.expectEqual(
        @import("../../parser/foundation/types/predicate.zig").TokenKind.left_brace,
        all_tokens[0].kind,
    );
}

test "UnifiedTokenIterator - reset" {
    const source = "[1, 2]";
    var iter = try UnifiedTokenIterator.init(
        testing.allocator,
        source,
        .json,
        .{},
    );
    defer iter.deinit();
    
    // Consume some tokens
    _ = try iter.next();
    _ = try iter.next();
    
    // Reset
    iter.reset();
    
    // Should start from beginning
    const first = try iter.next();
    try testing.expect(first != null);
    try testing.expectEqual(
        @import("../../parser/foundation/types/predicate.zig").TokenKind.left_bracket,
        first.?.kind,
    );
}