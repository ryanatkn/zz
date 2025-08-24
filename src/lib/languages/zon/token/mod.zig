/// Token Module - ZON token types and utilities
/// Lightweight tokens optimized for streaming

// Core token types (following JSON pattern)
pub const Token = @import("types.zig").ZonToken;
pub const TokenKind = @import("types.zig").ZonTokenKind;
pub const TokenFlags = @import("types.zig").ZonTokenFlags;

// Keep ZON prefix available for clarity
pub const ZonToken = Token;
pub const ZonTokenKind = TokenKind;
pub const ZonTokenFlags = TokenFlags;
