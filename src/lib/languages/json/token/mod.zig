/// Token Module - JSON token types and utilities
/// Lightweight tokens optimized for streaming

// Core token types (clean names)
pub const Token = @import("types.zig").Token;
pub const TokenKind = @import("types.zig").TokenKind;
pub const TokenFlags = @import("types.zig").TokenFlags;

// Token buffer for boundary handling
pub const TokenBuffer = @import("buffer.zig").TokenBuffer;
pub const TokenState = @import("buffer.zig").TokenState;
pub const TokenCompletion = @import("buffer.zig").TokenCompletion;
pub const BoundaryTester = @import("buffer.zig").BoundaryTester;
