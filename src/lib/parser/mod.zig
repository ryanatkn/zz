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
// Re-export AST types when they exist
// ============================================================================

// TODO: Will be available when AST module is implemented
// pub const Node = @import("../ast/mod.zig").Node;
// pub const Visitor = @import("../ast/mod.zig").Visitor;