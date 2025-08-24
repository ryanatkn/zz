/// Stream-first tests for ZON
/// Focused test file for the new streaming architecture
const std = @import("std");
const testing = std.testing;

// Import only the stream-first components
const Lexer = @import("../lexer/mod.zig").Lexer;
const Token = @import("../token/mod.zig").Token;
const TokenKind = @import("../token/mod.zig").TokenKind;

// Re-export tests from stream modules
test {
    _ = @import("../lexer/core.zig");
    _ = @import("../token/types.zig");
}

// Additional integration tests for streaming
test "ZON stream lexer integration" {
    const input =
        \\.{
        \\  .name = "stream-first",
        \\  .version = 1.0,
        \\  .enabled = true
        \\}
    ;

    var lexer = Lexer.init(input);

    // Verify we can process the entire input
    var token_count: usize = 0;
    while (lexer.next()) |token| {
        if (token.zon.kind == .eof) break;
        token_count += 1;
    }

    try testing.expect(token_count > 0);
}

test "ZON stream lexer performance characteristics" {
    // Verify the lexer struct size is reasonable for streaming architecture
    const lexer_size = @sizeOf(Lexer);
    try testing.expect(lexer_size < 70000); // ~64KB ring buffer + metadata
    try testing.expect(lexer_size > 65000); // Should be dominated by ring buffer

    // Verify token size is exactly 16 bytes
    const token_size = @sizeOf(Token);
    try testing.expectEqual(@as(usize, 16), token_size);
}

test "ZON stream lexer edge cases" {
    // Test empty struct
    var lexer1 = Lexer.init(".{}");
    const t1 = lexer1.next().?;
    try testing.expectEqual(TokenKind.struct_start, t1.zon.kind);
    const t2 = lexer1.next().?;
    try testing.expectEqual(TokenKind.struct_end, t2.zon.kind);

    // Test builtin function
    var lexer2 = Lexer.init("@import(\"std\")");
    const t3 = lexer2.next().?;
    try testing.expectEqual(TokenKind.import, t3.zon.kind);
}
