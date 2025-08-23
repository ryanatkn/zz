/// Token module - Simplified streaming token system
///
/// SIMPLIFIED: Only streaming tokens, no old infrastructure
/// Each language owns its token semantics completely

// Core components
pub const stream_token = @import("stream_token.zig");
pub const iterator = @import("iterator.zig");

// Main re-exports (new streaming system)
pub const StreamToken = stream_token.StreamToken;
pub const TokenIterator = iterator.TokenIterator;

// Old buffer utilities removed (data.zig, buffer.zig compatibility stubs deleted)
