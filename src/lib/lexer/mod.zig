/// Lexer module - DEPRECATED
/// 
/// LexerBridge and StreamAdapter have been removed in Phase 6.
/// Use direct stream lexers (JsonStreamLexer, ZonStreamLexer) instead.
/// This module kept temporarily for LexerState only.
const std = @import("std");

// Only export remaining types
pub const LexerState = @import("state.zig").LexerState;

// Re-export for convenience
pub const Language = @import("../core/language.zig").Language;
pub const StreamToken = @import("../token/stream_token.zig").StreamToken;

test {
    _ = @import("state.zig");
}