const std = @import("std");
const TokenData = @import("../common/token_base.zig").TokenData;
const Span = @import("../../parser/foundation/types/span.zig").Span;

/// Rich token types for ZON (Zig Object Notation)
/// Extends JSON with Zig-specific features
pub const ZonToken = union(enum) {
    // Structural tokens (same as JSON)
    object_start: TokenData,
    object_end: TokenData,
    array_start: TokenData,
    array_end: TokenData,
    comma: TokenData,
    colon: TokenData,
    equals: TokenData,  // ZON uses = for struct field assignment
    
    // Identifiers (ZON allows unquoted field names)
    identifier: struct {
        data: TokenData,
        text: []const u8,
        /// Whether this is a builtin identifier (@import, etc.)
        is_builtin: bool,
    },
    
    // Field name (can be identifier or string)
    field_name: struct {
        data: TokenData,
        /// The field name text (unquoted)
        name: []const u8,
        /// Original text (may include quotes if string)
        raw: []const u8,
        /// Whether field name was quoted
        is_quoted: bool,
    },
    
    // String value (supports Zig string literals)
    string_value: struct {
        data: TokenData,
        /// Unescaped string value
        value: []const u8,
        /// Original text including quotes
        raw: []const u8,
        /// Whether the string contained escape sequences
        has_escapes: bool,
        /// Whether this is a multiline string (\\)
        is_multiline: bool,
    },
    
    // Number value with Zig number formats
    number_value: struct {
        data: TokenData,
        /// Original text representation
        raw: []const u8,
        /// Parsed as integer if possible
        int_value: ?i128,  // Zig supports larger integers
        /// Parsed as float
        float_value: ?f64,
        /// Number base (2, 8, 10, 16)
        base: u8,
        /// Whether number has underscores
        has_underscores: bool,
        /// Whether number is explicitly a float
        is_float: bool,
    },
    
    // Character literal (Zig-specific)
    char_literal: struct {
        data: TokenData,
        value: u21,  // Unicode codepoint
        raw: []const u8,
    },
    
    // Boolean value
    boolean_value: struct {
        data: TokenData,
        value: bool,
    },
    
    // Null value
    null_value: TokenData,
    
    // Undefined value (Zig-specific)
    undefined_value: TokenData,
    
    // Enum literal (Zig-specific) .EnumValue
    enum_literal: struct {
        data: TokenData,
        name: []const u8,
    },
    
    // Struct literal indicator
    struct_literal: TokenData,  // .{}
    
    // Comments (Zig-style)
    comment: struct {
        data: TokenData,
        text: []const u8,
        kind: CommentKind,
    },
    
    // Whitespace
    whitespace: struct {
        data: TokenData,
        text: []const u8,
    },
    
    // Error token for recovery
    invalid: struct {
        data: TokenData,
        text: []const u8,
        expected: []const u8,
    },
    
    /// Get the span of this token
    pub fn span(self: ZonToken) Span {
        return switch (self) {
            .object_start, .object_end, .array_start, .array_end,
            .comma, .colon, .equals, .null_value, .undefined_value,
            .struct_literal => |data| data.span,
            inline else => |variant| variant.data.span,
        };
    }
    
    /// Get the token data
    pub fn tokenData(self: ZonToken) TokenData {
        return switch (self) {
            .object_start, .object_end, .array_start, .array_end,
            .comma, .colon, .equals, .null_value, .undefined_value,
            .struct_literal => |data| data,
            inline else => |variant| variant.data,
        };
    }
    
    /// Get the depth at this token
    pub fn depth(self: ZonToken) u16 {
        return self.tokenData().depth;
    }
    
    /// Check if this is a structural delimiter
    pub fn isDelimiter(self: ZonToken) bool {
        return switch (self) {
            .object_start, .object_end, .array_start, .array_end,
            .comma, .colon, .equals => true,
            else => false,
        };
    }
    
    /// Check if this is an opening delimiter
    pub fn isOpenDelimiter(self: ZonToken) bool {
        return switch (self) {
            .object_start, .array_start => true,
            else => false,
        };
    }
    
    /// Check if this is a closing delimiter
    pub fn isCloseDelimiter(self: ZonToken) bool {
        return switch (self) {
            .object_end, .array_end => true,
            else => false,
        };
    }
    
    /// Check if this is a value token
    pub fn isValue(self: ZonToken) bool {
        return switch (self) {
            .string_value, .number_value, .char_literal, .boolean_value,
            .null_value, .undefined_value, .enum_literal, .struct_literal,
            .object_start, .array_start => true,
            else => false,
        };
    }
    
    /// Check if this is trivia (whitespace/comment)
    pub fn isTrivia(self: ZonToken) bool {
        return switch (self) {
            .whitespace, .comment => true,
            else => false,
        };
    }
    
    /// Get text representation for debugging
    pub fn text(self: ZonToken) []const u8 {
        return switch (self) {
            .object_start => "{",
            .object_end => "}",
            .array_start => "[",
            .array_end => "]",
            .comma => ",",
            .colon => ":",
            .equals => "=",
            .identifier => |i| i.text,
            .field_name => |f| f.raw,
            .string_value => |s| s.raw,
            .number_value => |n| n.raw,
            .char_literal => |c| c.raw,
            .boolean_value => |b| if (b.value) "true" else "false",
            .null_value => "null",
            .undefined_value => "undefined",
            .enum_literal => |e| e.name,
            .struct_literal => ".{}",
            .comment => |c| c.text,
            .whitespace => |w| w.text,
            .invalid => |i| i.text,
        };
    }
};

/// Comment types for ZON
pub const CommentKind = enum {
    line,       // // comment
    doc,        // /// doc comment
    container,  // //! container doc comment
};

/// Create a simple structural token
pub fn structural(kind: StructuralKind, data: TokenData) ZonToken {
    return switch (kind) {
        .object_start => ZonToken{ .object_start = data },
        .object_end => ZonToken{ .object_end = data },
        .array_start => ZonToken{ .array_start = data },
        .array_end => ZonToken{ .array_end = data },
        .comma => ZonToken{ .comma = data },
        .colon => ZonToken{ .colon = data },
        .equals => ZonToken{ .equals = data },
    };
}

pub const StructuralKind = enum {
    object_start,
    object_end,
    array_start,
    array_end,
    comma,
    colon,
    equals,
};

// Tests
const testing = std.testing;

test "ZonToken - structural tokens" {
    const span = Span.init(0, 1);
    const data = TokenData.init(span, 1, 1, 0);
    
    const token = structural(.equals, data);
    try testing.expect(token.isDelimiter());
    try testing.expectEqualStrings("=", token.text());
}

test "ZonToken - identifier token" {
    const span = Span.init(10, 20);
    const data = TokenData.init(span, 1, 11, 1);
    
    const token = ZonToken{
        .identifier = .{
            .data = data,
            .text = "myField",
            .is_builtin = false,
        },
    };
    
    try testing.expect(!token.isDelimiter());
    try testing.expect(!token.isValue());
    try testing.expectEqualStrings("myField", token.text());
}

test "ZonToken - field name" {
    const span = Span.init(5, 15);
    const data = TokenData.init(span, 1, 6, 1);
    
    // Unquoted field
    const unquoted = ZonToken{
        .field_name = .{
            .data = data,
            .name = "config",
            .raw = "config",
            .is_quoted = false,
        },
    };
    
    try testing.expectEqualStrings("config", unquoted.text());
    try testing.expect(!unquoted.field_name.is_quoted);
    
    // Quoted field
    const quoted = ZonToken{
        .field_name = .{
            .data = data,
            .name = "config-file",
            .raw = "\"config-file\"",
            .is_quoted = true,
        },
    };
    
    try testing.expectEqualStrings("\"config-file\"", quoted.text());
    try testing.expect(quoted.field_name.is_quoted);
}

test "ZonToken - number with underscores" {
    const span = Span.init(20, 30);
    const data = TokenData.init(span, 2, 5, 1);
    
    const token = ZonToken{
        .number_value = .{
            .data = data,
            .raw = "1_000_000",
            .int_value = 1000000,
            .float_value = null,
            .base = 10,
            .has_underscores = true,
            .is_float = false,
        },
    };
    
    try testing.expect(token.isValue());
    try testing.expectEqualStrings("1_000_000", token.text());
    try testing.expect(token.number_value.has_underscores);
    try testing.expectEqual(@as(?i128, 1000000), token.number_value.int_value);
}

test "ZonToken - hex number" {
    const span = Span.init(30, 36);
    const data = TokenData.init(span, 3, 1, 2);
    
    const token = ZonToken{
        .number_value = .{
            .data = data,
            .raw = "0xFF",
            .int_value = 255,
            .float_value = null,
            .base = 16,
            .has_underscores = false,
            .is_float = false,
        },
    };
    
    try testing.expectEqual(@as(u8, 16), token.number_value.base);
    try testing.expectEqual(@as(?i128, 255), token.number_value.int_value);
}

test "ZonToken - char literal" {
    const span = Span.init(40, 43);
    const data = TokenData.init(span, 4, 1, 0);
    
    const token = ZonToken{
        .char_literal = .{
            .data = data,
            .value = 'a',
            .raw = "'a'",
        },
    };
    
    try testing.expect(token.isValue());
    try testing.expectEqualStrings("'a'", token.text());
    try testing.expectEqual(@as(u21, 'a'), token.char_literal.value);
}

test "ZonToken - enum literal" {
    const span = Span.init(50, 58);
    const data = TokenData.init(span, 5, 1, 1);
    
    const token = ZonToken{
        .enum_literal = .{
            .data = data,
            .name = ".Success",
        },
    };
    
    try testing.expect(token.isValue());
    try testing.expectEqualStrings(".Success", token.text());
}

test "ZonToken - undefined value" {
    const span = Span.init(60, 69);
    const data = TokenData.init(span, 6, 1, 0);
    
    const token = ZonToken{
        .undefined_value = data,
    };
    
    try testing.expect(token.isValue());
    try testing.expectEqualStrings("undefined", token.text());
}