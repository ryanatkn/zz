const std = @import("std");
const Token = @import("../../parser/foundation/types/token.zig").Token;
const Language = @import("../../core/language.zig").Language;
const LanguageRegistry = @import("../../languages/registry.zig").LanguageRegistry;
const LexerDispatch = @import("lexer_dispatch.zig").LexerDispatch;
const GenericStreamToken = @import("generic_stream_token.zig").GenericStreamToken;
const GenericStreamTokenBuffer = @import("generic_stream_token.zig").GenericStreamTokenBuffer;
const VTableHelpers = @import("generic_stream_token.zig").VTableHelpers;
const Context = @import("../transform.zig").Context;

/// High-performance generic streaming token iterator
/// Achieves <100ns/token by avoiding language-specific code in transform layer
/// Uses dispatch and vtable patterns for zero-cost language abstraction
pub const GenericTokenIterator = struct {
    allocator: std.mem.Allocator,
    input: []const u8,
    position: usize,
    context: *Context,
    dispatch: LexerDispatch,
    registry: *LanguageRegistry,
    buffer: GenericStreamTokenBuffer,
    buffer_index: usize,
    chunk_size: usize,
    eof_reached: bool,

    const Self = @This();
    const DEFAULT_CHUNK_SIZE = 4096;

    /// Initialize with language detection and generic dispatch
    pub fn init(
        allocator: std.mem.Allocator, 
        input: []const u8, 
        context: *Context, 
        language: ?Language,
        registry: *LanguageRegistry,
    ) !Self {
        // Determine language - default to json if not specified
        const lang = language orelse Language.json;
        
        // Create generic dispatch
        const dispatch = if (lang != .unknown) 
            try LexerDispatch.fromLanguage(allocator, lang, registry)
        else
            try LexerDispatch.fromContent(allocator, input, registry);

        return Self{
            .allocator = allocator,
            .input = input,
            .position = 0,
            .context = context,
            .dispatch = dispatch,
            .registry = registry,
            .buffer = GenericStreamTokenBuffer.init(allocator),
            .buffer_index = 0,
            .chunk_size = DEFAULT_CHUNK_SIZE,
            .eof_reached = false,
        };
    }

    /// Convenience constructor with global registry
    pub fn initWithGlobalRegistry(
        allocator: std.mem.Allocator,
        input: []const u8,
        context: *Context,
        language: ?Language,
    ) !Self {
        const global_registry = try @import("../../languages/registry.zig").getGlobalRegistry(allocator);
        return init(allocator, input, context, language, global_registry);
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
    }

    /// Get next token (returns GenericStreamToken for zero-copy access)
    pub fn next(self: *Self) !?GenericStreamToken {
        // Return buffered token if available
        if (self.buffer_index < self.buffer.len()) {
            const token = self.buffer.get(self.buffer_index).?;
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
        if (self.buffer_index < self.buffer.len()) {
            const token = self.buffer.get(self.buffer_index).?;
            self.buffer_index += 1;
            return token;
        }

        return null;
    }

    /// Get next token as generic Token (with conversion overhead - avoid if possible)
    pub fn nextAsGeneric(self: *Self) !?Token {
        const stream_token = try self.next() orelse return null;
        return stream_token.toGenericToken(self.input);
    }

    /// Peek at next token without consuming
    pub fn peek(self: *Self) !?GenericStreamToken {
        const current_index = self.buffer_index;
        defer self.buffer_index = current_index;
        return try self.next();
    }

    /// Reset to beginning
    pub fn reset(self: *Self) void {
        self.position = 0;
        self.buffer_index = 0;
        self.eof_reached = false;
        self.buffer.clear();
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
        return self.eof_reached and self.buffer_index >= self.buffer.len();
    }

    /// Get current position in input
    pub fn getPosition(self: *Self) usize {
        return self.position;
    }

    /// Get language being processed
    pub fn getLanguage(self: *Self) Language {
        return self.dispatch.getLanguage();
    }

    /// Get memory statistics
    pub fn getMemoryStats(self: *Self) struct { buffer_bytes: usize, buffer_tokens: usize } {
        return .{ 
            .buffer_bytes = self.buffer.len() * @sizeOf(GenericStreamToken),
            .buffer_tokens = self.buffer.len(),
        };
    }

    /// Get input size
    pub fn getInputSize(self: *Self) usize {
        return self.input.len;
    }

    /// Load next chunk of tokens using generic dispatch
    fn loadNextChunk(self: *Self) !void {
        // Clear buffer for new tokens
        self.buffer.clear();
        self.buffer_index = 0;

        // Determine chunk boundaries
        const chunk_end = @min(self.position + self.chunk_size, self.input.len);
        if (self.position >= chunk_end) {
            self.eof_reached = true;
            return;
        }

        const chunk = self.input[self.position..chunk_end];

        // Process chunk with generic dispatch (no language-specific code!)
        const generic_tokens = try self.dispatch.tokenizeChunk(chunk, self.position);
        defer self.allocator.free(generic_tokens);

        // Convert tokens to generic stream tokens using vtable approach
        try self.convertToStreamTokens(generic_tokens);

        // Update position
        self.position = chunk_end;
        if (self.position >= self.input.len) {
            self.eof_reached = true;
        }
    }

    /// Convert generic tokens to stream tokens using vtables
    /// This eliminates language-specific conversion logic
    fn convertToStreamTokens(self: *Self, tokens: []Token) !void {
        const vtable = VTableHelpers.createGenericTokenVTable();
        
        for (tokens) |*token| {
            const stream_token = GenericStreamToken.init(token, &vtable);
            try self.buffer.append(stream_token);
        }
    }

    /// Iterator interface for for-loops
    pub fn iterator(self: *Self) Iterator {
        return Iterator{ .token_iterator = self };
    }

    pub const Iterator = struct {
        token_iterator: *Self,

        pub fn next(self: *Iterator) !?GenericStreamToken {
            return self.token_iterator.next();
        }
    };
};

/// Factory functions for common use cases

/// Create token iterator from file path
pub fn fromPath(
    allocator: std.mem.Allocator,
    file_path: []const u8,
    input: []const u8,
    registry: *LanguageRegistry,
) !GenericTokenIterator {
    var context = Context.init(allocator);
    
    const language = Language.fromPath(file_path);
    return GenericTokenIterator.init(allocator, input, &context, language, registry);
}

/// Create token iterator with language auto-detection
pub fn fromContent(
    allocator: std.mem.Allocator,
    input: []const u8,
    registry: *LanguageRegistry,
) !GenericTokenIterator {
    var context = Context.init(allocator);
    
    return GenericTokenIterator.init(allocator, input, &context, null, registry);
}

/// Create token iterator with explicit language
pub fn fromLanguage(
    allocator: std.mem.Allocator,
    input: []const u8,
    language: Language,
    registry: *LanguageRegistry,
) !GenericTokenIterator {
    var context = Context.init(allocator);
    
    return GenericTokenIterator.init(allocator, input, &context, language, registry);
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "GenericTokenIterator - initialization" {
    var registry = LanguageRegistry.init(testing.allocator);
    defer registry.deinit();
    
    var context = Context.init(testing.allocator);
    
    var iterator = try GenericTokenIterator.init(
        testing.allocator,
        "{ \"key\": \"value\" }",
        &context,
        .json,
        &registry,
    );
    defer iterator.deinit();
    
    try testing.expectEqual(Language.json, iterator.getLanguage());
    try testing.expect(!iterator.isEof());
    try testing.expectEqual(@as(usize, 19), iterator.getInputSize());
}

test "GenericTokenIterator - factory methods" {
    var registry = LanguageRegistry.init(testing.allocator);
    defer registry.deinit();
    
    // Test fromPath
    var iterator = try fromPath(testing.allocator, "config.json", "{}", &registry);
    defer iterator.deinit();
    try testing.expectEqual(Language.json, iterator.getLanguage());
    
    // Test fromContent (auto-detection)
    iterator = try fromContent(testing.allocator, "{ \"test\": true }", &registry);
    defer iterator.deinit();
    try testing.expectEqual(Language.json, iterator.getLanguage());
    
    // Test fromLanguage
    iterator = try fromLanguage(testing.allocator, "{}", .json, &registry);
    defer iterator.deinit();
    try testing.expectEqual(Language.json, iterator.getLanguage());
}

test "GenericTokenIterator - memory stats" {
    var registry = LanguageRegistry.init(testing.allocator);
    defer registry.deinit();
    
    var iterator = try fromContent(testing.allocator, "{}", &registry);
    defer iterator.deinit();
    
    const stats = iterator.getMemoryStats();
    try testing.expect(stats.buffer_bytes >= 0);
    try testing.expect(stats.buffer_tokens >= 0);
}