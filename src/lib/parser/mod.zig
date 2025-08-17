const std = @import("std");

// ============================================================================
// Core Types - Main public API  
// ============================================================================

/// Simple recursive descent parser that generates AST from Grammar
pub const Parser = @import("parser.zig").Parser;

/// Parse context with position tracking and error reporting
pub const ParseContext = @import("context.zig").ParseContext;

// ============================================================================
// Parse Results and Errors
// ============================================================================

pub const ParseResult = @import("parser.zig").ParseResult;
pub const ParseError = @import("context.zig").ParseError;

// ============================================================================
// Stratified Parser Architecture - Phase 4 Complete
// ============================================================================

/// Foundation types for fact-based parsing
pub const Foundation = @import("foundation/mod.zig");

/// Lexical layer - Layer 0 (<0.1ms viewport tokenization)
pub const Lexical = @import("lexical/mod.zig");

/// Structural layer - Layer 1 (<1ms boundary detection) - PHASE 4 COMPLETE
pub const Structural = @import("structural/mod.zig");

// ============================================================================
// Convenience Re-exports for Stratified Parser
// ============================================================================

/// High-performance structural parser for boundary detection
pub const StructuralParser = @import("structural/mod.zig").StructuralParser;

/// Streaming lexer for viewport tokenization
pub const StreamingLexer = @import("lexical/mod.zig").StreamingLexer;

/// Core fact and span types
pub const Fact = @import("foundation/types/fact.zig").Fact;
pub const Span = @import("foundation/types/span.zig").Span;
pub const Token = @import("foundation/types/token.zig").Token;

// ============================================================================
// Re-export AST types when they exist
// ============================================================================

// TODO: Will be available when AST module is implemented
// pub const Node = @import("../ast/mod.zig").Node;
// pub const Visitor = @import("../ast/mod.zig").Visitor;