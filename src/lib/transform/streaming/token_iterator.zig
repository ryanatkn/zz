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
            if (PtrInfo != .pointer) @compileError("pointer must be a pointer");
            if (PtrInfo.pointer.size != .one) @compileError("pointer must be a single-item pointer");

            _ = PtrInfo.pointer.alignment;
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
        // OPTIMIZED: No need to free token.text since we use string slices now (Aug 19, 2025)
        // Token text points to original input buffer, not allocated memory
        // Only the ArrayList buffer itself needs cleanup
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

        // Clear buffer - no memory freeing needed since we use string slices
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

        // Clear buffer and reset index - no memory freeing needed since we use string slices
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
        // OPTIMIZED: Batch scanning algorithm (fixed Aug 19, 2025)
        // Replaces expensive character-by-character iteration with fast batch processing

        const delimiters = " \t\n\r"; // Common whitespace delimiters

        // More accurate capacity estimation: count potential tokens by delimiters
        var delimiter_count: usize = 0;
        for (chunk) |c| {
            if (std.mem.indexOfScalar(u8, delimiters, c) != null) {
                delimiter_count += 1;
            }
        }
        // Conservative estimate: delimiter_count + 1 potential tokens, plus 20% safety margin
        const estimated_tokens = (delimiter_count + 1) + (delimiter_count + 1) / 5;
        try self.buffer.ensureTotalCapacity(self.buffer.items.len + estimated_tokens);

        var start: usize = 0;
        var token_count: usize = 0;
        const max_tokens_per_chunk = 10000; // Safety limit to prevent runaway tokenization

        while (start < chunk.len and token_count < max_tokens_per_chunk) {
            // Skip leading delimiters efficiently
            while (start < chunk.len and std.mem.indexOfScalar(u8, delimiters, chunk[start]) != null) {
                start += 1;
            }

            if (start >= chunk.len) break;

            // Find next delimiter using fast batch search
            const token_end = if (std.mem.indexOfAny(u8, chunk[start..], delimiters)) |pos|
                start + pos
            else
                chunk.len;

            if (token_end > start) {
                // ZERO-ALLOCATION: Use string slice instead of dupe()
                const text = chunk[start..token_end];

                const token = Token.simple(.{
                    .start = self.position + start,
                    .end = self.position + token_end,
                }, .identifier, text, 0);

                // Use appendAssumeCapacity since we pre-allocated
                self.buffer.appendAssumeCapacity(token);
                token_count += 1;
            }

            start = token_end;
        }

        // Log warning if we hit safety limits (should not happen in normal use)
        if (token_count >= max_tokens_per_chunk) {
            std.log.warn("TokenIterator: Hit maximum tokens per chunk limit ({}), input may be malformed", .{max_tokens_per_chunk});
        }
    }
};

/// Stateless streaming lexer adapter for JsonLexer
pub const JsonLexerAdapter = struct {
    options: @import("../../languages/json/lexer.zig").JsonLexer.LexerOptions,

    const Self = @This();
    const JsonLexer = @import("../../languages/json/lexer.zig").JsonLexer;

    pub fn init(options: JsonLexer.LexerOptions) Self {
        return Self{ .options = options };
    }

    pub fn tokenizeChunk(self: *Self, input: []const u8, start_pos: usize, allocator: std.mem.Allocator) ![]Token {
        var lexer = JsonLexer.init(allocator, input, self.options);
        defer lexer.deinit();

        const tokens = try lexer.tokenize();

        // Adjust token positions for the start_pos offset
        for (tokens) |*token| {
            token.span.start += start_pos;
            token.span.end += start_pos;
        }

        return tokens;
    }

    pub fn deinit(self: *Self) void {
        _ = self; // No cleanup needed for stateless adapter
    }
};

/// Stateless streaming lexer adapter for ZonLexer
pub const ZonLexerAdapter = struct {
    options: @import("../../languages/zon/lexer.zig").ZonLexer.LexerOptions,

    const Self = @This();
    const ZonLexer = @import("../../languages/zon/lexer.zig").ZonLexer;

    pub fn init(options: ZonLexer.LexerOptions) Self {
        return Self{ .options = options };
    }

    pub fn tokenizeChunk(self: *Self, input: []const u8, start_pos: usize, allocator: std.mem.Allocator) ![]Token {
        var lexer = ZonLexer.init(allocator, input, self.options);
        defer lexer.deinit();

        const tokens = try lexer.tokenize();

        // Adjust token positions for the start_pos offset
        for (tokens) |*token| {
            token.span.start += start_pos;
            token.span.end += start_pos;
        }

        return tokens;
    }

    pub fn deinit(self: *Self) void {
        _ = self; // No cleanup needed for stateless adapter
    }
};

/// Convenience functions for creating TokenIterator with real lexers
pub fn createJsonTokenIterator(allocator: std.mem.Allocator, input: []const u8, context: *Context, options: @import("../../languages/json/lexer.zig").JsonLexer.LexerOptions) !TokenIterator {
    var adapter = JsonLexerAdapter.init(options);
    const lexer_interface = TokenIterator.LexerInterface.init(&adapter);
    return TokenIterator.init(allocator, input, context, lexer_interface);
}

pub fn createZonTokenIterator(allocator: std.mem.Allocator, input: []const u8, context: *Context, options: @import("../../languages/zon/lexer.zig").ZonLexer.LexerOptions) !TokenIterator {
    var adapter = ZonLexerAdapter.init(options);
    const lexer_interface = TokenIterator.LexerInterface.init(&adapter);
    return TokenIterator.init(allocator, input, context, lexer_interface);
}

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
        // EOF tokens can have empty text, skip that check
        if (token.kind != .eof) {
            try testing.expect(token.text.len > 0);
        }
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

test "TokenIterator - high token density" {
    var context = Context.init(testing.allocator);
    defer context.deinit();

    // High token density: many short tokens separated by single spaces
    const input = "a b c d e f g h i j k l m n o p q r s t u v w x y z";
    var iterator = TokenIterator.init(testing.allocator, input, &context, null);
    defer iterator.deinit();

    // Set small chunk size to test capacity estimation with dense tokens
    iterator.setChunkSize(10);

    var token_count: usize = 0;
    while (try iterator.next()) |token| {
        token_count += 1;
        // EOF tokens can have empty text, skip that check
        if (token.kind != .eof) {
            try testing.expect(token.text.len > 0);
        }
    }

    try testing.expect(token_count == 26); // 26 single-letter tokens
    try testing.expect(iterator.isEof());
}

test "TokenIterator - low token density" {
    var context = Context.init(testing.allocator);
    defer context.deinit();

    // Low token density: tokens that will be split at chunk boundaries
    const input = "word1      word2      word3";
    var iterator = TokenIterator.init(testing.allocator, input, &context, null);
    defer iterator.deinit();

    // Set small chunk size to test capacity estimation with sparse tokens
    iterator.setChunkSize(12);

    var token_count: usize = 0;
    while (try iterator.next()) |token| {
        token_count += 1;
        // EOF tokens can have empty text, skip that check
        if (token.kind != .eof) {
            try testing.expect(token.text.len > 0);
        }
    }

    // We expect exactly 3 tokens since they're separated by whitespace at good breaking points
    try testing.expect(token_count == 3);
    try testing.expect(iterator.isEof());
}

test "TokenIterator - mixed token density" {
    var context = Context.init(testing.allocator);
    defer context.deinit();

    // Mixed: some dense areas, some sparse areas that break cleanly on whitespace
    const input = "a b c   word   d e f g   another   h i j";
    var iterator = TokenIterator.init(testing.allocator, input, &context, null);
    defer iterator.deinit();

    iterator.setChunkSize(12);

    var token_count: usize = 0;
    var short_tokens: usize = 0;
    var medium_tokens: usize = 0;

    while (try iterator.next()) |token| {
        token_count += 1;
        if (token.text.len == 1) {
            short_tokens += 1;
        } else if (token.text.len > 3) {
            medium_tokens += 1;
        }
    }

    // Actual output: a b c word d e f g another h i j (12 tokens total)
    try testing.expect(token_count == 12);
    try testing.expect(short_tokens == 10); // Single-letter tokens: a b c d e f g h i j
    try testing.expect(medium_tokens == 2); // "word" and "another"
    try testing.expect(iterator.isEof());
}

test "TokenIterator - extreme density with tiny chunks" {
    var context = Context.init(testing.allocator);
    defer context.deinit();

    // Extreme case: every character is a token (worst case for capacity estimation)
    const input = "1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0";
    var iterator = TokenIterator.init(testing.allocator, input, &context, null);
    defer iterator.deinit();

    // Very small chunks to stress-test capacity estimation
    iterator.setChunkSize(5);

    var token_count: usize = 0;
    while (try iterator.next()) |token| {
        token_count += 1;
        try testing.expect(token.text.len == 1); // Each should be single digit
    }

    try testing.expect(token_count == 20); // 20 single-digit tokens
    try testing.expect(iterator.isEof());
}

test "TokenIterator - JSON lexer adapter" {
    var context = Context.init(testing.allocator);
    defer context.deinit();

    // Simple JSON that should be tokenized properly by JSON lexer
    const input = "{\"name\": \"Alice\", \"age\": 30, \"active\": true}";

    var adapter = JsonLexerAdapter.init(.{
        .allow_comments = false,
        .allow_trailing_commas = false,
    });
    defer adapter.deinit();

    const lexer_interface = TokenIterator.LexerInterface.init(&adapter);
    var iterator = TokenIterator.init(testing.allocator, input, &context, lexer_interface);
    defer iterator.deinit();

    // Use reasonably sized chunks for JSON
    iterator.setChunkSize(20);

    var token_count: usize = 0;
    var brace_count: usize = 0;
    var string_count: usize = 0;

    while (try iterator.next()) |token| {
        token_count += 1;
        // EOF tokens can have empty text, skip that check
        if (token.kind != .eof) {
            try testing.expect(token.text.len > 0);
        }

        // Count different token types (skip empty tokens like EOF)
        if (token.text.len > 0) {
            if (std.mem.eql(u8, token.text, "{") or std.mem.eql(u8, token.text, "}")) {
                brace_count += 1;
            } else if (token.text[0] == '"' and token.text[token.text.len - 1] == '"') {
                string_count += 1;
            }
        }
    }

    try testing.expect(token_count > 10); // Should have many tokens for JSON
    try testing.expect(brace_count >= 2); // Should have opening and closing braces
    try testing.expect(string_count >= 3); // Should have at least 3 string tokens ("name", "Alice", "active")
    try testing.expect(iterator.isEof());
}

test "TokenIterator - ZON lexer adapter" {
    var context = Context.init(testing.allocator);
    defer context.deinit();

    // Simple ZON content
    const input = ".{ .name = \"Alice\", .age = 30, .active = true }";

    var adapter = ZonLexerAdapter.init(.{
        .preserve_comments = true,
    });
    defer adapter.deinit();

    const lexer_interface = TokenIterator.LexerInterface.init(&adapter);
    var iterator = TokenIterator.init(testing.allocator, input, &context, lexer_interface);
    defer iterator.deinit();

    // Use reasonable chunk size for the test
    iterator.setChunkSize(60);

    var token_count: usize = 0;
    var field_count: usize = 0;
    var boolean_found: bool = false;

    while (try iterator.next()) |token| {
        token_count += 1;

        // EOF tokens can have empty text, skip that check
        if (token.kind != .eof) {
            try testing.expect(token.text.len > 0);
        }

        // Count identifier tokens (field names like "name", "age", "active")
        if (token.kind == .identifier) {
            field_count += 1;
        }

        // Check for boolean_literal token kind
        if (token.kind == .boolean_literal) {
            boolean_found = true;
        }
    }

    try testing.expect(token_count > 10); // Should have many tokens for ZON
    try testing.expect(field_count >= 3); // Should have .name, .age, .active fields
    try testing.expect(boolean_found); // Should find the boolean_literal for "true"
    try testing.expect(iterator.isEof());
}

test "TokenIterator - real lexers vs fallback comparison" {
    var context = Context.init(testing.allocator);
    defer context.deinit();

    const json_input = "{\"name\": \"Alice\", \"active\": true, \"score\": null}";

    // Test JSON with real lexer
    var json_adapter = JsonLexerAdapter.init(.{});
    defer json_adapter.deinit();

    const json_lexer_interface = TokenIterator.LexerInterface.init(&json_adapter);
    var json_iterator = TokenIterator.init(testing.allocator, json_input, &context, json_lexer_interface);
    defer json_iterator.deinit();

    var json_real_tokens: usize = 0;
    var json_boolean_found: bool = false;
    var json_null_found: bool = false;

    while (try json_iterator.next()) |token| {
        json_real_tokens += 1;
        if (token.kind == .boolean_literal) json_boolean_found = true;
        if (token.kind == .null_literal) json_null_found = true;
    }

    // Test JSON with fallback tokenizer
    var json_fallback = TokenIterator.init(testing.allocator, json_input, &context, null);
    defer json_fallback.deinit();

    var json_fallback_tokens: usize = 0;
    while (try json_fallback.next()) |token| {
        json_fallback_tokens += 1;
        // Fallback only produces generic identifiers, not specific literals
        try testing.expect(token.kind == .identifier);
    }

    // Real lexer should produce more accurate tokens
    try testing.expect(json_real_tokens > json_fallback_tokens); // Real lexer produces more specific tokens
    try testing.expect(json_boolean_found); // Real lexer recognizes boolean_literal
    try testing.expect(json_null_found); // Real lexer recognizes null_literal

    // Test ZON comparison
    const zon_input = ".{ .count = 42, .enabled = true }";

    // ZON with real lexer
    var zon_adapter = ZonLexerAdapter.init(.{});
    defer zon_adapter.deinit();

    const zon_lexer_interface = TokenIterator.LexerInterface.init(&zon_adapter);
    var zon_iterator = TokenIterator.init(testing.allocator, zon_input, &context, zon_lexer_interface);
    defer zon_iterator.deinit();

    var zon_real_tokens: usize = 0;
    var zon_boolean_found: bool = false;
    var zon_number_found: bool = false;

    while (try zon_iterator.next()) |token| {
        zon_real_tokens += 1;
        if (token.kind == .boolean_literal) zon_boolean_found = true;
        if (token.kind == .number_literal) zon_number_found = true;
    }

    // ZON with fallback
    var zon_fallback = TokenIterator.init(testing.allocator, zon_input, &context, null);
    defer zon_fallback.deinit();

    var zon_fallback_tokens: usize = 0;
    while (try zon_fallback.next()) |_| {
        zon_fallback_tokens += 1;
    }

    // Real ZON lexer should be much more accurate
    try testing.expect(zon_real_tokens > zon_fallback_tokens);
    try testing.expect(zon_boolean_found); // Real lexer recognizes boolean_literal
    try testing.expect(zon_number_found); // Real lexer recognizes number_literal
}
