/// Lightweight ZON token - exactly 16 bytes
/// ZON (Zig Object Notation) is Zig's configuration format
const std = @import("std");
const PackedSpan = @import("../../../span/mod.zig").PackedSpan;
const packSpan = @import("../../../span/mod.zig").packSpan;
const Span = @import("../../../span/mod.zig").Span;

/// ZON-specific token kinds
pub const ZonTokenKind = enum(u8) {
    // Structural
    struct_start, // .{
    struct_end, // }
    array_start, // .{  (for arrays)
    array_end, // }
    object_start, // {
    object_end, // }
    paren_open, // (
    paren_close, // )
    comma, // ,
    equals, // =
    colon, // :
    dot, // .

    // Values
    field_name, // .field_name or "field_name"
    identifier, // Simple identifier
    string_value, // String literal
    number_value, // Number (int or float)
    boolean_true, // true
    boolean_false, // false
    null_value, // null
    undefined, // undefined

    // ZON-specific
    enum_literal, // .EnumValue
    import, // @import("...")

    // Trivia
    whitespace,
    comment, // // or /* */

    // Special
    eof,
    err, // 'error' is reserved in Zig
};

/// Flags for additional token information (2 bytes)
pub const ZonTokenFlags = packed struct {
    has_escapes: bool = false, // String contains escape sequences
    is_float: bool = false, // Number is floating point
    is_negative: bool = false, // Number is negative
    is_hex: bool = false, // Number in hex format (0x)
    is_binary: bool = false, // Number in binary format (0b)
    is_octal: bool = false, // Number in octal format (0o)
    multiline_comment: bool = false, // /* */ style comment
    multiline_string: bool = false, // \\ multiline string
    is_quoted_field: bool = false, // Field name is quoted
    _padding: u7 = 0, // Reserved for future use
};

/// Lightweight ZON token - exactly 16 bytes
pub const ZonToken = extern struct {
    span: PackedSpan, // 8 bytes - position in source
    kind: ZonTokenKind, // 1 byte - token type
    depth: u8, // 1 byte - nesting depth
    flags: ZonTokenFlags, // 2 bytes - additional info
    data: u32, // 4 bytes - string table index or inline value

    /// Create a new ZON token
    pub fn init(span: Span, kind: ZonTokenKind, depth: u8) ZonToken {
        return .{
            .span = packSpan(span),
            .kind = kind,
            .depth = depth,
            .flags = .{},
            .data = 0,
        };
    }

    /// Create a structural token
    pub fn structural(span: Span, kind: ZonTokenKind, depth: u8) ZonToken {
        std.debug.assert(switch (kind) {
            .struct_start, .struct_end, .array_start, .array_end, .comma, .equals, .dot => true,
            else => false,
        });
        return init(span, kind, depth);
    }

    /// Create a field name token
    pub fn field(span: Span, depth: u8, string_index: u32, is_quoted: bool) ZonToken {
        var token = init(span, .field_name, depth);
        token.data = string_index;
        token.flags.is_quoted_field = is_quoted;
        return token;
    }

    /// Create a string token
    pub fn string(span: Span, depth: u8, string_index: u32, flags: ZonTokenFlags) ZonToken {
        var token = init(span, .string_value, depth);
        token.data = string_index;
        token.flags = flags;
        return token;
    }

    /// Create a number token
    pub fn number(span: Span, depth: u8, flags: ZonTokenFlags) ZonToken {
        var token = init(span, .number_value, depth);
        token.flags = flags;
        return token;
    }

    /// Create an identifier token
    pub fn identifier(span: Span, depth: u8, string_index: u32) ZonToken {
        var token = init(span, .identifier, depth);
        token.data = string_index;
        return token;
    }

    /// Create an enum literal token
    pub fn enumLiteral(span: Span, depth: u8, string_index: u32) ZonToken {
        var token = init(span, .enum_literal, depth);
        token.data = string_index;
        return token;
    }

    /// Create a boolean token
    pub fn boolean(span: Span, depth: u8, value: bool) ZonToken {
        return init(span, if (value) .boolean_true else .boolean_false, depth);
    }

    /// Create a null token
    pub fn nullValue(span: Span, depth: u8) ZonToken {
        return init(span, .null_value, depth);
    }

    /// Create an undefined token
    pub fn undefinedValue(span: Span, depth: u8) ZonToken {
        return init(span, .undefined, depth);
    }

    /// Create an import token
    pub fn import(span: Span, depth: u8, string_index: u32) ZonToken {
        var token = init(span, .import, depth);
        token.data = string_index;
        return token;
    }

    /// Create trivia token (whitespace or comment)
    pub fn trivia(span: Span, kind: ZonTokenKind) ZonToken {
        std.debug.assert(kind == .whitespace or kind == .comment);
        return init(span, kind, 0);
    }

    /// Check if token is trivia
    pub fn isTrivia(self: ZonToken) bool {
        return self.kind == .whitespace or self.kind == .comment;
    }

    /// Check if token opens a scope
    pub fn isOpenDelimiter(self: ZonToken) bool {
        return self.kind == .struct_start or self.kind == .array_start;
    }

    /// Check if token closes a scope
    pub fn isCloseDelimiter(self: ZonToken) bool {
        return self.kind == .struct_end or self.kind == .array_end;
    }

    /// Get atom ID for this token's text content
    pub fn getAtomId(self: ZonToken) ?u32 {
        return switch (self.kind) {
            .field_name, .identifier, .string_value, .enum_literal, .import => self.data,
            else => null,
        };
    }

    /// DEPRECATED: Use getAtomId() instead
    pub fn getStringIndex(self: ZonToken) ?u32 {
        return self.getAtomId();
    }
};

// Size assertion - must be exactly 16 bytes
comptime {
    std.debug.assert(@sizeOf(ZonToken) == 16);
    std.debug.assert(@sizeOf(ZonTokenKind) == 1);
    std.debug.assert(@sizeOf(ZonTokenFlags) == 2);
}

test "ZonToken size and creation" {
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(ZonToken));
    try std.testing.expectEqual(@as(usize, 1), @sizeOf(ZonTokenKind));
    try std.testing.expectEqual(@as(usize, 2), @sizeOf(ZonTokenFlags));

    const span = Span.init(10, 20);

    // Test structural token
    const struct_start = ZonToken.structural(span, .struct_start, 0);
    try std.testing.expectEqual(ZonTokenKind.struct_start, struct_start.kind);
    try std.testing.expectEqual(@as(u8, 0), struct_start.depth);
    try std.testing.expect(struct_start.isOpenDelimiter());

    // Test field token
    const field_tok = ZonToken.field(span, 1, 42, true);
    try std.testing.expectEqual(ZonTokenKind.field_name, field_tok.kind);
    try std.testing.expectEqual(@as(u32, 42), field_tok.data);
    try std.testing.expect(field_tok.flags.is_quoted_field);

    // Test enum literal
    const enum_lit = ZonToken.enumLiteral(span, 1, 100);
    try std.testing.expectEqual(ZonTokenKind.enum_literal, enum_lit.kind);
    try std.testing.expectEqual(@as(u32, 100), enum_lit.data);
}

test "ZonToken categorization" {
    const span = Span.init(0, 1);

    const ws = ZonToken.trivia(span, .whitespace);
    try std.testing.expect(ws.isTrivia());

    const struct_tok = ZonToken.structural(span, .struct_start, 0);
    try std.testing.expect(struct_tok.isOpenDelimiter());
    try std.testing.expect(!struct_tok.isCloseDelimiter());

    const array_end = ZonToken.structural(span, .array_end, 1);
    try std.testing.expect(!array_end.isOpenDelimiter());
    try std.testing.expect(array_end.isCloseDelimiter());
}
