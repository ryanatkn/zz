/// Lexer Module - ZON streaming lexer
/// Zero-allocation streaming tokenization

// Core lexer functionality
pub const Lexer = @import("core.zig").Lexer;
pub const LexerState = @import("core.zig").LexerState;
pub const LexerOptions = @import("core.zig").LexerOptions;

// ZON-specific lexer functionality
pub const StatefulZonLexer = @import("core.zig").StatefulZonLexer;
