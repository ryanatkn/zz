/// Stream-first tests for JSON
/// Focused test file for the new streaming architecture
const std = @import("std");
const testing = std.testing;

// Import only the stream-first components
const Lexer = @import("../lexer/mod.zig").Lexer;
const JsonToken = @import("../token/mod.zig").Token;
const TokenKind = @import("../token/mod.zig").TokenKind;

// Re-export tests from stream modules
test {
    _ = @import("../lexer/mod.zig");
    _ = @import("../token/mod.zig");
}

// Additional integration tests for streaming
test "JSON stream lexer integration" {
    const input =
        \\{
        \\  "name": "stream-first",
        \\  "version": 1.0,
        \\  "enabled": true
        \\}
    ;

    var lexer = Lexer.init(input);

    // Verify we can process the entire input
    var token_count: usize = 0;
    while (lexer.next()) |token| {
        if (token.json.kind == .eof) break;
        token_count += 1;
    }

    try testing.expect(token_count > 0);
}

test "JSON stream lexer performance characteristics" {
    // Verify the lexer struct size is reasonable
    const lexer_size = @sizeOf(Lexer);
    try testing.expect(lexer_size < 5000); // Mostly ring buffer

    // Verify token size is exactly 16 bytes
    const token_size = @sizeOf(JsonToken);
    try testing.expectEqual(@as(usize, 16), token_size);
}

test "JSON stream lexer edge cases" {
    // Test empty object
    var lexer1 = Lexer.init("{}");
    const t1 = lexer1.next().?;
    try testing.expectEqual(TokenKind.object_start, t1.json.kind);
    const t2 = lexer1.next().?;
    try testing.expectEqual(TokenKind.object_end, t2.json.kind);

    // Test empty array
    var lexer2 = Lexer.init("[]");
    const t3 = lexer2.next().?;
    try testing.expectEqual(TokenKind.array_start, t3.json.kind);
    const t4 = lexer2.next().?;
    try testing.expectEqual(TokenKind.array_end, t4.json.kind);

    // Test single values
    var lexer3 = Lexer.init("null");
    const t5 = lexer3.next().?;
    try testing.expectEqual(TokenKind.null_value, t5.json.kind);
}
