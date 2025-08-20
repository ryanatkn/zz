const std = @import("std");
const ZonToken = @import("tokens.zig").ZonToken;
const Token = @import("../../parser/foundation/types/token.zig").Token;
const TokenKind = @import("../../parser/foundation/types/predicate.zig").TokenKind;
const Span = @import("../../parser/foundation/types/span.zig").Span;
const GenericStreamToken = @import("../../transform/streaming/generic_stream_token.zig").GenericStreamToken;

/// VTable adapter for ZonToken to work with GenericStreamToken
/// This enables ZonToken to be used in the generic streaming system
/// without hardcoded dependencies in the transform layer.
pub const ZonTokenVTableAdapter = struct {
    
    /// Create VTable for ZonToken
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
    
    /// Get span from ZonToken
    fn getSpan(token_ptr: *anyopaque) Span {
        const token: *ZonToken = @ptrCast(@alignCast(token_ptr));
        return token.span();
    }
    
    /// Map ZonToken to generic TokenKind
    fn getKind(token_ptr: *anyopaque) TokenKind {
        const token: *ZonToken = @ptrCast(@alignCast(token_ptr));
        return switch (token.*) {
            .object_start => .left_brace,
            .object_end => .right_brace,
            .array_start => .left_bracket,
            .array_end => .right_bracket,
            .comma => .comma,
            .colon => .colon,
            .equals => .operator,
            .identifier => .identifier,
            .field_name => |f| if (f.is_quoted) .string_literal else .identifier,
            .string_value => .string_literal,
            .decimal_int, .hex_int, .binary_int, .octal_int, .float => .number_literal,
            .char_literal => .string_literal,
            .boolean_value => .boolean_literal,
            .null_value => .null_literal,
            .undefined_value => .keyword,
            .enum_literal => .identifier,
            .struct_literal => .delimiter,
            .comment => .comment,
            .whitespace => .whitespace,
            .invalid => .unknown,
        };
    }
    
    /// Get text from ZonToken
    fn getText(token_ptr: *anyopaque) []const u8 {
        const token: *ZonToken = @ptrCast(@alignCast(token_ptr));
        return token.text();
    }
    
    /// Get depth from ZonToken
    fn getDepth(token_ptr: *anyopaque) u16 {
        const token: *ZonToken = @ptrCast(@alignCast(token_ptr));
        return token.tokenData().depth;
    }
    
    /// Check if ZonToken is trivia
    fn isTrivia(token_ptr: *anyopaque) bool {
        const token: *ZonToken = @ptrCast(@alignCast(token_ptr));
        return token.isTrivia();
    }
    
    /// Check if ZonToken is opening delimiter
    fn isOpenDelimiter(token_ptr: *anyopaque) bool {
        const token: *ZonToken = @ptrCast(@alignCast(token_ptr));
        return token.isOpenDelimiter();
    }
    
    /// Check if ZonToken is closing delimiter
    fn isCloseDelimiter(token_ptr: *anyopaque) bool {
        const token: *ZonToken = @ptrCast(@alignCast(token_ptr));
        return token.isCloseDelimiter();
    }
    
    /// Check if ZonToken is error
    fn isError(token_ptr: *anyopaque) bool {
        const token: *ZonToken = @ptrCast(@alignCast(token_ptr));
        return switch (token.*) {
            .invalid => true,
            else => false,
        };
    }
    
    /// Convert ZonToken to generic Token
    fn toGenericToken(token_ptr: *anyopaque, source: []const u8) Token {
        const token: *ZonToken = @ptrCast(@alignCast(token_ptr));
        return convertZonToGenericToken(token.*, source);
    }
    
    /// Get debug info from ZonToken
    fn getDebugInfo(token_ptr: *anyopaque) []const u8 {
        const token: *ZonToken = @ptrCast(@alignCast(token_ptr));
        return switch (token.*) {
            .identifier => |id| if (id.is_builtin) "builtin_identifier" else "identifier",
            .field_name => |field| if (field.is_quoted) "quoted_field" else "unquoted_field",
            .string_value => |str| if (str.has_escapes) 
                (if (str.is_multiline) "multiline_escaped_string" else "escaped_string")
            else 
                (if (str.is_multiline) "multiline_string" else "string"),
            .decimal_int => |num| if (num.has_underscores) "decimal_int_underscores" else "decimal_int",
            .hex_int => |num| if (num.has_underscores) "hex_int_underscores" else "hex_int",
            .binary_int => |num| if (num.has_underscores) "binary_int_underscores" else "binary_int",
            .octal_int => |num| if (num.has_underscores) "octal_int_underscores" else "octal_int",
            .float => |f| if (f.has_exponent) 
                (if (f.has_underscores) "float_exp_underscores" else "float_exp")
            else 
                (if (f.has_underscores) "float_underscores" else "float"),
            .char_literal => "char",
            .boolean_value => |boolean| if (boolean.value) "true" else "false",
            .enum_literal => "enum_literal",
            .comment => |comment| @tagName(comment.kind),
            else => @tagName(token.*),
        };
    }
};

/// Convert ZonToken to generic Token (implementation of slow path)
fn convertZonToGenericToken(zon_token: ZonToken, source: []const u8) Token {
    _ = source; // May be needed for text extraction in some cases
    
    const span_val = zon_token.span();
    const depth = zon_token.tokenData().depth;
    const kind = switch (zon_token) {
        .object_start => TokenKind.left_brace,
        .object_end => TokenKind.right_brace,
        .array_start => TokenKind.left_bracket,
        .array_end => TokenKind.right_bracket,
        .comma => TokenKind.comma,
        .colon => TokenKind.colon,
        .equals => TokenKind.operator,
        .identifier => TokenKind.identifier,
        .field_name => |f| if (f.is_quoted) TokenKind.string_literal else TokenKind.identifier,
        .string_value => TokenKind.string_literal,
        .decimal_int, .hex_int, .binary_int, .octal_int, .float => TokenKind.number_literal,
        .char_literal => TokenKind.string_literal,
        .boolean_value => TokenKind.boolean_literal,
        .null_value => TokenKind.null_literal,
        .undefined_value => TokenKind.keyword,
        .enum_literal => TokenKind.identifier,
        .struct_literal => TokenKind.delimiter,
        .comment => TokenKind.comment,
        .whitespace => TokenKind.whitespace,
        .invalid => TokenKind.unknown,
    };
    
    // Extract text from ZonToken
    const text = zon_token.text();
    
    return Token{
        .kind = kind,
        .span = span_val,
        .text = text,
        .bracket_depth = depth,
        .flags = .{}, // TODO: Map flags from ZonToken if needed
    };
}

/// Helper to create GenericStreamToken from ZonToken
pub fn createGenericStreamToken(zon_token: *ZonToken) GenericStreamToken {
    const vtable = ZonTokenVTableAdapter.createVTable();
    return GenericStreamToken.init(zon_token, &vtable);
}

/// Convert array of ZonTokens to GenericStreamTokens
pub fn convertZonTokensToGeneric(
    allocator: std.mem.Allocator,
    zon_tokens: []ZonToken,
) ![]GenericStreamToken {
    var stream_tokens = try allocator.alloc(GenericStreamToken, zon_tokens.len);
    const vtable = ZonTokenVTableAdapter.createVTable();
    
    for (zon_tokens, 0..) |*zon_token, i| {
        stream_tokens[i] = GenericStreamToken.init(zon_token, &vtable);
    }
    
    return stream_tokens;
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "ZonTokenVTableAdapter - basic functionality" {
    // Create a test ZonToken
    var zon_token = ZonToken{
        .decimal_int = .{
            .data = .{
                .span = Span{ .start = 0, .end = 3 },
                .line = 1,
                .column = 1,
                .depth = 0,
            },
            .value = 123,
            .raw = "123",
            .has_underscores = false,
        },
    };
    
    // Create generic stream token
    const vtable = ZonTokenVTableAdapter.createVTable();
    const stream_token = GenericStreamToken.init(&zon_token, &vtable);
    
    // Test vtable dispatch
    try testing.expectEqual(TokenKind.number_literal, stream_token.kind());
    try testing.expectEqual(@as(usize, 0), stream_token.span().start);
    try testing.expectEqual(@as(usize, 3), stream_token.span().end);
    try testing.expectEqualStrings("123", stream_token.text());
    try testing.expectEqual(@as(u16, 0), stream_token.depth());
    try testing.expect(!stream_token.isTrivia());
    try testing.expect(!stream_token.isError());
}

test "ZonTokenVTableAdapter - hex number with underscores" {
    var hex_token = ZonToken{
        .hex_int = .{
            .data = .{
                .span = Span{ .start = 5, .end = 13 },
                .line = 1,
                .column = 6,
                .depth = 1,
            },
            .value = 0xFF_FF,
            .raw = "0xFF_FF",
            .has_underscores = true,
        },
    };
    
    const stream_token = createGenericStreamToken(&hex_token);
    try testing.expectEqual(TokenKind.number_literal, stream_token.kind());
    try testing.expectEqualStrings("0xFF_FF", stream_token.text());
    
    const debug_info = stream_token.getDebugInfo();
    try testing.expect(debug_info != null);
    if (debug_info) |info| {
        try testing.expectEqualStrings("hex_int_underscores", info);
    }
}

test "ZonTokenVTableAdapter - enum literal" {
    var enum_token = ZonToken{
        .enum_literal = .{
            .data = .{
                .span = Span{ .start = 10, .end = 18 },
                .line = 2,
                .column = 1,
                .depth = 0,
            },
            .name = ".Success",
        },
    };
    
    const stream_token = createGenericStreamToken(&enum_token);
    try testing.expectEqual(TokenKind.identifier, stream_token.kind());
    try testing.expectEqualStrings(".Success", stream_token.text());
    try testing.expect(stream_token.isValue());
}

test "ZonTokenVTableAdapter - field name quoted vs unquoted" {
    // Unquoted field
    var unquoted_field = ZonToken{
        .field_name = .{
            .data = .{
                .span = Span{ .start = 0, .end = 6 },
                .line = 1,
                .column = 1,
                .depth = 1,
            },
            .name = "config",
            .raw = "config",
            .is_quoted = false,
        },
    };
    
    const unquoted_stream = createGenericStreamToken(&unquoted_field);
    try testing.expectEqual(TokenKind.identifier, unquoted_stream.kind());
    
    // Quoted field
    var quoted_field = ZonToken{
        .field_name = .{
            .data = .{
                .span = Span{ .start = 10, .end = 23 },
                .line = 1,
                .column = 11,
                .depth = 1,
            },
            .name = "config-file",
            .raw = "\"config-file\"",
            .is_quoted = true,
        },
    };
    
    const quoted_stream = createGenericStreamToken(&quoted_field);
    try testing.expectEqual(TokenKind.string_literal, quoted_stream.kind());
}