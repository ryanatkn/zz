const std = @import("std");
const JsonToken = @import("tokens.zig").JsonToken;
const Token = @import("../../parser_old/foundation/types/token.zig").Token;
const TokenKind = @import("../../parser_old/foundation/types/predicate.zig").TokenKind;
const Span = @import("../../parser_old/foundation/types/span.zig").Span;
const GenericStreamToken = @import("../../transform_old/streaming/generic_stream_token.zig").GenericStreamToken;

/// VTable adapter for JsonToken to work with GenericStreamToken
/// This enables JsonToken to be used in the generic streaming system
/// without hardcoded dependencies in the transform layer.
pub const JsonTokenVTableAdapter = struct {
    /// Create VTable for JsonToken
    pub fn createVTable() GenericStreamToken.VTable {
        return GenericStreamToken.VTable{
            .getSpanFn = getSpan,
            .getKindFn = getKind,
            .getTextFn = getText,
            .getDepthFn = getDepth,
            .isTriviaFn = isTrivia,
            .isOpenDelimiterFn = isOpenDelimiter,
            .isCloseDelimiterFn = isCloseDelimiter,
            .isErrorFn = isError,
            .toGenericTokenFn = toGenericToken,
            .getDebugInfoFn = getDebugInfo,
        };
    }

    /// Get span from JsonToken
    fn getSpan(token_ptr: *anyopaque) Span {
        const token: *JsonToken = @ptrCast(@alignCast(token_ptr));
        return token.span();
    }

    /// Map JsonToken to generic TokenKind
    fn getKind(token_ptr: *anyopaque) TokenKind {
        const token: *JsonToken = @ptrCast(@alignCast(token_ptr));
        return switch (token.*) {
            .object_start => .left_brace,
            .object_end => .right_brace,
            .array_start => .left_bracket,
            .array_end => .right_bracket,
            .comma => .comma,
            .colon => .colon,
            .property_name => .string_literal,
            .string_value => .string_literal,
            .decimal_int, .hex_int, .float, .scientific => .number_literal,
            .boolean_value => .boolean_literal,
            .null_value => .null_literal,
            .comment => .comment,
            .whitespace => .whitespace,
            .invalid => .unknown,
        };
    }

    /// Get text from JsonToken
    fn getText(token_ptr: *anyopaque) []const u8 {
        const token: *JsonToken = @ptrCast(@alignCast(token_ptr));
        return token.text();
    }

    /// Get depth from JsonToken
    fn getDepth(token_ptr: *anyopaque) u16 {
        const token: *JsonToken = @ptrCast(@alignCast(token_ptr));
        return token.tokenData().depth;
    }

    /// Check if JsonToken is trivia
    fn isTrivia(token_ptr: *anyopaque) bool {
        const token: *JsonToken = @ptrCast(@alignCast(token_ptr));
        return switch (token.*) {
            .whitespace, .comment => true,
            else => false,
        };
    }

    /// Check if JsonToken is opening delimiter
    fn isOpenDelimiter(token_ptr: *anyopaque) bool {
        const token: *JsonToken = @ptrCast(@alignCast(token_ptr));
        return switch (token.*) {
            .object_start, .array_start => true,
            else => false,
        };
    }

    /// Check if JsonToken is closing delimiter
    fn isCloseDelimiter(token_ptr: *anyopaque) bool {
        const token: *JsonToken = @ptrCast(@alignCast(token_ptr));
        return switch (token.*) {
            .object_end, .array_end => true,
            else => false,
        };
    }

    /// Check if JsonToken is error
    fn isError(token_ptr: *anyopaque) bool {
        const token: *JsonToken = @ptrCast(@alignCast(token_ptr));
        return switch (token.*) {
            .invalid => true,
            else => false,
        };
    }

    /// Convert JsonToken to generic Token
    fn toGenericToken(token_ptr: *anyopaque, source: []const u8) Token {
        const token: *JsonToken = @ptrCast(@alignCast(token_ptr));
        return convertJsonToGenericToken(token.*, source);
    }

    /// Get debug info from JsonToken
    fn getDebugInfo(token_ptr: *anyopaque) []const u8 {
        const token: *JsonToken = @ptrCast(@alignCast(token_ptr));
        return switch (token.*) {
            .property_name => |prop| if (prop.has_escapes) "escaped_property" else "property",
            .string_value => |str| if (str.has_escapes) "escaped_string" else "string",
            .decimal_int => "decimal_int",
            .hex_int => "hex_int",
            .float => "float",
            .scientific => "scientific",
            .boolean_value => |boolean| if (boolean.value) "true" else "false",
            .comment => |comment| @tagName(comment.kind),
            else => @tagName(token.*),
        };
    }
};

/// Convert JsonToken to generic Token (implementation of slow path)
fn convertJsonToGenericToken(json_token: JsonToken, source: []const u8) Token {
    _ = source; // May be needed for text extraction in some cases

    const span_val = json_token.span();
    const depth = json_token.tokenData().depth;
    const kind = switch (json_token) {
        .object_start => TokenKind.left_brace,
        .object_end => TokenKind.right_brace,
        .array_start => TokenKind.left_bracket,
        .array_end => TokenKind.right_bracket,
        .comma => TokenKind.comma,
        .colon => TokenKind.colon,
        .property_name => TokenKind.string_literal,
        .string_value => TokenKind.string_literal,
        .decimal_int, .hex_int, .float, .scientific => TokenKind.number_literal,
        .boolean_value => TokenKind.boolean_literal,
        .null_value => TokenKind.null_literal,
        .comment => TokenKind.comment,
        .whitespace => TokenKind.whitespace,
        .invalid => TokenKind.unknown,
    };

    // Extract text from JsonToken
    const text = json_token.text();

    return Token{
        .kind = kind,
        .span = span_val,
        .text = text,
        .bracket_depth = depth,
        .flags = .{}, // TODO: Map flags from JsonToken if needed
    };
}

/// Helper to create GenericStreamToken from JsonToken
pub fn createGenericStreamToken(json_token: *JsonToken) GenericStreamToken {
    const vtable = JsonTokenVTableAdapter.createVTable();
    return GenericStreamToken.init(json_token, &vtable);
}

/// Convert array of JsonTokens to GenericStreamTokens
pub fn convertJsonTokensToGeneric(
    allocator: std.mem.Allocator,
    json_tokens: []JsonToken,
) ![]GenericStreamToken {
    var stream_tokens = try allocator.alloc(GenericStreamToken, json_tokens.len);
    const vtable = JsonTokenVTableAdapter.createVTable();

    for (json_tokens, 0..) |*json_token, i| {
        stream_tokens[i] = GenericStreamToken.init(json_token, &vtable);
    }

    return stream_tokens;
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "JsonTokenVTableAdapter - basic functionality" {
    // Create a test JsonToken
    var json_token = JsonToken{
        .string_value = .{
            .data = .{
                .span = Span{ .start = 0, .end = 7 },
                .line = 1,
                .column = 1,
                .depth = 0,
            },
            .value = "test",
            .raw = "\"test\"",
            .has_escapes = false,
        },
    };

    // Create generic stream token
    const vtable = JsonTokenVTableAdapter.createVTable();
    const stream_token = GenericStreamToken.init(&json_token, &vtable);

    // Test vtable dispatch
    try testing.expectEqual(TokenKind.string_literal, stream_token.kind());
    try testing.expectEqual(@as(usize, 0), stream_token.span().start);
    try testing.expectEqual(@as(usize, 7), stream_token.span().end);
    try testing.expectEqual(@as(u16, 0), stream_token.depth());
    try testing.expect(!stream_token.isTrivia());
    try testing.expect(!stream_token.isError());
    try testing.expect(!stream_token.isOpenDelimiter());
    try testing.expect(!stream_token.isCloseDelimiter());
}

test "JsonTokenVTableAdapter - delimiter detection" {
    // Test object start
    var obj_start = JsonToken{
        .object_start = .{
            .span = Span{ .start = 0, .end = 1 },
            .line = 1,
            .column = 1,
            .depth = 0,
        },
    };

    const stream_token = createGenericStreamToken(&obj_start);
    try testing.expect(stream_token.isOpenDelimiter());
    try testing.expect(!stream_token.isCloseDelimiter());
    try testing.expectEqual(TokenKind.left_brace, stream_token.kind());
}

test "JsonTokenVTableAdapter - debug info" {
    var bool_token = JsonToken{
        .boolean_value = .{
            .data = .{
                .span = Span{ .start = 0, .end = 4 },
                .line = 1,
                .column = 1,
                .depth = 0,
            },
            .value = true,
        },
    };

    const stream_token = createGenericStreamToken(&bool_token);
    const debug_info = stream_token.getDebugInfo();
    try testing.expect(debug_info != null);
    if (debug_info) |info| {
        try testing.expectEqualStrings("true", info);
    }
}
