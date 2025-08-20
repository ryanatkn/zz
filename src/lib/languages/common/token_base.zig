const std = @import("std");
const Span = @import("../../parser/foundation/types/span.zig").Span;

/// Base token data shared by all language-specific tokens
/// Provides common fields that every token needs regardless of language
pub const TokenData = struct {
    /// Text span this token covers in source
    span: Span,
    
    /// Line number (1-based) for error reporting
    line: u32,
    
    /// Column number (1-based) for error reporting  
    column: u32,
    
    /// Nesting depth for brackets/braces/parens
    depth: u16,
    
    /// Additional flags packed for efficiency
    flags: TokenFlags = .{},
    
    /// Create token data with all fields
    pub fn init(span: Span, line: u32, column: u32, depth: u16) TokenData {
        return .{
            .span = span,
            .line = line,
            .column = column,
            .depth = depth,
            .flags = .{},
        };
    }
    
    /// Create token data with flags
    pub fn initWithFlags(span: Span, line: u32, column: u32, depth: u16, flags: TokenFlags) TokenData {
        return .{
            .span = span,
            .line = line,
            .column = column,
            .depth = depth,
            .flags = flags,
        };
    }
};

/// Flags for token metadata
pub const TokenFlags = packed struct {
    /// Token was inserted for error recovery
    is_inserted: bool = false,
    
    /// Token contains errors
    has_error: bool = false,
    
    /// Token is at end of line
    is_eol: bool = false,
    
    /// Token should be preserved in output (e.g., comments in JSON5)
    preserve: bool = false,
    
    /// Token has been modified from original (e.g., unescaped)
    is_transformed: bool = false,
    
    /// Reserved for future use
    _padding: u3 = 0,
};

/// Common token interface for conversion
pub const TokenInterface = struct {
    /// Get the span of any token type
    pub fn getSpan(token: anytype) Span {
        const T = @TypeOf(token);
        return switch (@typeInfo(T)) {
            .Union => switch (token) {
                inline else => |data| blk: {
                    const field_type = @TypeOf(data);
                    if (@typeInfo(field_type) == .Struct) {
                        if (@hasField(field_type, "data")) {
                            break :blk data.data.span;
                        } else if (@hasField(field_type, "span")) {
                            break :blk data.span;
                        }
                    }
                    // For simple TokenData fields
                    if (field_type == TokenData) {
                        break :blk data.span;
                    }
                    @compileError("Token variant missing span field");
                },
            },
            else => @compileError("Token must be a union type"),
        };
    }
    
    /// Get token data from any token variant
    pub fn getData(token: anytype) TokenData {
        const T = @TypeOf(token);
        return switch (@typeInfo(T)) {
            .Union => switch (token) {
                inline else => |data| blk: {
                    const field_type = @TypeOf(data);
                    if (@typeInfo(field_type) == .Struct) {
                        if (@hasField(field_type, "data")) {
                            break :blk data.data;
                        }
                    }
                    // For simple TokenData fields
                    if (field_type == TokenData) {
                        break :blk data;
                    }
                    @compileError("Token variant missing data field");
                },
            },
            else => @compileError("Token must be a union type"),
        };
    }
    
    /// Check if token has semantic value (for conversion)
    pub fn hasSemanticValue(token: anytype) bool {
        const T = @TypeOf(token);
        return switch (@typeInfo(T)) {
            .Union => switch (token) {
                inline else => |data| blk: {
                    const field_type = @TypeOf(data);
                    if (@typeInfo(field_type) == .Struct) {
                        // Check for value fields
                        if (@hasField(field_type, "value")) return true;
                        if (@hasField(field_type, "int_value")) return true;
                        if (@hasField(field_type, "float_value")) return true;
                    }
                    break :blk false;
                },
            },
            else => false,
        };
    }
};

// Tests
const testing = std.testing;

test "TokenData - initialization" {
    const span = Span.init(10, 20);
    const data = TokenData.init(span, 5, 15, 2);
    
    try testing.expect(data.span.eql(span));
    try testing.expectEqual(@as(u32, 5), data.line);
    try testing.expectEqual(@as(u32, 15), data.column);
    try testing.expectEqual(@as(u16, 2), data.depth);
    try testing.expect(!data.flags.is_inserted);
    try testing.expect(!data.flags.has_error);
}

test "TokenData - with flags" {
    const span = Span.init(0, 10);
    const flags = TokenFlags{
        .is_inserted = true,
        .has_error = false,
        .is_eol = true,
    };
    const data = TokenData.initWithFlags(span, 1, 1, 0, flags);
    
    try testing.expect(data.flags.is_inserted);
    try testing.expect(!data.flags.has_error);
    try testing.expect(data.flags.is_eol);
}

test "TokenFlags - packing" {
    // Ensure flags struct is packed to 1 byte
    try testing.expectEqual(@as(usize, 1), @sizeOf(TokenFlags));
}