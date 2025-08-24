/// Lightweight JSON token - exactly 16 bytes
/// Optimized for streaming with minimal memory footprint
const std = @import("std");
const PackedSpan = @import("../../../span/mod.zig").PackedSpan;
const packSpan = @import("../../../span/mod.zig").packSpan;
const Span = @import("../../../span/mod.zig").Span;

/// JSON-specific token kinds
pub const TokenKind = enum(u8) {
    // Structural
    object_start, // {
    object_end, // }
    array_start, // [
    array_end, // ]
    comma, // ,
    colon, // :

    // Values
    property_name, // "key" in object
    string_value, // String literal
    number_value, // Number (int or float)
    boolean_true, // true
    boolean_false, // false
    null_value, // null

    // Trivia
    whitespace,
    comment, // Non-standard but common

    // Special
    eof,
    err, // 'error' is reserved in Zig
    continuation, // Token continues across buffer boundaries
};

/// Flags for additional token information (2 bytes)
pub const TokenFlags = packed struct {
    has_escapes: bool = false, // String contains escape sequences
    is_float: bool = false, // Number is floating point
    is_negative: bool = false, // Number is negative
    is_hex: bool = false, // Number in hex format (non-standard)
    is_scientific: bool = false, // Number in scientific notation
    multiline_comment: bool = false, // /* */ style comment
    continuation: bool = false, // Token spans 4KB boundary (needs more data)
    _padding: u9 = 0, // Reserved for future use
};

/// Lightweight JSON token - exactly 16 bytes
pub const Token = extern struct {
    span: PackedSpan, // 8 bytes - position in source
    kind: TokenKind, // 1 byte - token type
    depth: u8, // 1 byte - nesting depth
    flags: TokenFlags, // 2 bytes - additional info
    data: u32, // 4 bytes - string table index or inline value

    /// Create a new JSON token
    pub fn init(span: Span, kind: TokenKind, depth: u8) Token {
        return .{
            .span = packSpan(span),
            .kind = kind,
            .depth = depth,
            .flags = .{},
            .data = 0,
        };
    }

    /// Create a structural token (brackets, comma, colon)
    pub fn structural(span: Span, kind: TokenKind, depth: u8) Token {
        std.debug.assert(switch (kind) {
            .object_start, .object_end, .array_start, .array_end, .comma, .colon => true,
            else => false,
        });
        return init(span, kind, depth);
    }

    /// Create a string token (property name or value)
    pub fn string(span: Span, is_property: bool, depth: u8, string_index: u32, has_escapes: bool) Token {
        var token = init(span, if (is_property) .property_name else .string_value, depth);
        token.data = string_index;
        token.flags.has_escapes = has_escapes;
        return token;
    }

    /// Create a number token
    pub fn number(span: Span, depth: u8, flags: TokenFlags) Token {
        var token = init(span, .number_value, depth);
        token.flags = flags;
        return token;
    }

    /// Create a boolean token
    pub fn boolean(span: Span, depth: u8, value: bool) Token {
        return init(span, if (value) .boolean_true else .boolean_false, depth);
    }

    /// Create a null token
    pub fn nullValue(span: Span, depth: u8) Token {
        return init(span, .null_value, depth);
    }

    /// Create trivia token (whitespace or comment)
    pub fn trivia(span: Span, kind: TokenKind) Token {
        std.debug.assert(kind == .whitespace or kind == .comment);
        return init(span, kind, 0);
    }

    /// Check if token is trivia
    pub fn isTrivia(self: Token) bool {
        return self.kind == .whitespace or self.kind == .comment;
    }

    /// Check if token opens a scope
    pub fn isOpenDelimiter(self: Token) bool {
        return self.kind == .object_start or self.kind == .array_start;
    }

    /// Check if token closes a scope
    pub fn isCloseDelimiter(self: Token) bool {
        return self.kind == .object_end or self.kind == .array_end;
    }

    /// Get atom ID for this token's text content
    pub fn getAtomId(self: Token) ?u32 {
        return switch (self.kind) {
            .property_name, .string_value => self.data,
            else => null,
        };
    }

    /// DEPRECATED: Use getAtomId() instead
    pub fn getStringIndex(self: Token) ?u32 {
        return self.getAtomId();
    }
};

// Size assertion - must be exactly 16 bytes
comptime {
    std.debug.assert(@sizeOf(Token) == 16);
    std.debug.assert(@sizeOf(TokenKind) == 1);
    std.debug.assert(@sizeOf(TokenFlags) == 2);
}

test "Token size and creation" {
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(Token));
    try std.testing.expectEqual(@as(usize, 1), @sizeOf(TokenKind));
    try std.testing.expectEqual(@as(usize, 2), @sizeOf(TokenFlags));

    const span = Span.init(10, 20);

    // Test structural token
    const obj_start = Token.structural(span, .object_start, 0);
    try std.testing.expectEqual(TokenKind.object_start, obj_start.kind);
    try std.testing.expectEqual(@as(u8, 0), obj_start.depth);
    try std.testing.expect(obj_start.isOpenDelimiter());

    // Test string token
    const str = Token.string(span, false, 1, 42, true);
    try std.testing.expectEqual(TokenKind.string_value, str.kind);
    try std.testing.expectEqual(@as(u32, 42), str.data);
    try std.testing.expect(str.flags.has_escapes);

    // Test boolean token
    const bool_true = Token.boolean(span, 2, true);
    try std.testing.expectEqual(TokenKind.boolean_true, bool_true.kind);

    const bool_false = Token.boolean(span, 2, false);
    try std.testing.expectEqual(TokenKind.boolean_false, bool_false.kind);
}

test "Token categorization" {
    const span = Span.init(0, 1);

    const ws = Token.trivia(span, .whitespace);
    try std.testing.expect(ws.isTrivia());

    const obj = Token.structural(span, .object_start, 0);
    try std.testing.expect(obj.isOpenDelimiter());
    try std.testing.expect(!obj.isCloseDelimiter());

    const arr_end = Token.structural(span, .array_end, 1);
    try std.testing.expect(!arr_end.isOpenDelimiter());
    try std.testing.expect(arr_end.isCloseDelimiter());
}
