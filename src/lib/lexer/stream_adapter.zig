/// StreamAdapter - Converts lexer output to Stream(StreamToken)
///
/// TODO: Direct streaming from source without intermediate ArrayList
/// TODO: Incremental lexing support for edits
/// TODO: Parallel tokenization for large files
/// TODO: Memory-mapped file support for zero-copy lexing
const std = @import("std");
const Stream = @import("../stream/mod.zig").Stream;
const StreamToken = @import("../token/stream_token.zig").StreamToken;
const RingBuffer = @import("../stream/mod.zig").RingBuffer;
const LexerBridge = @import("lexer_bridge.zig").LexerBridge;
const StreamError = @import("../stream/error.zig").StreamError;

/// Adapts lexer output to streaming interface
pub const StreamAdapter = struct {
    tokens: []const StreamToken,
    position: usize,
    
    // TODO: Add lookahead buffer for peek operations
    // TODO: Consider using RingBuffer for better memory locality
    lookahead: RingBuffer(StreamToken, 16),
    
    // TODO: Add support for incremental updates
    // edit_list: ?[]Edit,
    // last_edit_position: usize,
    
    const Self = @This();
    
    /// Initialize adapter with tokens
    pub fn init(tokens: []const StreamToken) StreamAdapter {
        return .{
            .tokens = tokens,
            .position = 0,
            .lookahead = RingBuffer(StreamToken, 16).init(),
        };
    }
    
    /// Create a Stream from this adapter
    pub fn toStream(self: *Self) Stream(StreamToken) {
        return Stream(StreamToken){
            .ptr = self,
            .vtable = &stream_vtable,
        };
    }
    
    /// Stream vtable implementation
    const stream_vtable = Stream(StreamToken).VTable{
        .nextFn = next,
        .peekFn = peek,
        .skipFn = skip,
        .closeFn = close,
        .getPositionFn = getPosition,
        .isExhaustedFn = isExhausted,
    };
    
    fn next(ptr: *anyopaque) StreamError!?StreamToken {
        const self = @as(*Self, @ptrCast(@alignCast(ptr)));
        
        // Check lookahead buffer first
        if (self.lookahead.pop()) |token| {
            return token;
        }
        
        // Get next token from array
        if (self.position < self.tokens.len) {
            const token = self.tokens[self.position];
            self.position += 1;
            return token;
        }
        
        return null;
    }
    
    fn peek(ptr: *const anyopaque) StreamError!?StreamToken {
        const self = @as(*const Self, @ptrCast(@alignCast(ptr)));
        
        // Check lookahead buffer
        if (self.lookahead.peek()) |token| {
            return token;
        }
        
        // Peek at next token
        if (self.position < self.tokens.len) {
            const token = self.tokens[self.position];
            // Can't modify const self, so we need a different approach
            // TODO: Fix this to work with const self
            return token;
        }
        
        return null;
    }
    
    fn skip(ptr: *anyopaque, n: usize) StreamError!void {
        const self = @as(*Self, @ptrCast(@alignCast(ptr)));
        
        // Skip buffered tokens first
        var remaining = n;
        while (remaining > 0 and self.lookahead.pop() != null) {
            remaining -= 1;
        }
        
        // Skip remaining from main array
        self.position = @min(self.position + remaining, self.tokens.len);
    }
    
    fn close(ptr: *anyopaque) void {
        const self = @as(*Self, @ptrCast(@alignCast(ptr)));
        // TODO: Add cleanup if needed
        _ = self;
    }
    
    fn getPosition(ptr: *const anyopaque) usize {
        const self = @as(*const Self, @ptrCast(@alignCast(ptr)));
        return self.position;
    }
    
    fn isExhausted(ptr: *const anyopaque) bool {
        const self = @as(*const Self, @ptrCast(@alignCast(ptr)));
        return self.position >= self.tokens.len and self.lookahead.isEmpty();
    }
};

/// Streaming lexer that produces tokens on demand
/// TODO: Implement this for true streaming without full tokenization
pub const StreamingLexer = struct {
    source: []const u8,
    bridge: *LexerBridge,
    position: usize,
    buffer: RingBuffer(StreamToken, 256), // Larger buffer for batching
    
    // TODO: Add state machine for incremental lexing
    // state: LexerState,
    
    // TODO: Add error recovery
    // error_handler: ErrorHandler,
    
    const Self = @This();
    
    pub fn init(source: []const u8, bridge: *LexerBridge) StreamingLexer {
        return .{
            .source = source,
            .bridge = bridge,
            .position = 0,
            .buffer = RingBuffer(StreamToken, 256).init(),
        };
    }
    
    /// Create a Stream from this streaming lexer
    pub fn toStream(self: *Self) Stream(StreamToken) {
        return Stream(StreamToken){
            .ptr = self,
            .vtable = &streaming_vtable,
        };
    }
    
    const streaming_vtable = Stream(StreamToken).VTable{
        .nextFn = streamingNext,
        .peekFn = streamingPeek,
        .skipFn = streamingSkip,
        .closeFn = streamingClose,
        .getPositionFn = streamingGetPosition,
        .isExhaustedFn = streamingIsExhausted,
    };
    
    fn streamingNext(ptr: *anyopaque) StreamError!?StreamToken {
        const self = @as(*Self, @ptrCast(@alignCast(ptr)));
        
        // Check buffer first
        if (self.buffer.pop()) |token| {
            return token;
        }
        
        // TODO: Implement actual streaming tokenization
        // For now, we tokenize everything at once (not ideal)
        if (self.position == 0) {
            const tokens = self.bridge.tokenize(self.source) catch return null;
            defer self.bridge.allocator.free(tokens);
            
            // Fill buffer with tokens
            for (tokens) |token| {
                _ = self.buffer.push(token) catch break;
            }
            
            self.position = self.source.len; // Mark as consumed
        }
        
        return self.buffer.pop();
    }
    
    fn streamingPeek(ptr: *const anyopaque) StreamError!?StreamToken {
        const self = @as(*const Self, @ptrCast(@alignCast(ptr)));
        
        // Peek at buffer
        return self.buffer.peek();
    }
    
    fn streamingSkip(ptr: *anyopaque, n: usize) StreamError!void {
        const self = @as(*Self, @ptrCast(@alignCast(ptr)));
        
        var remaining = n;
        while (remaining > 0) {
            if (try streamingNext(ptr) == null) break;
            remaining -= 1;
        }
        _ = self;
    }
    
    fn streamingClose(ptr: *anyopaque) void {
        const self = @as(*Self, @ptrCast(@alignCast(ptr)));
        self.buffer.clear();
    }
    
    fn streamingGetPosition(ptr: *const anyopaque) usize {
        const self = @as(*const Self, @ptrCast(@alignCast(ptr)));
        return self.position;
    }
    
    fn streamingIsExhausted(ptr: *const anyopaque) bool {
        const self = @as(*const Self, @ptrCast(@alignCast(ptr)));
        return self.position >= self.source.len and self.buffer.isEmpty();
    }
};

test "StreamAdapter basic operations" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const AtomTable = @import("../memory/atom_table.zig").AtomTable;
    
    // Create atom table and bridge
    var atom_table = AtomTable.init(allocator);
    defer atom_table.deinit();
    
    var bridge = try LexerBridge.init(allocator, .json, &atom_table);
    defer bridge.deinit();
    
    // Tokenize some JSON
    const source = "[1, 2, 3]";
    const tokens = try bridge.tokenize(source);
    defer allocator.free(tokens);
    
    // Create adapter
    var adapter = StreamAdapter.init(tokens);
    var stream = adapter.toStream();
    
    // Test next
    const first = try stream.next();
    try testing.expect(first != null);
    
    // Test peek
    const peeked = try stream.peek();
    try testing.expect(peeked != null);
    
    // Verify peek doesn't advance
    const next = try stream.next();
    try testing.expectEqual(peeked, next);
    
    // Test skip
    try stream.skip(2);
    
    // Consume remaining
    var count: usize = 0;
    while (try stream.next()) |_| {
        count += 1;
    }
    
    // We should have consumed some tokens
    try testing.expect(count > 0);
    
    // TODO: Test streaming lexer
    // TODO: Test incremental updates
    // TODO: Test error recovery
    // TODO: Benchmark streaming vs batch
}