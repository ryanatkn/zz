/// Lexer module - PURE RE-EXPORTS ONLY
///
/// Unified lexer infrastructure for all language implementations.
/// This module contains NO implementations, only re-exports.

// Infrastructure components
pub const interface = @import("interface.zig");
pub const streaming = @import("streaming.zig");
pub const incremental = @import("incremental.zig");
pub const buffer = @import("buffer.zig");
pub const context = @import("context.zig");

// Convenience re-exports for common types
pub const LexerInterface = interface.LexerInterface;
pub const createInterface = interface.createInterface;

pub const TokenStream = streaming.TokenStream;
pub const createTokenStream = streaming.createTokenStream;

pub const Edit = incremental.Edit;
pub const TokenDelta = incremental.TokenDelta;
pub const IncrementalState = incremental.IncrementalState;

pub const StreamBuffer = buffer.StreamBuffer;
pub const LookaheadBuffer = buffer.LookaheadBuffer;

pub const LexerError = context.LexerError;
pub const ErrorDetail = context.ErrorDetail;
pub const LexerContext = context.LexerContext;
pub const LexerState = context.LexerState;
