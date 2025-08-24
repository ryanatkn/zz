/// Lexer Module - JSON streaming lexer
/// Zero-allocation streaming tokenization with boundary handling

// Core lexer functionality
pub const StreamLexer = @import("core.zig").JsonStreamLexer;
pub const LexerState = @import("core.zig").LexerState;

// Boundary handling functions
pub const feedData = @import("boundaries.zig").feedData;
pub const peek = @import("boundaries.zig").peek;
pub const continueBoundaryToken = @import("boundaries.zig").continueBoundaryToken;

// Backward compatibility exports
pub const JsonStreamLexer = StreamLexer;
