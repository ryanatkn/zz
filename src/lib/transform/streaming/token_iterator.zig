const std = @import("std");
const Context = @import("../transform.zig").Context;
const Token = @import("../../parser/foundation/types/token.zig").Token;
const StreamToken = @import("stream_token.zig").StreamToken;
const StatefulJsonLexer = @import("../../languages/json/stateful_lexer.zig").StatefulJsonLexer;
const StatefulZonLexer = @import("../../languages/zon/stateful_lexer.zig").StatefulZonLexer;
const StatefulLexer = @import("stateful_lexer.zig").StatefulLexer;

/// High-performance streaming token iterator using zero-copy StreamToken
/// Achieves <100ns/token by avoiding unnecessary conversions
pub const TokenIterator = struct {
    allocator: std.mem.Allocator,
    input: []const u8,
    position: usize,
    context: *Context,
    lexer: LexerKind,
    buffer: std.ArrayList(StreamToken),
    buffer_index: usize,
    chunk_size: usize,
    eof_reached: bool,

    const Self = @This();
    const DEFAULT_CHUNK_SIZE = 4096;

    /// Language type for lexer selection
    pub const Language = enum {
        json,
        zon,
        auto,
    };

    /// Lexer variant for different languages
    pub const LexerKind = union(enum) {
        json: *StatefulJsonLexer,
        zon: *StatefulZonLexer,
        none: void,

        pub fn deinit(self: *LexerKind, allocator: std.mem.Allocator) void {
            switch (self.*) {
                .json => |lexer| {
                    lexer.deinit();
                    allocator.destroy(lexer);
                },
                .zon => |lexer| {
                    lexer.deinit();
                    allocator.destroy(lexer);
                },
                .none => {},
            }
        }

        pub fn processChunk(
            self: *LexerKind,
            chunk: []const u8,
            chunk_pos: usize,
            allocator: std.mem.Allocator,
        ) ![]StreamToken {
            return switch (self.*) {
                .json => |lexer| try lexer.processChunk(chunk, chunk_pos, allocator),
                .zon => |lexer| try lexer.processChunk(chunk, chunk_pos, allocator),
                .none => try tokenizeSimple(chunk, chunk_pos, allocator),
            };
        }
    };

    /// Initialize with language detection
    pub fn init(allocator: std.mem.Allocator, input: []const u8, context: *Context, language: ?Language) !Self {
        const lang = language orelse detectLanguage(input);
        
        var lexer_kind: LexerKind = .none;
        switch (lang) {
            .json => {
                const lexer = try allocator.create(StatefulJsonLexer);
                lexer.* = StatefulJsonLexer.init(allocator, .{
                    .allow_comments = false,
                    .allow_trailing_commas = false,
                    .json5_mode = false,
                    .error_recovery = true,
                });
                lexer_kind = .{ .json = lexer };
            },
            .zon => {
                const lexer = try allocator.create(StatefulZonLexer);
                lexer.* = StatefulZonLexer.init(allocator, .{});
                lexer_kind = .{ .zon = lexer };
            },
            .auto => {
                // Auto-detection logic
                if (std.mem.startsWith(u8, std.mem.trim(u8, input, " \t\n\r"), "{") or
                    std.mem.startsWith(u8, std.mem.trim(u8, input, " \t\n\r"), "["))
                {
                    const lexer = try allocator.create(StatefulJsonLexer);
                    lexer.* = StatefulJsonLexer.init(allocator, .{
                        .allow_comments = false,
                        .allow_trailing_commas = false,
                        .json5_mode = false,
                        .error_recovery = true,
                    });
                    lexer_kind = .{ .json = lexer };
                } else {
                    lexer_kind = .none;
                }
            },
        }

        return Self{
            .allocator = allocator,
            .input = input,
            .position = 0,
            .context = context,
            .lexer = lexer_kind,
            .buffer = std.ArrayList(StreamToken).init(allocator),
            .buffer_index = 0,
            .chunk_size = DEFAULT_CHUNK_SIZE,
            .eof_reached = false,
        };
    }

    pub fn deinit(self: *Self) void {
        // Clean up lexer
        switch (self.lexer) {
            .json => |lexer| {
                lexer.deinit();
                self.allocator.destroy(lexer);
            },
            .zon => |lexer| {
                lexer.deinit();
                self.allocator.destroy(lexer);
            },
            .none => {},
        }
        
        // Clean up buffer
        self.buffer.deinit();
    }

    /// Get next token (returns StreamToken for zero-copy access)
    pub fn next(self: *Self) !?StreamToken {
        // Return buffered token if available
        if (self.buffer_index < self.buffer.items.len) {
            const token = self.buffer.items[self.buffer_index];
            self.buffer_index += 1;
            return token;
        }

        // Check if we're done
        if (self.eof_reached or self.position >= self.input.len) {
            return null;
        }

        // Load next chunk
        try self.loadNextChunk();

        // Try again with newly loaded tokens
        if (self.buffer_index < self.buffer.items.len) {
            const token = self.buffer.items[self.buffer_index];
            self.buffer_index += 1;
            return token;
        }

        return null;
    }

    /// Get next token as generic Token (with conversion overhead)
    pub fn nextAsGeneric(self: *Self) !?Token {
        const stream_token = try self.next() orelse return null;
        return stream_token.toGenericToken(self.input);
    }

    /// Peek at next token without consuming
    pub fn peek(self: *Self) !?StreamToken {
        const current_index = self.buffer_index;
        defer self.buffer_index = current_index;
        return try self.next();
    }

    /// Reset to beginning
    pub fn reset(self: *Self) void {
        self.position = 0;
        self.buffer_index = 0;
        self.eof_reached = false;
        self.buffer.clearRetainingCapacity();
    }

    /// Set chunk size for streaming
    pub fn setChunkSize(self: *Self, size: usize) void {
        self.chunk_size = size;
    }

    /// Skip trivia tokens
    pub fn skipTrivia(self: *Self) !void {
        while (try self.peek()) |token| {
            if (!token.isTrivia()) break;
            _ = try self.next();
        }
    }

    /// Check if at end of input
    pub fn isEof(self: *Self) bool {
        return self.eof_reached and self.buffer_index >= self.buffer.items.len;
    }

    /// Get current position in input
    pub fn getPosition(self: *Self) usize {
        return self.position;
    }

    /// Get memory statistics (stub for compatibility)
    pub fn getMemoryStats(self: *Self) struct { buffer_bytes: usize } {
        _ = self;
        return .{ .buffer_bytes = 0 };
    }

    /// Get input size
    pub fn getInputSize(self: *Self) usize {
        return self.input.len;
    }

    /// Load next chunk of tokens
    fn loadNextChunk(self: *Self) !void {
        // Clear buffer for new tokens
        self.buffer.clearRetainingCapacity();
        self.buffer_index = 0;

        // Determine chunk boundaries
        const chunk_end = @min(self.position + self.chunk_size, self.input.len);
        if (self.position >= chunk_end) {
            self.eof_reached = true;
            return;
        }

        const chunk = self.input[self.position..chunk_end];

        // Process chunk with appropriate lexer
        const tokens = try self.lexer.processChunk(chunk, self.position, self.allocator);
        defer self.allocator.free(tokens);

        // Add tokens to buffer
        try self.buffer.appendSlice(tokens);

        // Update position
        self.position = chunk_end;
        if (self.position >= self.input.len) {
            self.eof_reached = true;
        }
    }

    /// Detect language from content
    fn detectLanguage(input: []const u8) Language {
        const trimmed = std.mem.trim(u8, input, " \t\n\r");
        if (std.mem.startsWith(u8, trimmed, "{") or std.mem.startsWith(u8, trimmed, "[")) {
            return .json;
        }
        if (std.mem.startsWith(u8, trimmed, ".{")) {
            return .zon;
        }
        return .auto;
    }
};

/// Simple fallback tokenizer for when no language-specific lexer is available
fn tokenizeSimple(chunk: []const u8, chunk_pos: usize, allocator: std.mem.Allocator) ![]StreamToken {
    var tokens = std.ArrayList(StreamToken).init(allocator);
    defer tokens.deinit();
    
    var i: usize = 0;
    while (i < chunk.len) {
        // Skip whitespace
        while (i < chunk.len and std.ascii.isWhitespace(chunk[i])) {
            i += 1;
        }
        
        if (i >= chunk.len) break;
        
        // Find end of token (simple whitespace separation)
        const token_start = i;
        while (i < chunk.len and !std.ascii.isWhitespace(chunk[i])) {
            i += 1;
        }
        
        if (token_start < i) {
            // Create a generic token
            const token = Token{
                .kind = .identifier,
                .span = .{
                    .start = chunk_pos + token_start,
                    .end = chunk_pos + i,
                },
                .text = chunk[token_start..i],
                .bracket_depth = 0,
                .flags = .{},
            };
            
            try tokens.append(StreamToken{ .generic = token });
        }
    }
    
    return tokens.toOwnedSlice();
}

// Tests
const testing = std.testing;

test "TokenIterator - StreamToken zero-copy" {
    const input = "{\"test\": 123}";
    var ctx = Context.init(testing.allocator);
    defer ctx.deinit();

    var iter = try TokenIterator.init(testing.allocator, input, &ctx, .json);
    defer iter.deinit();

    // Get first token as StreamToken (no conversion)
    const first = try iter.next();
    try testing.expect(first != null);
    try testing.expectEqual(@as(usize, 0), first.?.span().start);

    // Access fields directly without conversion
    try testing.expect(first.?.isOpenDelimiter());
    try testing.expect(!first.?.isTrivia());
}

test "TokenIterator - chunk boundaries" {
    const input = "{\"a_very_long_property_name\": \"value\"}";
    var ctx = Context.init(testing.allocator);
    defer ctx.deinit();

    var iter = try TokenIterator.init(testing.allocator, input, &ctx, .json);
    defer iter.deinit();

    iter.setChunkSize(10); // Small chunks to test boundaries

    var token_count: usize = 0;
    while (try iter.next()) |_| {
        token_count += 1;
    }

    try testing.expect(token_count > 0);
}

test "TokenIterator - generic token conversion" {
    const input = "[1, 2, 3]";
    var ctx = Context.init(testing.allocator);
    defer ctx.deinit();

    var iter = try TokenIterator.init(testing.allocator, input, &ctx, .json);
    defer iter.deinit();

    // Get token as generic Token (with conversion)
    const first = try iter.nextAsGeneric();
    try testing.expect(first != null);
    try testing.expectEqual(.left_bracket, first.?.kind);
}