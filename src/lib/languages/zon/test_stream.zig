/// Stream-first tests for ZON
/// Focused test file for the new streaming architecture
const std = @import("std");
const testing = std.testing;

// Import only the stream-first components
const ZonStreamLexer = @import("stream_lexer.zig").ZonStreamLexer;
const ZonToken = @import("stream_token.zig").ZonToken;
const ZonTokenKind = @import("stream_token.zig").ZonTokenKind;

// Re-export tests from stream modules
test {
    _ = @import("stream_lexer.zig");
    _ = @import("stream_token.zig");
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

    var lexer = ZonStreamLexer.init(input);

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
    const lexer_size = @sizeOf(ZonStreamLexer);
    try testing.expect(lexer_size < 70000); // ~64KB ring buffer + metadata
    try testing.expect(lexer_size > 65000); // Should be dominated by ring buffer

    // Verify token size is exactly 16 bytes
    const token_size = @sizeOf(ZonToken);
    try testing.expectEqual(@as(usize, 16), token_size);
}

test "ZON stream lexer edge cases" {
    // Test empty struct
    var lexer1 = ZonStreamLexer.init(".{}");
    const t1 = lexer1.next().?;
    try testing.expectEqual(ZonTokenKind.struct_start, t1.zon.kind);
    const t2 = lexer1.next().?;
    try testing.expectEqual(ZonTokenKind.struct_end, t2.zon.kind);

    // Test builtin function
    var lexer2 = ZonStreamLexer.init("@import(\"std\")");
    const t3 = lexer2.next().?;
    try testing.expectEqual(ZonTokenKind.import, t3.zon.kind);
}
