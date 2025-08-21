/// Lexer module - Bridge between old lexers and stream-first architecture
/// 
/// TODO: This is a transitional module for Phase 2
/// TODO: Will be replaced with pure stream-first lexers in Phase 4
/// TODO: Current implementation uses vtable dispatch for compatibility
/// TODO: Target: Direct StreamToken production without intermediate Token type
const std = @import("std");

// Export core lexer types
pub const LexerBridge = @import("lexer_bridge.zig").LexerBridge;
pub const StreamAdapter = @import("stream_adapter.zig").StreamAdapter;
pub const LexerRegistry = @import("registry.zig").LexerRegistry;
pub const LexerState = @import("state.zig").LexerState;

// Re-export for convenience
pub const Language = @import("../core/language.zig").Language;
pub const StreamToken = @import("../token/stream_token.zig").StreamToken;
pub const TokenStream = @import("../stream/mod.zig").Stream(StreamToken);

test {
    _ = @import("test.zig");
    _ = @import("lexer_bridge.zig");
    _ = @import("stream_adapter.zig");
    _ = @import("registry.zig");
    _ = @import("state.zig");
}