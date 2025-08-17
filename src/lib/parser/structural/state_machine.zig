const std = @import("std");
const Token = @import("../lexical/mod.zig").Token;
const TokenKind = @import("../lexical/mod.zig").TokenKind;
const Language = @import("../lexical/mod.zig").Language;
const BoundaryKind = @import("../foundation/types/predicate.zig").BoundaryKind;

/// Parsing states for structural boundary detection
/// Optimized for O(1) state transitions and branch prediction
pub const ParseState = enum(u8) {
    // Global states
    top_level = 0,           // At module/file scope
    error_recovery = 1,      // Recovering from parse error
    
    // Zig-specific states  
    function_signature = 10,  // Inside function signature
    function_body = 11,      // Inside function body
    struct_signature = 12,   // Inside struct signature
    struct_body = 13,        // Inside struct body
    enum_signature = 14,     // Inside enum signature
    enum_body = 15,          // Inside enum body
    block = 16,              // Inside code block
    expression = 17,         // Inside expression
    comment = 18,            // Inside comment block
    string_literal = 19,     // Inside string literal
    
    // Generic states (for other languages)
    class_signature = 30,    // Inside class signature
    class_body = 31,         // Inside class body
    method_signature = 32,   // Inside method signature
    method_body = 33,        // Inside method body
    
    /// Get the boundary kind this state represents (if any)
    pub fn toBoundaryKind(self: ParseState) ?BoundaryKind {
        return switch (self) {
            .function_signature, .function_body => .function,
            .struct_signature, .struct_body => .struct_,
            .enum_signature, .enum_body => .enum_,
            .class_signature, .class_body => .class,
            .method_signature, .method_body => .function,
            .block => .block,
            else => null,
        };
    }
    
    /// Check if this state represents a boundary
    pub fn isBoundary(self: ParseState) bool {
        return self.toBoundaryKind() != null;
    }
    
    /// Check if this state represents an error state
    pub fn isError(self: ParseState) bool {
        return self == .error_recovery;
    }
    
    /// Check if this state represents a signature (vs body)
    pub fn isSignature(self: ParseState) bool {
        return switch (self) {
            .function_signature, .struct_signature, .enum_signature,
            .class_signature, .method_signature => true,
            else => false,
        };
    }
};

/// State transition result
pub const StateTransition = struct {
    /// New state after transition
    new_state: ParseState,
    
    /// Whether a boundary was detected
    boundary_detected: bool,
    
    /// Whether this transition indicates an error
    is_error: bool,
    
    /// Confidence level for this transition (0.0 to 1.0)
    confidence: f32,
    
    pub fn success(new_state: ParseState) StateTransition {
        return .{
            .new_state = new_state,
            .boundary_detected = false,
            .is_error = false,
            .confidence = 1.0,
        };
    }
    
    pub fn boundary(new_state: ParseState, confidence: f32) StateTransition {
        return .{
            .new_state = new_state,
            .boundary_detected = true,
            .is_error = false,
            .confidence = confidence,
        };
    }
    
    pub fn error_transition(recovery_state: ParseState) StateTransition {
        return .{
            .new_state = recovery_state,
            .boundary_detected = false,
            .is_error = true,
            .confidence = 0.5,
        };
    }
};

/// Parsing context for state machine
pub const ParseContext = struct {
    /// Current parsing state
    current_state: ParseState,
    
    /// Previous state (for recovery)
    previous_state: ParseState,
    
    /// Current bracket depth
    bracket_depth: u16,
    
    /// Current indentation level
    indent_level: u16,
    
    /// Whether we're inside a string/comment
    in_trivia: bool,
    
    /// Language-specific context
    language: Language,
    
    /// Error count for recovery decisions
    error_count: u16,
    
    pub fn init(language: Language) ParseContext {
        return .{
            .current_state = .top_level,
            .previous_state = .top_level,
            .bracket_depth = 0,
            .indent_level = 0,
            .in_trivia = false,
            .language = language,
            .error_count = 0,
        };
    }
    
    /// Reset context to initial state
    pub fn reset(self: *ParseContext) void {
        self.current_state = .top_level;
        self.previous_state = .top_level;
        self.bracket_depth = 0;
        self.indent_level = 0;
        self.in_trivia = false;
        self.error_count = 0;
    }
    
    /// Enter error recovery mode
    pub fn enterErrorRecovery(self: *ParseContext) void {
        self.previous_state = self.current_state;
        self.current_state = .error_recovery;
        self.error_count += 1;
    }
    
    /// Exit error recovery mode
    pub fn exitErrorRecovery(self: *ParseContext, new_state: ParseState) void {
        self.current_state = new_state;
        // Keep previous_state for potential re-entry
    }
};

/// High-performance state machine for structural parsing
/// Uses transition tables for O(1) state changes
pub const StateMachine = struct {
    /// Parsing context
    context: ParseContext,
    
    /// Transition table for fast lookups
    /// [current_state][token_kind] -> transition
    transition_table: [256][32]?StateTransition,
    
    /// Allocator for state management
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, language: Language) StateMachine {
        var machine = StateMachine{
            .context = ParseContext.init(language),
            .transition_table = std.mem.zeroes([256][32]?StateTransition),
            .allocator = allocator,
        };
        
        machine.buildTransitionTable();
        return machine;
    }
    
    pub fn deinit(self: *StateMachine) void {
        _ = self;
        // No cleanup needed for transition table
    }
    
    /// Process a token and return state transition
    pub fn processToken(self: *StateMachine, token: Token) StateTransition {
        // Update bracket depth and trivia status
        self.updateContextFromToken(token);
        
        // Check for error recovery exit conditions
        if (self.context.current_state == .error_recovery) {
            if (self.shouldExitErrorRecovery(token)) {
                const recovery_state = self.getRecoveryState(token);
                self.context.exitErrorRecovery(recovery_state);
                return StateTransition.success(recovery_state);
            }
            return StateTransition.success(.error_recovery);
        }
        
        // Check for keyword-specific transitions first (token text matters)
        if (token.kind == .keyword) {
            if (self.processKeywordToken(token)) |transition| {
                self.applyTransition(transition);
                return transition;
            }
        }
        
        // Look up transition in table for non-keywords
        const state_idx = @intFromEnum(self.context.current_state);
        const token_idx = @intFromEnum(token.kind);
        if (self.transition_table[state_idx][token_idx]) |transition| {
            self.applyTransition(transition);
            return transition;
        }
        
        // No transition found - check for error condition
        if (self.isUnexpectedToken(token)) {
            self.context.enterErrorRecovery();
            return StateTransition.error_transition(.error_recovery);
        }
        
        // Default to staying in current state
        return StateTransition.success(self.context.current_state);
    }
    
    /// Get current parsing state
    pub fn getCurrentState(self: StateMachine) ParseState {
        return self.context.current_state;
    }
    
    /// Get current bracket depth
    pub fn getBracketDepth(self: StateMachine) u16 {
        return self.context.bracket_depth;
    }
    
    /// Check if currently in error recovery
    pub fn isInErrorRecovery(self: StateMachine) bool {
        return self.context.current_state == .error_recovery;
    }
    
    /// Reset state machine to initial state
    pub fn reset(self: *StateMachine) void {
        self.context.reset();
    }
    
    // ========================================================================
    // Private Implementation
    // ========================================================================
    
    /// Process keyword token with text-based matching
    fn processKeywordToken(self: *StateMachine, token: Token) ?StateTransition {
        switch (self.context.language) {
            .zig => return self.processZigKeyword(token),
            .typescript => return self.processTypeScriptKeyword(token),
            else => return null,
        }
    }
    
    /// Process Zig-specific keywords
    fn processZigKeyword(self: *StateMachine, token: Token) ?StateTransition {
        if (self.context.current_state != .top_level) return null;
        
        if (std.mem.eql(u8, token.text, "fn")) {
            return StateTransition.boundary(.function_signature, 0.95);
        } else if (std.mem.eql(u8, token.text, "struct")) {
            return StateTransition.boundary(.struct_signature, 0.95);
        } else if (std.mem.eql(u8, token.text, "enum")) {
            return StateTransition.boundary(.enum_signature, 0.95);
        }
        
        return null;
    }
    
    /// Process TypeScript-specific keywords
    fn processTypeScriptKeyword(self: *StateMachine, token: Token) ?StateTransition {
        if (self.context.current_state != .top_level) return null;
        
        if (std.mem.eql(u8, token.text, "function")) {
            return StateTransition.boundary(.function_signature, 0.9);
        } else if (std.mem.eql(u8, token.text, "class")) {
            return StateTransition.boundary(.class_signature, 0.9);
        }
        
        return null;
    }
    
    /// Build transition table for fast state lookups
    fn buildTransitionTable(self: *StateMachine) void {
        switch (self.context.language) {
            .zig => self.buildZigTransitions(),
            .typescript => self.buildTSTransitions(),
            .json => self.buildJSONTransitions(),
            else => self.buildGenericTransitions(),
        }
    }
    
    /// Build Zig-specific transition table
    fn buildZigTransitions(self: *StateMachine) void {
        // Keywords are now handled by processKeywordToken
        const open_brace_idx = @intFromEnum(TokenKind.delimiter); // "{"
        const close_brace_idx = @intFromEnum(TokenKind.delimiter); // "}"
        _ = @intFromEnum(TokenKind.delimiter); // open_paren_idx - unused for now
        _ = @intFromEnum(TokenKind.delimiter); // close_paren_idx - unused for now
        
        // Function signature -> body
        const fn_sig_idx = @intFromEnum(ParseState.function_signature);
        self.transition_table[fn_sig_idx][open_brace_idx] = StateTransition.boundary(.function_body, 0.9);
        
        // Function body -> top level
        const fn_body_idx = @intFromEnum(ParseState.function_body);
        self.transition_table[fn_body_idx][close_brace_idx] = StateTransition.boundary(.top_level, 0.9);
        
        // Struct signature -> body
        const struct_sig_idx = @intFromEnum(ParseState.struct_signature);
        self.transition_table[struct_sig_idx][open_brace_idx] = StateTransition.boundary(.struct_body, 0.9);
        
        // Struct body -> top level
        const struct_body_idx = @intFromEnum(ParseState.struct_body);
        self.transition_table[struct_body_idx][close_brace_idx] = StateTransition.boundary(.top_level, 0.9);
        
        // Block handling for nested scopes
        self.transition_table[fn_body_idx][open_brace_idx] = StateTransition.boundary(.block, 0.8);
        const block_idx = @intFromEnum(ParseState.block);
        self.transition_table[block_idx][close_brace_idx] = StateTransition.success(.function_body);
    }
    
    /// Build TypeScript transition table
    fn buildTSTransitions(self: *StateMachine) void {
        _ = self;
        // Keywords are now handled by processKeywordToken
        // Non-keyword transitions for TypeScript would go here
    }
    
    /// Build JSON transition table (simpler)
    fn buildJSONTransitions(self: *StateMachine) void {
        const open_brace_idx = @intFromEnum(TokenKind.delimiter); // "{"
        const close_brace_idx = @intFromEnum(TokenKind.delimiter); // "}"
        
        const top_level_idx = @intFromEnum(ParseState.top_level);
        self.transition_table[top_level_idx][open_brace_idx] = StateTransition.boundary(.block, 0.95);
        
        const block_idx = @intFromEnum(ParseState.block);
        self.transition_table[block_idx][close_brace_idx] = StateTransition.boundary(.top_level, 0.95);
    }
    
    /// Build generic transition table
    fn buildGenericTransitions(self: *StateMachine) void {
        // Basic brace-based block detection
        const open_brace_idx = @intFromEnum(TokenKind.delimiter);
        const close_brace_idx = @intFromEnum(TokenKind.delimiter);
        
        const top_level_idx = @intFromEnum(ParseState.top_level);
        self.transition_table[top_level_idx][open_brace_idx] = StateTransition.boundary(.block, 0.7);
        
        const block_idx = @intFromEnum(ParseState.block);
        self.transition_table[block_idx][close_brace_idx] = StateTransition.boundary(.top_level, 0.7);
    }
    
    /// Update context based on token content
    fn updateContextFromToken(self: *StateMachine, token: Token) void {
        // Update bracket depth from token
        self.context.bracket_depth = token.bracket_depth;
        
        // Update trivia status
        self.context.in_trivia = switch (token.kind) {
            .comment, .whitespace => true,
            else => false,
        };
        
        // Could add indentation tracking here
    }
    
    /// Apply state transition to context
    fn applyTransition(self: *StateMachine, transition: StateTransition) void {
        if (transition.is_error) {
            self.context.enterErrorRecovery();
        } else {
            self.context.previous_state = self.context.current_state;
            self.context.current_state = transition.new_state;
        }
    }
    
    /// Check if we should exit error recovery
    fn shouldExitErrorRecovery(self: StateMachine, token: Token) bool {
        // Exit on balanced braces or specific recovery tokens
        _ = self;
        return switch (token.kind) {
            .delimiter => true, // Braces, parens might indicate recovery
            .keyword => true,   // Keywords usually indicate structure
            else => false,
        };
    }
    
    /// Get recovery state based on current context
    fn getRecoveryState(self: StateMachine, token: Token) ParseState {
        _ = token;
        
        // Simple recovery: go back to previous state or top level
        if (self.context.bracket_depth == 0) {
            return .top_level;
        } else {
            return self.context.previous_state;
        }
    }
    
    /// Check if token is unexpected in current state
    fn isUnexpectedToken(self: StateMachine, token: Token) bool {
        // Check for mismatched brackets
        if (token.kind == .delimiter) {
            // Check if closing bracket without matching open
            if (token.text.len == 1) {
                const ch = token.text[0];
                switch (ch) {
                    ')', ']', '}' => {
                        // Closing bracket - check if we have matching open
                        // For now, just check bracket depth
                        if (self.context.bracket_depth == 0) {
                            return true; // Unexpected closing bracket
                        }
                    },
                    else => {},
                }
            }
        }
        
        // Check for specific state violations
        switch (self.context.current_state) {
            .function_signature => {
                // After opening paren, expect params or closing paren
                if (self.context.bracket_depth > 0 and token.kind == .delimiter and token.text[0] == '{') {
                    return true; // Opening brace without closing paren
                }
            },
            else => {},
        }
        
        return false;
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "state machine initialization" {
    var machine = StateMachine.init(testing.allocator, .zig);
    defer machine.deinit();
    
    try testing.expectEqual(ParseState.top_level, machine.getCurrentState());
    try testing.expectEqual(@as(u16, 0), machine.getBracketDepth());
    try testing.expect(!machine.isInErrorRecovery());
}

test "state transitions" {
    var machine = StateMachine.init(testing.allocator, .zig);
    defer machine.deinit();
    
    // Create a mock function token
    const Span = @import("../foundation/types/span.zig").Span;
    const span = Span.init(0, 2);
    const fn_token = Token.simple(span, .keyword, "fn", 0);
    
    const transition = machine.processToken(fn_token);
    try testing.expect(transition.boundary_detected);
    try testing.expectEqual(ParseState.function_signature, machine.getCurrentState());
}

test "error recovery" {
    var machine = StateMachine.init(testing.allocator, .zig);
    defer machine.deinit();
    
    // Force into error recovery
    machine.context.enterErrorRecovery();
    try testing.expect(machine.isInErrorRecovery());
    
    // Recovery should eventually exit
    const Span = @import("../foundation/types/span.zig").Span;
    const span = Span.init(0, 1);
    const brace_token = Token.simple(span, .delimiter, "}", 0);
    
    _ = machine.processToken(brace_token);
    // Should exit error recovery (exact state depends on recovery logic)
}