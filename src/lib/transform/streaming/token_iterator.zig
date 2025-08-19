const std = @import("std");
const Context = @import("../transform.zig").Context;
const Token = @import("../../parser/foundation/types/token.zig").Token;

/// Iterator for streaming token processing with minimal memory footprint
///
/// Provides token-by-token iteration over large text inputs without loading
/// all tokens into memory at once. Particularly useful for files >10MB where
/// full tokenization would consume significant memory.
pub const TokenIterator = struct {
    allocator: std.mem.Allocator,
    input: []const u8,
    position: usize,
    context: *Context,
    lexer: ?LexerInterface,
    buffer: std.ArrayList(Token),
    buffer_index: usize,
    chunk_size: usize,
    eof_reached: bool,

    const Self = @This();
    const DEFAULT_CHUNK_SIZE = 4096; // 4KB chunks for balanced memory/performance

    /// Interface for language-specific lexers
    pub const LexerInterface = struct {
        const VTable = struct {
            tokenizeChunk: *const fn (lexer: *anyopaque, input: []const u8, start_pos: usize, allocator: std.mem.Allocator) anyerror![]Token,
            deinit: *const fn (lexer: *anyopaque) void,
        };

        ptr: *anyopaque,
        vtable: *const VTable,

        pub fn init(pointer: anytype) LexerInterface {
            const Ptr = @TypeOf(pointer);
            const PtrInfo = @typeInfo(Ptr);
            if (PtrInfo != .Pointer) @compileError("pointer must be a pointer");
            if (PtrInfo.Pointer.size != .One) @compileError("pointer must be a single-item pointer");

            _ = PtrInfo.Pointer.alignment;
            const gen = struct {
                fn tokenizeChunkImpl(ptr: *anyopaque, input: []const u8, start_pos: usize, allocator: std.mem.Allocator) anyerror![]Token {
                    const self: Ptr = @ptrCast(@alignCast(ptr));
                    return try self.tokenizeChunk(input, start_pos, allocator);
                }

                fn deinitImpl(ptr: *anyopaque) void {
                    const self: Ptr = @ptrCast(@alignCast(ptr));
                    self.deinit();
                }

                const vtable = VTable{
                    .tokenizeChunk = tokenizeChunkImpl,
                    .deinit = deinitImpl,
                };
            };

            return LexerInterface{
                .ptr = pointer,
                .vtable = &gen.vtable,
            };
        }

        pub fn tokenizeChunk(self: LexerInterface, input: []const u8, start_pos: usize, allocator: std.mem.Allocator) ![]Token {
            return try self.vtable.tokenizeChunk(self.ptr, input, start_pos, allocator);
        }

        pub fn deinit(self: LexerInterface) void {
            self.vtable.deinit(self.ptr);
        }
    };

    /// Initialize token iterator with streaming lexer
    pub fn init(allocator: std.mem.Allocator, input: []const u8, context: *Context, lexer: ?LexerInterface) Self {
        return Self{
            .allocator = allocator,
            .input = input,
            .position = 0,
            .context = context,
            .lexer = lexer,
            .buffer = std.ArrayList(Token).init(allocator),
            .buffer_index = 0,
            .chunk_size = DEFAULT_CHUNK_SIZE,
            .eof_reached = false,
        };
    }

    pub fn deinit(self: *Self) void {
        // Free any remaining tokens in buffer
        for (self.buffer.items) |token| {
            if (token.text.len > 0) {
                self.allocator.free(token.text);
            }
        }
        self.buffer.deinit();
        
        if (self.lexer) |lexer| {
            lexer.deinit();
        }
    }

    /// Set chunk size for memory/performance tuning
    pub fn setChunkSize(self: *Self, size: usize) void {
        self.chunk_size = size;
    }

    /// Get next token, loading chunks as needed
    pub fn next(self: *Self) !?Token {
        // If we have buffered tokens, return next one
        if (self.buffer_index < self.buffer.items.len) {
            const token = self.buffer.items[self.buffer_index];
            self.buffer_index += 1;
            return token;
        }

        // If we've reached EOF and buffer is empty, we're done
        if (self.eof_reached) {
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

    /// Peek at next token without consuming it
    pub fn peek(self: *Self) !?Token {
        const current_index = self.buffer_index;
        const token = try self.next();
        self.buffer_index = current_index; // Restore position
        return token;
    }

    /// Reset iterator to beginning
    pub fn reset(self: *Self) void {
        self.position = 0;
        self.buffer_index = 0;
        self.eof_reached = false;
        
        // Clear buffer
        for (self.buffer.items) |token| {
            if (token.text.len > 0) {
                self.allocator.free(token.text);
            }
        }
        self.buffer.clearRetainingCapacity();
    }

    /// Get current position in input
    pub fn getPosition(self: Self) usize {
        return self.position;
    }

    /// Get total input size
    pub fn getInputSize(self: Self) usize {
        return self.input.len;
    }

    /// Check if we've reached end of input
    pub fn isEof(self: Self) bool {
        return self.eof_reached and self.buffer_index >= self.buffer.items.len;
    }

    /// Get memory usage statistics
    pub fn getMemoryStats(self: Self) MemoryStats {
        var token_memory: usize = 0;
        for (self.buffer.items) |token| {
            token_memory += @sizeOf(Token) + token.text.len;
        }

        return MemoryStats{
            .buffer_tokens = self.buffer.items.len,
            .token_memory_bytes = token_memory,
            .buffer_capacity_bytes = self.buffer.capacity * @sizeOf(Token),
            .position = self.position,
            .input_size = self.input.len,
            .progress_percent = (@as(f64, @floatFromInt(self.position)) / @as(f64, @floatFromInt(self.input.len))) * 100.0,
        };
    }

    pub const MemoryStats = struct {
        buffer_tokens: usize,
        token_memory_bytes: usize,
        buffer_capacity_bytes: usize,
        position: usize,
        input_size: usize,
        progress_percent: f64,
    };

    fn loadNextChunk(self: *Self) !void {
        if (self.position >= self.input.len) {
            self.eof_reached = true;
            return;
        }

        // Clear buffer and reset index
        for (self.buffer.items) |token| {
            if (token.text.len > 0) {
                self.allocator.free(token.text);
            }
        }
        self.buffer.clearRetainingCapacity();
        self.buffer_index = 0;

        // Determine chunk boundaries
        _ = self.input.len - self.position;
        const chunk_end = @min(self.position + self.chunk_size, self.input.len);
        
        // Find a good breaking point (prefer to break on whitespace/newlines)
        var actual_end = chunk_end;
        if (chunk_end < self.input.len) {
            // Look backward up to 256 bytes for a good break point
            const search_limit = @min(256, chunk_end - self.position);
            var search_pos = chunk_end;
            
            while (search_pos > chunk_end - search_limit and search_pos > self.position) {
                search_pos -= 1;
                const ch = self.input[search_pos];
                if (ch == '\n' or ch == '\r' or ch == ' ' or ch == '\t' or ch == '}' or ch == ']' or ch == ',') {
                    actual_end = search_pos + 1;
                    break;
                }
            }
        }

        const chunk = self.input[self.position..actual_end];

        // Use lexer if available, otherwise create simple tokens
        if (self.lexer) |lexer| {
            const tokens = try lexer.tokenizeChunk(chunk, self.position, self.allocator);
            try self.buffer.appendSlice(tokens);
            self.allocator.free(tokens);
        } else {
            // Simple fallback tokenization (split on whitespace)
            try self.tokenizeSimple(chunk);
        }

        self.position = actual_end;
        
        if (self.position >= self.input.len) {
            self.eof_reached = true;
        }
    }

    fn tokenizeSimple(self: *Self, chunk: []const u8) !void {
        var start: usize = 0;
        var i: usize = 0;

        while (i <= chunk.len) {
            const is_delimiter = (i == chunk.len) or 
                                (chunk[i] == ' ' or chunk[i] == '\t' or chunk[i] == '\n' or chunk[i] == '\r');
            
            if (is_delimiter) {
                if (i > start) {
                    const text = try self.allocator.dupe(u8, chunk[start..i]);
                    const token = Token.simple(.{
                        .start = self.position + start,
                        .end = self.position + i,
                    }, .identifier, text, 0);
                    try self.buffer.append(token);
                }
                start = i + 1;
            }
            i += 1;
        }
    }
};

// Tests
const testing = std.testing;

test "TokenIterator - basic functionality" {
    var context = Context.init(testing.allocator);
    defer context.deinit();

    const input = "hello world foo bar";
    var iterator = TokenIterator.init(testing.allocator, input, &context, null);
    defer iterator.deinit();

    // Set small chunk size for testing
    iterator.setChunkSize(8);

    var token_count: usize = 0;
    while (try iterator.next()) |token| {
        token_count += 1;
        try testing.expect(token.text.len > 0);
    }

    try testing.expect(token_count == 4);
    try testing.expect(iterator.isEof());
}

test "TokenIterator - memory stats" {
    var context = Context.init(testing.allocator);
    defer context.deinit();

    const input = "test input for memory stats";
    var iterator = TokenIterator.init(testing.allocator, input, &context, null);
    defer iterator.deinit();

    const stats_before = iterator.getMemoryStats();
    try testing.expect(stats_before.position == 0);
    try testing.expect(stats_before.progress_percent == 0.0);

    _ = try iterator.next(); // Load first chunk

    const stats_after = iterator.getMemoryStats();
    try testing.expect(stats_after.buffer_tokens > 0);
    try testing.expect(stats_after.token_memory_bytes > 0);
}

test "TokenIterator - reset functionality" {
    var context = Context.init(testing.allocator);
    defer context.deinit();

    const input = "test reset functionality";
    var iterator = TokenIterator.init(testing.allocator, input, &context, null);
    defer iterator.deinit();

    // Consume some tokens
    _ = try iterator.next();
    _ = try iterator.next();

    const pos_before_reset = iterator.getPosition();
    try testing.expect(pos_before_reset > 0);

    // Reset and verify
    iterator.reset();
    try testing.expect(iterator.getPosition() == 0);
    try testing.expect(!iterator.isEof());
}