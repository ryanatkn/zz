/// Token module - PURE RE-EXPORTS ONLY
///
/// Unified token system with lightweight representation and efficient dispatch.
/// This module contains NO implementations, only re-exports.

// Core components
pub const token = @import("token.zig");
pub const stream_token = @import("stream_token.zig");
pub const kind = @import("kind.zig");
pub const generic = @import("generic.zig");
pub const iterator = @import("iterator.zig");
pub const buffer = @import("buffer.zig");
pub const data = @import("data.zig");

// Convenience re-exports for common types
pub const Token = token.Token;
pub const TokenKind = token.TokenKind;
pub const TokenFlags = token.TokenFlags;

pub const TokenData = data.TokenData;
pub const TokenInterface = data.TokenInterface;

pub const StreamToken = stream_token.StreamToken;

pub const SimpleStreamToken = generic.SimpleStreamToken;

pub const TokenIterator = iterator.TokenIterator;

pub const TokenBuffer = buffer.TokenBuffer;
pub const LookaheadBuffer = buffer.LookaheadBuffer;

// Stream types for tokens
const stream_mod = @import("../stream/mod.zig");
pub const TokenStream = stream_mod.Stream(StreamToken);
pub const DirectTokenStream = stream_mod.DirectStream(StreamToken);

/// Create DirectStream from token slice
pub fn directTokenStream(tokens: []const StreamToken) DirectTokenStream {
    return stream_mod.directFromSlice(StreamToken, tokens);
}
