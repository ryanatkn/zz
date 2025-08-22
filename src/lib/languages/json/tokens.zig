const std = @import("std");
const TokenData = @import("../../token/data.zig").TokenData;
const Span = @import("../../span/mod.zig").Span;

/// Rich token types for JSON with full semantic information
/// Each variant carries the maximum amount of information available at lex time
pub const JsonToken = union(enum) {
    // Structural tokens
    object_start: TokenData,
    object_end: TokenData,
    array_start: TokenData,
    array_end: TokenData,
    comma: TokenData,
    colon: TokenData,

    // Property name (object key)
    property_name: struct {
        data: TokenData,
        /// Unescaped string value
        value: []const u8,
        /// Original text including quotes
        raw: []const u8,
        /// Whether the string contained escape sequences
        has_escapes: bool,
    },

    // String value (in arrays or as object values)
    string_value: struct {
        data: TokenData,
        /// Unescaped string value
        value: []const u8,
        /// Original text including quotes
        raw: []const u8,
        /// Whether the string contained escape sequences
        has_escapes: bool,
    },

    // Decimal integer (base 10)
    decimal_int: struct {
        data: TokenData,
        /// Original text representation
        raw: []const u8,
        /// Parsed integer value
        value: i64,
    },

    // Hexadecimal integer (0x prefix)
    hex_int: struct {
        data: TokenData,
        /// Original text representation
        raw: []const u8,
        /// Parsed unsigned value
        value: u64,
    },

    // Floating point number (has decimal point)
    float: struct {
        data: TokenData,
        /// Original text representation
        raw: []const u8,
        /// Parsed float value
        value: f64,
    },

    // Scientific notation number (has e/E)
    scientific: struct {
        data: TokenData,
        /// Original text representation
        raw: []const u8,
        /// Parsed float value
        value: f64,
    },

    // Boolean value
    boolean_value: struct {
        data: TokenData,
        value: bool,
    },

    // Null value
    null_value: TokenData,

    // JSON5 extensions
    comment: struct {
        data: TokenData,
        text: []const u8,
        kind: CommentKind,
    },

    // Whitespace (usually filtered but available if needed)
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
    pub fn span(self: JsonToken) Span {
        return switch (self) {
            .object_start, .object_end, .array_start, .array_end, .comma, .colon, .null_value => |data| data.span,
            inline else => |variant| variant.data.span,
        };
    }

    /// Get the token data
    pub fn tokenData(self: JsonToken) TokenData {
        return switch (self) {
            .object_start, .object_end, .array_start, .array_end, .comma, .colon, .null_value => |data| data,
            inline else => |variant| variant.data,
        };
    }

    /// Get the depth at this token
    pub fn depth(self: JsonToken) u16 {
        return self.tokenData().depth;
    }

    /// Check if this is a structural delimiter
    pub fn isDelimiter(self: JsonToken) bool {
        return switch (self) {
            .object_start, .object_end, .array_start, .array_end, .comma, .colon => true,
            else => false,
        };
    }

    /// Check if this is an opening delimiter
    pub fn isOpenDelimiter(self: JsonToken) bool {
        return switch (self) {
            .object_start, .array_start => true,
            else => false,
        };
    }

    /// Check if this is a closing delimiter
    pub fn isCloseDelimiter(self: JsonToken) bool {
        return switch (self) {
            .object_end, .array_end => true,
            else => false,
        };
    }

    /// Check if this is a value token
    pub fn isValue(self: JsonToken) bool {
        return switch (self) {
            .string_value, .decimal_int, .hex_int, .float, .scientific, .boolean_value, .null_value, .object_start, .array_start => true,
            else => false,
        };
    }

    /// Check if this is trivia (whitespace/comment)
    pub fn isTrivia(self: JsonToken) bool {
        return switch (self) {
            .whitespace, .comment => true,
            else => false,
        };
    }

    /// Get text representation for debugging
    pub fn text(self: JsonToken) []const u8 {
        return switch (self) {
            .object_start => "{",
            .object_end => "}",
            .array_start => "[",
            .array_end => "]",
            .comma => ",",
            .colon => ":",
            .property_name => |p| p.raw,
            .string_value => |s| s.raw,
            .decimal_int => |n| n.raw,
            .hex_int => |n| n.raw,
            .float => |n| n.raw,
            .scientific => |n| n.raw,
            .boolean_value => |b| if (b.value) "true" else "false",
            .null_value => "null",
            .comment => |c| c.text,
            .whitespace => |w| w.text,
            .invalid => |i| i.text,
        };
    }
};

/// Comment types for JSON5
pub const CommentKind = enum {
    line, // // comment
    block, // /* comment */
};

/// Create a simple structural token
pub fn structural(kind: StructuralKind, data: TokenData) JsonToken {
    return switch (kind) {
        .object_start => JsonToken{ .object_start = data },
        .object_end => JsonToken{ .object_end = data },
        .array_start => JsonToken{ .array_start = data },
        .array_end => JsonToken{ .array_end = data },
        .comma => JsonToken{ .comma = data },
        .colon => JsonToken{ .colon = data },
    };
}

pub const StructuralKind = enum {
    object_start,
    object_end,
    array_start,
    array_end,
    comma,
    colon,
};

// Tests
const testing = std.testing;

test "JsonToken - structural tokens" {
    const span = Span.init(0, 1);
    const data = TokenData.init(span, 1, 1, 0);

    const token = structural(.object_start, data);
    try testing.expect(token.isDelimiter());
    try testing.expect(token.isOpenDelimiter());
    try testing.expect(!token.isCloseDelimiter());
    try testing.expectEqualStrings("{", token.text());
}

test "JsonToken - string token" {
    const span = Span.init(10, 17);
    const data = TokenData.init(span, 1, 11, 1);

    const token = JsonToken{
        .string_value = .{
            .data = data,
            .value = "hello",
            .raw = "\"hello\"",
            .has_escapes = false,
        },
    };

    try testing.expect(!token.isDelimiter());
    try testing.expect(token.isValue());
    try testing.expectEqualStrings("\"hello\"", token.text());
    try testing.expect(!token.string_value.has_escapes);
}

test "JsonToken - number token" {
    const span = Span.init(20, 25);
    const data = TokenData.init(span, 2, 5, 1);

    const token = JsonToken{
        .float = .{
            .data = data,
            .raw = "42.5",
            .value = 42.5,
        },
    };

    try testing.expect(token.isValue());
    try testing.expectEqualStrings("42.5", token.text());
    try testing.expectEqual(@as(f64, 42.5), token.float.value);
}

test "JsonToken - boolean and null" {
    const span = Span.init(30, 34);
    const data = TokenData.init(span, 3, 1, 2);

    const true_token = JsonToken{
        .boolean_value = .{
            .data = data,
            .value = true,
        },
    };

    try testing.expect(true_token.isValue());
    try testing.expectEqualStrings("true", true_token.text());
    try testing.expect(true_token.boolean_value.value);

    const null_token = JsonToken{
        .null_value = data,
    };

    try testing.expect(null_token.isValue());
    try testing.expectEqualStrings("null", null_token.text());
}

test "JsonToken - trivia" {
    const span = Span.init(40, 50);
    const data = TokenData.init(span, 4, 1, 0);

    const comment = JsonToken{
        .comment = .{
            .data = data,
            .text = "// test comment",
            .kind = .line,
        },
    };

    try testing.expect(comment.isTrivia());
    try testing.expect(!comment.isValue());
    try testing.expectEqualStrings("// test comment", comment.text());
}
