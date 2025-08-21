/// LexerState - Shared state management for streaming lexers
///
/// TODO: Add support for incremental lexing with edit tracking
/// TODO: Consider thread-local state for parallel lexing
/// TODO: Add checkpointing for error recovery
const std = @import("std");

/// Lexer state for tracking position and context
pub const LexerState = struct {
    /// Current byte position in source
    position: usize = 0,
    
    /// Current line number (1-based)
    line: u32 = 1,
    
    /// Current column number (1-based)
    column: u32 = 1,
    
    /// Nesting depth for brackets/braces
    depth: u16 = 0,
    
    /// Context flags
    flags: StateFlags = .{},
    
    /// Stack for tracking nested contexts
    /// TODO: Make this configurable or growable
    context_stack: [32]ContextType = undefined,
    context_depth: u8 = 0,
    
    /// Previous character for lookback
    /// TODO: Consider multi-char lookback buffer
    prev_char: ?u8 = null,
    
    /// Statistics for performance monitoring
    /// TODO: Make this optional for release builds
    stats: StateStats = .{},
    
    pub const StateFlags = packed struct {
        in_string: bool = false,
        in_comment: bool = false,
        in_template: bool = false,
        in_regex: bool = false,
        has_errors: bool = false,
        // TODO: Add more language-specific flags
        _padding: u3 = 0,
    };
    
    pub const ContextType = enum(u8) {
        top_level,
        object,
        array,
        string,
        comment,
        template,
        regex,
        parentheses,
        // TODO: Add language-specific contexts
    };
    
    pub const StateStats = struct {
        bytes_processed: u64 = 0,
        lines_processed: u32 = 0,
        tokens_emitted: u64 = 0,
        errors_encountered: u32 = 0,
    };
    
    /// Initialize a new lexer state
    pub fn init() LexerState {
        return .{};
    }
    
    /// Reset state for reuse
    pub fn reset(self: *LexerState) void {
        self.* = init();
    }
    
    /// Advance position by n bytes
    pub fn advance(self: *LexerState, n: usize) void {
        self.position += n;
        self.column += @intCast(n);
        self.stats.bytes_processed += n;
    }
    
    /// Handle newline character
    pub fn newline(self: *LexerState) void {
        self.line += 1;
        self.column = 1;
        self.stats.lines_processed += 1;
        self.prev_char = '\n';
    }
    
    /// Push a new context onto the stack
    pub fn pushContext(self: *LexerState, context: ContextType) !void {
        if (self.context_depth >= self.context_stack.len) {
            // TODO: Grow the stack or handle overflow better
            return error.ContextStackOverflow;
        }
        self.context_stack[self.context_depth] = context;
        self.context_depth += 1;
    }
    
    /// Pop the current context
    pub fn popContext(self: *LexerState) ?ContextType {
        if (self.context_depth == 0) return null;
        self.context_depth -= 1;
        return self.context_stack[self.context_depth];
    }
    
    /// Get the current context
    pub fn currentContext(self: *const LexerState) ?ContextType {
        if (self.context_depth == 0) return null;
        return self.context_stack[self.context_depth - 1];
    }
    
    /// Enter a string context
    pub fn enterString(self: *LexerState) !void {
        self.flags.in_string = true;
        try self.pushContext(.string);
    }
    
    /// Exit a string context
    pub fn exitString(self: *LexerState) void {
        self.flags.in_string = false;
        _ = self.popContext();
    }
    
    /// Enter a comment context
    pub fn enterComment(self: *LexerState) !void {
        self.flags.in_comment = true;
        try self.pushContext(.comment);
    }
    
    /// Exit a comment context
    pub fn exitComment(self: *LexerState) void {
        self.flags.in_comment = false;
        _ = self.popContext();
    }
    
    /// Increment nesting depth
    pub fn increaseDepth(self: *LexerState) void {
        self.depth += 1;
    }
    
    /// Decrement nesting depth
    pub fn decreaseDepth(self: *LexerState) void {
        if (self.depth > 0) {
            self.depth -= 1;
        }
    }
    
    /// Record a token emission
    pub fn recordToken(self: *LexerState) void {
        self.stats.tokens_emitted += 1;
    }
    
    /// Record an error
    pub fn recordError(self: *LexerState) void {
        self.flags.has_errors = true;
        self.stats.errors_encountered += 1;
    }
    
    /// Create a checkpoint for backtracking
    /// TODO: Implement proper checkpointing
    pub fn checkpoint(self: *const LexerState) Checkpoint {
        return .{
            .position = self.position,
            .line = self.line,
            .column = self.column,
            .depth = self.depth,
            .flags = self.flags,
            .context_depth = self.context_depth,
        };
    }
    
    /// Restore from a checkpoint
    pub fn restore(self: *LexerState, cp: Checkpoint) void {
        self.position = cp.position;
        self.line = cp.line;
        self.column = cp.column;
        self.depth = cp.depth;
        self.flags = cp.flags;
        self.context_depth = cp.context_depth;
    }
    
    pub const Checkpoint = struct {
        position: usize,
        line: u32,
        column: u32,
        depth: u16,
        flags: StateFlags,
        context_depth: u8,
    };
};

/// Shared state for incremental lexing
/// TODO: Implement this for efficient re-lexing after edits
pub const IncrementalState = struct {
    /// Previous valid state at line boundaries
    line_states: std.ArrayList(LexerState),
    
    /// Edit history for incremental updates
    edits: std.ArrayList(Edit),
    
    /// Version number for cache invalidation
    version: u32 = 0,
    
    pub const Edit = struct {
        start: usize,
        end: usize,
        new_text: []const u8,
        version: u32,
    };
    
    pub fn init(allocator: std.mem.Allocator) IncrementalState {
        return .{
            .line_states = std.ArrayList(LexerState).init(allocator),
            .edits = std.ArrayList(Edit).init(allocator),
        };
    }
    
    pub fn deinit(self: *IncrementalState) void {
        self.line_states.deinit();
        self.edits.deinit();
    }
    
    /// Record an edit for incremental processing
    pub fn recordEdit(self: *IncrementalState, edit: Edit) !void {
        try self.edits.append(edit);
        self.version += 1;
    }
    
    /// Get the nearest valid state before position
    pub fn getNearestState(self: *IncrementalState, position: usize) ?LexerState {
        _ = self;
        _ = position;
        // TODO: Implement binary search for efficiency
        return null;
    }
};

test "LexerState basic operations" {
    const testing = std.testing;
    
    var state = LexerState.init();
    
    // Test initialization
    try testing.expectEqual(@as(usize, 0), state.position);
    try testing.expectEqual(@as(u32, 1), state.line);
    try testing.expectEqual(@as(u32, 1), state.column);
    
    // Test advance
    state.advance(5);
    try testing.expectEqual(@as(usize, 5), state.position);
    try testing.expectEqual(@as(u32, 6), state.column);
    
    // Test newline
    state.newline();
    try testing.expectEqual(@as(u32, 2), state.line);
    try testing.expectEqual(@as(u32, 1), state.column);
    
    // Test context stack
    try state.pushContext(.object);
    try testing.expectEqual(LexerState.ContextType.object, state.currentContext());
    
    try state.pushContext(.array);
    try testing.expectEqual(LexerState.ContextType.array, state.currentContext());
    
    _ = state.popContext();
    try testing.expectEqual(LexerState.ContextType.object, state.currentContext());
    
    // Test depth tracking
    state.increaseDepth();
    try testing.expectEqual(@as(u16, 1), state.depth);
    state.decreaseDepth();
    try testing.expectEqual(@as(u16, 0), state.depth);
    
    // Test string context
    try state.enterString();
    try testing.expect(state.flags.in_string);
    state.exitString();
    try testing.expect(!state.flags.in_string);
    
    // Test checkpointing
    const cp = state.checkpoint();
    state.advance(10);
    state.restore(cp);
    try testing.expectEqual(cp.position, state.position);
    
    // TODO: Test incremental state
    // TODO: Test error recovery
    // TODO: Test statistics tracking
}