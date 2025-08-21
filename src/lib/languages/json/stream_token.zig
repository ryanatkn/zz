/// Lightweight JSON token - exactly 16 bytes
/// Optimized for streaming with minimal memory footprint
const std = @import("std");
const PackedSpan = @import("../../span/mod.zig").PackedSpan;
const packSpan = @import("../../span/mod.zig").packSpan;
const Span = @import("../../span/mod.zig").Span;

/// JSON-specific token kinds
pub const JsonTokenKind = enum(u8) {
    // Structural
    object_start,   // {
    object_end,     // }
    array_start,    // [
    array_end,      // ]
    comma,          // ,
    colon,          // :
    
    // Values
    property_name,  // "key" in object
    string_value,   // String literal
    number_value,   // Number (int or float)
    boolean_true,   // true
    boolean_false,  // false
    null_value,     // null
    
    // Trivia
    whitespace,
    comment,        // Non-standard but common
    
    // Special
    eof,
    err, // 'error' is reserved in Zig
};

/// Flags for additional token information (2 bytes)
pub const JsonTokenFlags = packed struct {
    has_escapes: bool = false,      // String contains escape sequences
    is_float: bool = false,          // Number is floating point
    is_negative: bool = false,       // Number is negative
    is_hex: bool = false,            // Number in hex format (non-standard)
    is_scientific: bool = false,     // Number in scientific notation
    multiline_comment: bool = false, // /* */ style comment
    _padding: u10 = 0,               // Reserved for future use
};

/// Lightweight JSON token - exactly 16 bytes
pub const JsonToken = extern struct {
    span: PackedSpan,           // 8 bytes - position in source
    kind: JsonTokenKind,        // 1 byte - token type
    depth: u8,                  // 1 byte - nesting depth
    flags: JsonTokenFlags,      // 2 bytes - additional info
    data: u32,                  // 4 bytes - string table index or inline value
    
    /// Create a new JSON token
    pub fn init(span: Span, kind: JsonTokenKind, depth: u8) JsonToken {
        return .{
            .span = packSpan(span),
            .kind = kind,
            .depth = depth,
            .flags = .{},
            .data = 0,
        };
    }
    
    /// Create a structural token (brackets, comma, colon)
    pub fn structural(span: Span, kind: JsonTokenKind, depth: u8) JsonToken {
        std.debug.assert(switch (kind) {
            .object_start, .object_end, .array_start, .array_end,
            .comma, .colon => true,
            else => false,
        });
        return init(span, kind, depth);
    }
    
    /// Create a string token (property name or value)
    pub fn string(span: Span, is_property: bool, depth: u8, string_index: u32, has_escapes: bool) JsonToken {
        var token = init(span, if (is_property) .property_name else .string_value, depth);
        token.data = string_index;
        token.flags.has_escapes = has_escapes;
        return token;
    }
    
    /// Create a number token
    pub fn number(span: Span, depth: u8, flags: JsonTokenFlags) JsonToken {
        var token = init(span, .number_value, depth);
        token.flags = flags;
        return token;
    }
    
    /// Create a boolean token
    pub fn boolean(span: Span, depth: u8, value: bool) JsonToken {
        return init(span, if (value) .boolean_true else .boolean_false, depth);
    }
    
    /// Create a null token
    pub fn nullValue(span: Span, depth: u8) JsonToken {
        return init(span, .null_value, depth);
    }
    
    /// Create trivia token (whitespace or comment)
    pub fn trivia(span: Span, kind: JsonTokenKind) JsonToken {
        std.debug.assert(kind == .whitespace or kind == .comment);
        return init(span, kind, 0);
    }
    
    /// Check if token is trivia
    pub fn isTrivia(self: JsonToken) bool {
        return self.kind == .whitespace or self.kind == .comment;
    }
    
    /// Check if token opens a scope
    pub fn isOpenDelimiter(self: JsonToken) bool {
        return self.kind == .object_start or self.kind == .array_start;
    }
    
    /// Check if token closes a scope
    pub fn isCloseDelimiter(self: JsonToken) bool {
        return self.kind == .object_end or self.kind == .array_end;
    }
    
    /// Get string table index (for string tokens)
    /// TODO: Rename to getAtomId() once migration complete
    pub fn getStringIndex(self: JsonToken) ?u32 {
        return switch (self.kind) {
            .property_name, .string_value => self.data,
            else => null,
        };
    }
    
    /// Get atom ID for this token's text content
    /// TODO: Replace getStringIndex with this method
    pub fn getAtomId(self: JsonToken) ?u32 {
        return self.getStringIndex();
    }
};

// Size assertion - must be exactly 16 bytes
comptime {
    std.debug.assert(@sizeOf(JsonToken) == 16);
    std.debug.assert(@sizeOf(JsonTokenKind) == 1);
    std.debug.assert(@sizeOf(JsonTokenFlags) == 2);
}

test "JsonToken size and creation" {
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(JsonToken));
    try std.testing.expectEqual(@as(usize, 1), @sizeOf(JsonTokenKind));
    try std.testing.expectEqual(@as(usize, 2), @sizeOf(JsonTokenFlags));
    
    const span = Span.init(10, 20);
    
    // Test structural token
    const obj_start = JsonToken.structural(span, .object_start, 0);
    try std.testing.expectEqual(JsonTokenKind.object_start, obj_start.kind);
    try std.testing.expectEqual(@as(u8, 0), obj_start.depth);
    try std.testing.expect(obj_start.isOpenDelimiter());
    
    // Test string token
    const str = JsonToken.string(span, false, 1, 42, true);
    try std.testing.expectEqual(JsonTokenKind.string_value, str.kind);
    try std.testing.expectEqual(@as(u32, 42), str.data);
    try std.testing.expect(str.flags.has_escapes);
    
    // Test boolean token
    const bool_true = JsonToken.boolean(span, 2, true);
    try std.testing.expectEqual(JsonTokenKind.boolean_true, bool_true.kind);
    
    const bool_false = JsonToken.boolean(span, 2, false);
    try std.testing.expectEqual(JsonTokenKind.boolean_false, bool_false.kind);
}

test "JsonToken categorization" {
    const span = Span.init(0, 1);
    
    const ws = JsonToken.trivia(span, .whitespace);
    try std.testing.expect(ws.isTrivia());
    
    const obj = JsonToken.structural(span, .object_start, 0);
    try std.testing.expect(obj.isOpenDelimiter());
    try std.testing.expect(!obj.isCloseDelimiter());
    
    const arr_end = JsonToken.structural(span, .array_end, 1);
    try std.testing.expect(!arr_end.isOpenDelimiter());
    try std.testing.expect(arr_end.isCloseDelimiter());
}