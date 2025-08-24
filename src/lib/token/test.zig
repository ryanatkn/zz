/// Comprehensive tests for the token module
const std = @import("std");
const testing = std.testing;

// Import token module components
const Token = @import("stream_token.zig").Token;

// Import language tokens
const JsonToken = @import("../languages/json/token/mod.zig").Token;
const ZonToken = @import("../languages/zon/stream_token.zig").ZonToken;

// Import span types
const Span = @import("../span/mod.zig").Span;
const PackedSpan = @import("../span/mod.zig").PackedSpan;
const packSpan = @import("../span/mod.zig").packSpan;

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
    try testing.expectEqual(@as(?u32, 42), str.getAtomId());
    try testing.expect(str.flags.has_escapes);

    // Boolean tokens
    const bool_true = JsonToken.boolean(span, 2, true);
    const JsonTokenKind = @import("../languages/json/token/mod.zig").TokenKind;
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
    try testing.expectEqual(@as(?u32, 100), field.getAtomId());
    try testing.expect(field.flags.is_quoted_field);

    // Enum literal
    const enum_lit = ZonToken.enumLiteral(span, 2, 200);
    const ZonTokenKind = @import("../languages/zon/stream_token.zig").ZonTokenKind;
    try testing.expectEqual(ZonTokenKind.enum_literal, enum_lit.kind);
}

test "Token tagged union operations" {
    const span = Span.init(0, 10);

    // JSON token in Token
    const json_tok = JsonToken.structural(span, .object_start, 0);
    const stream_json = Token{ .json = json_tok };

    // Direct field access - no methods
    try testing.expectEqual(packSpan(span), stream_json.json.span);
    try testing.expectEqual(@as(u8, 0), stream_json.json.depth);
    // No generic kind mapping - language owns its kinds
    const JsonTokenKind = @import("../languages/json/token/mod.zig").TokenKind;
    try testing.expectEqual(JsonTokenKind.object_start, stream_json.json.kind);
    try testing.expect(stream_json.json.isOpenDelimiter());

    // ZON token in Token
    const zon_tok = ZonToken.field(span, 1, 42, false);
    const stream_zon = Token{ .zon = zon_tok };

    // Direct field access - no methods
    try testing.expectEqual(packSpan(span), stream_zon.zon.span);
    try testing.expectEqual(@as(u8, 1), stream_zon.zon.depth);
    // No generic kind mapping - language owns its kinds
    const ZonTokenKind = @import("../languages/zon/stream_token.zig").ZonTokenKind;
    try testing.expectEqual(ZonTokenKind.field_name, stream_zon.zon.kind);
    try testing.expectEqual(@as(?u32, 42), stream_zon.zon.getAtomId());
}

test "Token size constraints" {
    const size = @sizeOf(Token);
    // Token should be: 1 byte tag + 16 byte max variant = 17 bytes
    // Aligned to 24 bytes typically
    try testing.expect(size <= 24);

    // Report actual size for visibility
    std.debug.print("\n  Token size: {} bytes (target: ≤24)\n", .{size});
}

test "Token categorization across languages" {
    const span = Span.init(0, 1);

    // Test that categorization works consistently across languages
    const json_ws = JsonToken.trivia(span, .whitespace);
    const json_stream = Token{ .json = json_ws };
    try testing.expect(json_stream.json.isTrivia());

    const zon_comment = ZonToken.trivia(span, .comment);
    const zon_stream = Token{ .zon = zon_comment };
    try testing.expect(zon_stream.zon.isTrivia());
}

// Integration test with streaming lexers
test "TokenIterator basic operations" {
    const TokenIterator = @import("iterator.zig").TokenIterator;
    const Language = @import("../core/language.zig").Language;

    // Test JSON lexing
    {
        const json_source =
            \\{"name": "test", "value": 42}
        ;

        var iter = try TokenIterator.init(json_source, .json);

        var token_count: usize = 0;
        while (iter.next()) |token| {
            token_count += 1;

            // Verify we get Token with json variant
            switch (token) {
                .json => |json_token| {
                    _ = json_token.kind;
                    _ = json_token.span;
                },
                else => unreachable,
            }

            // Check for EOF using direct field access
            switch (token) {
                .json => |t| if (t.kind == .eof) break,
                else => {},
            }
        }

        try testing.expect(token_count > 0);
    }

    // Test ZON lexing
    {
        const zon_source =
            \\.{ .name = "test", .value = 42 }
        ;

        var iter = try TokenIterator.init(zon_source, .zon);

        var token_count: usize = 0;
        while (iter.next()) |token| {
            token_count += 1;

            switch (token) {
                .zon => |zon_token| {
                    _ = zon_token.kind;
                    _ = zon_token.span;
                },
                else => unreachable,
            }

            // Check for EOF using direct field access
            switch (token) {
                .zon => |t| if (t.kind == .eof) break,
                else => {},
            }
        }

        try testing.expect(token_count > 0);
    }

    // Test language detection by caller
    {
        const source = "{}";
        const lang = Language.fromPath("test.json");
        var iter = try TokenIterator.init(source, lang);

        const token = iter.next();
        try testing.expect(token != null);

        switch (token.?) {
            .json => {}, // Expected
            else => unreachable,
        }
    }
}

// TODO: Add benchmark test comparing:
// - Token tagged union dispatch performance
// - Old vtable-based GenericToken performance
// - Direct language token access performance

// TODO: Test fact extraction with real AtomTable integration
// - Verify atom IDs are properly assigned
// - Check string deduplication works correctly
// - Measure memory usage with string interning
