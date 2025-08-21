/// Comprehensive tests for the token module
const std = @import("std");
const testing = std.testing;

// Import token module components
const TokenKind = @import("kind.zig").TokenKind;
const StreamToken = @import("stream_token.zig").StreamToken;
const SimpleStreamToken = @import("generic.zig").SimpleStreamToken;

// Import language tokens
const JsonToken = @import("../languages/json/stream_token.zig").JsonToken;
const ZonToken = @import("../languages/zon/stream_token.zig").ZonToken;

// Import span types
const Span = @import("../span/mod.zig").Span;
const PackedSpan = @import("../span/mod.zig").PackedSpan;
const packSpan = @import("../span/mod.zig").packSpan;

test "TokenKind basic properties" {
    // Size check
    try testing.expectEqual(@as(usize, 1), @sizeOf(TokenKind));

    // Categorization tests
    try testing.expect(TokenKind.whitespace.isTrivia());
    try testing.expect(TokenKind.comment.isTrivia());
    try testing.expect(!TokenKind.identifier.isTrivia());

    try testing.expect(TokenKind.left_brace.isDelimiter());
    try testing.expect(TokenKind.left_brace.isOpenDelimiter());
    try testing.expect(!TokenKind.left_brace.isCloseDelimiter());

    try testing.expect(TokenKind.keyword_if.isKeyword());
    try testing.expect(TokenKind.plus.isOperator());
    try testing.expect(TokenKind.string.isLiteral());
}

test "JsonToken size and construction" {
    try testing.expectEqual(@as(usize, 16), @sizeOf(JsonToken));

    const span = Span.init(10, 20);

    // Structural tokens
    const obj_start = JsonToken.structural(span, .object_start, 0);
    try testing.expectEqual(@as(u8, 0), obj_start.depth);
    try testing.expect(obj_start.isOpenDelimiter());
    try testing.expect(!obj_start.isCloseDelimiter());

    // String tokens
    const str = JsonToken.string(span, false, 1, 42, true);
    try testing.expectEqual(@as(?u32, 42), str.getStringIndex());
    try testing.expect(str.flags.has_escapes);

    // Boolean tokens
    const bool_true = JsonToken.boolean(span, 2, true);
    const JsonTokenKind = @import("../languages/json/stream_token.zig").JsonTokenKind;
    try testing.expectEqual(JsonTokenKind.boolean_true, bool_true.kind);
}

test "ZonToken size and construction" {
    try testing.expectEqual(@as(usize, 16), @sizeOf(ZonToken));

    const span = Span.init(30, 40);

    // Structural tokens
    const struct_start = ZonToken.structural(span, .struct_start, 0);
    try testing.expectEqual(@as(u8, 0), struct_start.depth);
    try testing.expect(struct_start.isOpenDelimiter());

    // Field tokens
    const field = ZonToken.field(span, 1, 100, true);
    try testing.expectEqual(@as(?u32, 100), field.getStringIndex());
    try testing.expect(field.flags.is_quoted_field);

    // Enum literal
    const enum_lit = ZonToken.enumLiteral(span, 2, 200);
    const ZonTokenKind = @import("../languages/zon/stream_token.zig").ZonTokenKind;
    try testing.expectEqual(ZonTokenKind.enum_literal, enum_lit.kind);
}

test "StreamToken tagged union operations" {
    const span = Span.init(0, 10);

    // JSON token in StreamToken
    const json_tok = JsonToken.structural(span, .object_start, 0);
    const stream_json = StreamToken{ .json = json_tok };

    try testing.expectEqual(packSpan(span), stream_json.span());
    try testing.expectEqual(@as(u8, 0), stream_json.depth());
    try testing.expectEqual(TokenKind.left_brace, stream_json.kind());
    try testing.expect(stream_json.isOpenDelimiter());

    // ZON token in StreamToken
    const zon_tok = ZonToken.field(span, 1, 42, false);
    const stream_zon = StreamToken{ .zon = zon_tok };

    try testing.expectEqual(packSpan(span), stream_zon.span());
    try testing.expectEqual(@as(u8, 1), stream_zon.depth());
    try testing.expectEqual(TokenKind.identifier, stream_zon.kind());
    try testing.expectEqual(@as(?u32, 42), stream_zon.getStringIndex());
}

test "StreamToken size constraints" {
    const size = @sizeOf(StreamToken);
    // StreamToken should be: 1 byte tag + 16 byte max variant = 17 bytes
    // Aligned to 24 bytes typically
    try testing.expect(size <= 24);

    // Report actual size for visibility
    std.debug.print("\n  StreamToken size: {} bytes (target: ≤24)\n", .{size});
}

test "Generic SimpleStreamToken" {
    const span = Span.init(50, 60);

    // Define a custom token union
    const TestUnion = union(enum) {
        json: JsonToken,
        zon: ZonToken,
    };

    const TestToken = SimpleStreamToken(TestUnion);

    // Create a JSON token through generic wrapper
    const json_tok = JsonToken.structural(span, .array_start, 2);
    const test_tok = TestToken{
        .token = TestUnion{ .json = json_tok },
    };

    try testing.expectEqual(packSpan(span), test_tok.span());
    try testing.expectEqual(@as(u8, 2), test_tok.depth());
    try testing.expect(test_tok.isOpenDelimiter());
}

test "Fact extraction interface" {
    const allocator = testing.allocator;
    const FactStore = @import("../fact/mod.zig").FactStore;

    var store = FactStore.init(allocator);
    defer store.deinit();

    const span = Span.init(0, 5);
    const source = "{}[]\"test\"";

    // Create tokens
    const json_obj = JsonToken.structural(span, .object_start, 0);
    const stream_tok = StreamToken{ .json = json_obj };

    // Extract facts (this will add facts to the store)
    try stream_tok.extractFacts(&store, source);

    // Verify facts were added
    const facts = store.getAll();
    try testing.expect(facts.len > 0);

    // TODO: Once fact extraction is fully implemented, verify specific facts
    // For now just check that extraction doesn't crash
}

test "Token categorization across languages" {
    const span = Span.init(0, 1);

    // Test that categorization works consistently across languages
    const json_ws = JsonToken.trivia(span, .whitespace);
    const json_stream = StreamToken{ .json = json_ws };
    try testing.expect(json_stream.isTrivia());

    const zon_comment = ZonToken.trivia(span, .comment);
    const zon_stream = StreamToken{ .zon = zon_comment };
    try testing.expect(zon_stream.isTrivia());
}

// Integration test with actual lexing would go here once lexers are implemented
test "TokenIterator basic operations" {
    // TODO: Implement once actual lexers are available
    // For now, just test that the module compiles
    _ = @import("iterator.zig");
}

// TODO: Add benchmark test comparing:
// - StreamToken tagged union dispatch performance
// - Old vtable-based GenericStreamToken performance
// - Direct language token access performance

// TODO: Test fact extraction with real AtomTable integration
// - Verify atom IDs are properly assigned
// - Check string deduplication works correctly
// - Measure memory usage with string interning
