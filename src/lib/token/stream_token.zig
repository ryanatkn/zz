/// StreamToken - Re-export from the language registry
/// This module now serves as the public interface to the token system,
/// while the actual token union is defined in the language registry
/// to keep all language-specific imports isolated.
///
/// Performance characteristics:
/// - Tagged union dispatch: 1-2 cycles (jump table)
/// - Memory size: ≤24 bytes (1 byte tag + 16 byte max variant + alignment)
/// - Zero allocations for token operations
const std = @import("std");

// The actual StreamToken is defined in the language registry
// This keeps all language-specific imports in one place
pub const StreamToken = @import("../languages/token_registry.zig").StreamToken;

// Compile-time size check to ensure token stays small
comptime {
    const token_size = @sizeOf(StreamToken);
    if (token_size > 24) {
        @compileError(std.fmt.comptimePrint("StreamToken too large: {} bytes (target: ≤24)", .{token_size}));
    }
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "StreamToken size constraints" {
    const size = @sizeOf(StreamToken);
    // StreamToken should be: 1 byte tag + 16 byte max variant = 17 bytes
    // Aligned to 24 bytes typically
    try testing.expect(size <= 24);

    // Report actual size for visibility
    std.debug.print("\n  StreamToken size: {} bytes (target: ≤24)\n", .{size});
}
