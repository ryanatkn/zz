/// Stream-first tests for JSON
/// Focused test file for the new streaming architecture
const std = @import("std");
const testing = std.testing;

// Import only the stream-first components
const JsonStreamLexer = @import("stream_lexer.zig").JsonStreamLexer;
const JsonToken = @import("stream_token.zig").JsonToken;
const JsonTokenKind = @import("stream_token.zig").JsonTokenKind;

// Re-export tests from stream modules
test {
    _ = @import("stream_lexer.zig");
    _ = @import("stream_token.zig");
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
    
    var lexer = JsonStreamLexer.init(input);
    
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
    const lexer_size = @sizeOf(JsonStreamLexer);
    try testing.expect(lexer_size < 5000); // Mostly ring buffer
    
    // Verify token size is exactly 16 bytes
    const token_size = @sizeOf(JsonToken);
    try testing.expectEqual(@as(usize, 16), token_size);
}

test "JSON stream lexer edge cases" {
    // Test empty object
    var lexer1 = JsonStreamLexer.init("{}");
    const t1 = lexer1.next().?;
    try testing.expectEqual(JsonTokenKind.object_start, t1.json.kind);
    const t2 = lexer1.next().?;
    try testing.expectEqual(JsonTokenKind.object_end, t2.json.kind);
    
    // Test empty array
    var lexer2 = JsonStreamLexer.init("[]");
    const t3 = lexer2.next().?;
    try testing.expectEqual(JsonTokenKind.array_start, t3.json.kind);
    const t4 = lexer2.next().?;
    try testing.expectEqual(JsonTokenKind.array_end, t4.json.kind);
    
    // Test single values
    var lexer3 = JsonStreamLexer.init("null");
    const t5 = lexer3.next().?;
    try testing.expectEqual(JsonTokenKind.null_value, t5.json.kind);
}