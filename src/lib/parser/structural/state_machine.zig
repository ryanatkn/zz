const std = @import("std");
const Token = @import("../lexical/mod.zig").Token;
const TokenKind = @import("../lexical/mod.zig").TokenKind;
const Language = @import("../lexical/mod.zig").Language;
const DelimiterType = @import("../foundation/mod.zig").DelimiterType;
const BoundaryKind = @import("../foundation/types/predicate.zig").BoundaryKind;
const Span = @import("../foundation/types/span.zig").Span;

/// Parsing states for structural boundary detection
/// Optimized for O(1) state transitions and branch prediction
pub const ParseState = enum(u8) {
    // Global states
    top_level = 0, // At module/file scope
    error_recovery = 1, // Recovering from parse error

    // Zig-specific states
    function_signature = 10, // Inside function signature
    function_body = 11, // Inside function body
    struct_signature = 12, // Inside struct signature
    struct_body = 13, // Inside struct body
    enum_signature = 14, // Inside enum signature
    enum_body = 15, // Inside enum body
    block = 16, // Inside code block
    expression = 17, // Inside expression
    comment = 18, // Inside comment block
    string_literal = 19, // Inside string literal

    // Generic states (for other languages)
    class_signature = 30, // Inside class signature
    class_body = 31, // Inside class body
    method_signature = 32, // Inside method signature
    method_body = 33, // Inside method body

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
            .function_signature, .struct_signature, .enum_signature, .class_signature, .method_signature => true,
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

        // Check for delimiter-specific transitions (high performance)
        if (token.kind == .delimiter) {
            if (self.processDelimiterToken(token)) |transition| {
                self.applyTransition(transition);
                return transition;
            }
        }

        // Look up transition in table for non-keyword, non-delimiter tokens
        // (Currently unused - all languages use specialized process functions)
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

    /// Get previous parsing state
    pub fn getPreviousState(self: StateMachine) ParseState {
        return self.context.previous_state;
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
        // Only process keywords from top_level to ensure proper boundary detection
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

    /// Process delimiter token with high-performance DelimiterType switch
    /// Uses nested switch for O(1) state transitions with branch prediction optimization
    fn processDelimiterToken(self: *StateMachine, token: Token) ?StateTransition {
        const delim_type = token.getDelimiterType() orelse return null;

        return switch (delim_type) {
            .open_brace => switch (self.context.current_state) {
                .function_signature => StateTransition.boundary(.function_body, 0.9),
                .struct_signature => StateTransition.boundary(.struct_body, 0.9),
                .enum_signature => StateTransition.boundary(.enum_body, 0.9),
                .class_signature => StateTransition.boundary(.class_body, 0.9),
                .method_signature => StateTransition.boundary(.method_body, 0.9),
                .top_level => switch (self.context.language) {
                    .json => StateTransition.boundary(.block, 0.95),
                    else => null,
                },
                // Remove nested block handling for now to fix basic function detection
                else => null,
            },
            .close_brace => switch (self.context.current_state) {
                .function_body => StateTransition.boundary(.top_level, 0.9),
                .struct_body => StateTransition.boundary(.top_level, 0.9),
                .enum_body => StateTransition.boundary(.top_level, 0.9),
                .class_body => StateTransition.boundary(.top_level, 0.9),
                .method_body => StateTransition.boundary(.class_body, 0.9),
                .block => StateTransition.boundary(.top_level, 0.8), // Simplified: all blocks return to top_level
                else => switch (self.context.language) {
                    .json => StateTransition.boundary(.top_level, 0.95),
                    else => null,
                },
            },
            .open_paren => switch (self.context.current_state) {
                .function_signature, .method_signature => StateTransition.success(self.context.current_state), // Stay in signature, parsing params
                else => null,
            },
            .close_paren => switch (self.context.current_state) {
                .function_signature, .method_signature => StateTransition.success(self.context.current_state), // Stay in signature, waiting for brace
                else => null,
            },
            // Brackets and angles handled generically for now
            .open_bracket, .close_bracket, .open_angle, .close_angle => null,
        };
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
        // Keywords and delimiters are now handled by specialized process functions
        // Transition table only used for other token types if needed
        _ = self;
        // Currently no non-keyword, non-delimiter transitions for Zig
    }

    /// Build TypeScript transition table
    fn buildTSTransitions(self: *StateMachine) void {
        _ = self;
        // Keywords are now handled by processKeywordToken
        // Non-keyword transitions for TypeScript would go here
    }

    /// Build JSON transition table (simpler)
    fn buildJSONTransitions(self: *StateMachine) void {
        // JSON delimiter transitions handled by processDelimiterToken
        _ = self;
    }

    /// Build generic transition table
    fn buildGenericTransitions(self: *StateMachine) void {
        // Generic delimiter transitions handled by processDelimiterToken
        _ = self;
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
            .keyword => true, // Keywords usually indicate structure
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
    const span = Span.init(0, 2);
    const fn_token = Token.simple(span, .keyword, "fn", 0);

    const transition = machine.processToken(fn_token);
    try testing.expect(transition.boundary_detected);
    try testing.expectEqual(ParseState.function_signature, machine.getCurrentState());
}

test "complete function sequence" {
    var machine = StateMachine.init(testing.allocator, .zig);
    defer machine.deinit();

    // Test complete sequence: fn test() {}
    const fn_token = Token.simple(Span.init(0, 2), .keyword, "fn", 0);
    const name_token = Token.simple(Span.init(3, 7), .identifier, "test", 0);
    const open_paren = Token.simple(Span.init(7, 8), .delimiter, "(", 1);
    const close_paren = Token.simple(Span.init(8, 9), .delimiter, ")", 0);
    const open_brace = Token.simple(Span.init(10, 11), .delimiter, "{", 1);
    const close_brace = Token.simple(Span.init(12, 13), .delimiter, "}", 0);

    // fn -> function_signature
    var result = machine.processToken(fn_token);
    try testing.expect(result.boundary_detected);
    try testing.expectEqual(ParseState.function_signature, machine.getCurrentState());

    // test -> stay in function_signature
    result = machine.processToken(name_token);
    try testing.expectEqual(ParseState.function_signature, machine.getCurrentState());

    // ( -> stay in function_signature
    result = machine.processToken(open_paren);
    try testing.expectEqual(ParseState.function_signature, machine.getCurrentState());

    // ) -> stay in function_signature
    result = machine.processToken(close_paren);
    try testing.expectEqual(ParseState.function_signature, machine.getCurrentState());

    // { -> function_body
    result = machine.processToken(open_brace);
    try testing.expect(result.boundary_detected);
    try testing.expectEqual(ParseState.function_body, machine.getCurrentState());

    // } -> top_level
    result = machine.processToken(close_brace);
    try testing.expect(result.boundary_detected);
    try testing.expectEqual(ParseState.top_level, machine.getCurrentState());

    // Second function should work too
    const fn_token2 = Token.simple(Span.init(20, 22), .keyword, "fn", 0);
    result = machine.processToken(fn_token2);
    try testing.expect(result.boundary_detected);
    try testing.expectEqual(ParseState.function_signature, machine.getCurrentState());
}

test "error recovery" {
    var machine = StateMachine.init(testing.allocator, .zig);
    defer machine.deinit();

    // Force into error recovery
    machine.context.enterErrorRecovery();
    try testing.expect(machine.isInErrorRecovery());

    // Recovery should eventually exit
    const span = Span.init(0, 1);
    const brace_token = Token.simple(span, .delimiter, "}", 0);

    _ = machine.processToken(brace_token);
    // Should exit error recovery (exact state depends on recovery logic)
}
