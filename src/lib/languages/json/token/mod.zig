/// Token Module - JSON token types and utilities
/// Lightweight tokens optimized for streaming

// Core token types (removing Json prefix within module)
pub const Token = @import("types.zig").JsonToken;
pub const TokenKind = @import("types.zig").JsonTokenKind;
pub const TokenFlags = @import("types.zig").JsonTokenFlags;

// Token buffer for boundary handling
pub const TokenBuffer = @import("buffer.zig").TokenBuffer;
pub const TokenState = @import("buffer.zig").TokenState;
pub const TokenCompletion = @import("buffer.zig").TokenCompletion;
pub const BoundaryTester = @import("buffer.zig").BoundaryTester;

// Backward compatibility exports (keep Json prefix for external use)
pub const JsonToken = Token;
pub const JsonTokenKind = TokenKind;
pub const JsonTokenFlags = TokenFlags;
