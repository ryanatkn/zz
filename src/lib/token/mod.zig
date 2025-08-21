/// Token module - Unified token system for stream-first architecture
/// Provides lightweight tokens with zero vtable overhead via tagged unions
///
/// Architecture: Tagged union dispatch (1-2 cycles) vs vtable (3-5 cycles)
/// Token size: 16 bytes per language token, ≤24 bytes for StreamToken
///
/// Extensibility Strategy:
/// - Phase 2: Hardcoded core languages (maximum performance)
/// - Phase 3: Add custom variant with vtable for experimentation
/// - Phase 4: Comptime composition for build-time extensibility
/// - Phase 5: Full plugin system preserving fast path
///
/// TODO: Integrate with global AtomTable from memory module for string interning
/// TODO: Create TokenRegistry similar to LanguageRegistry for language dispatch
/// TODO: Add benchmarks comparing StreamToken dispatch vs old vtable approach
/// TODO: Consider re-exporting language tokens for convenience (json.Token, etc)
const std = @import("std");

// Core token types
pub const TokenKind = @import("kind.zig").TokenKind;
pub const StreamToken = @import("stream_token.zig").StreamToken;

// Generic/composable token support
pub const SimpleStreamToken = @import("generic.zig").SimpleStreamToken;
pub const TokenInterface = @import("generic.zig").TokenInterface;

// Re-export Stream types for TokenStream
const Stream = @import("../stream/mod.zig").Stream;
const DirectStream = @import("../stream/mod.zig").DirectStream;
const directFromSlice = @import("../stream/mod.zig").directFromSlice;

pub const TokenStream = Stream(StreamToken);
pub const DirectTokenStream = DirectStream(StreamToken);

/// Create DirectStream from token slice
pub fn directTokenStream(tokens: []const StreamToken) DirectTokenStream {
    return directFromSlice(StreamToken, tokens);
}

/// TODO: Phase 5 - Migrate TokenIterator to produce DirectTokenStream

// TokenIterator for streaming tokenization
pub const TokenIterator = @import("iterator.zig").TokenIterator;

test "Token module" {
    _ = @import("kind.zig");
    _ = @import("stream_token.zig");
    _ = @import("test.zig");
}
