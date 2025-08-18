const std = @import("std");

/// ZON-specific utility functions
///
/// This module contains helpers specific to ZON syntax and semantics.
/// Keeping these ZON-specific avoids generic overhead and allows
/// for optimizations specific to ZON's patterns.
/// Check if a string is a valid ZON identifier
pub fn isValidIdentifier(text: []const u8) bool {
    if (text.len == 0) return false;

    // Check first character
    if (!std.ascii.isAlphabetic(text[0]) and text[0] != '_') {
        return false;
    }

    // Check remaining characters
    for (text[1..]) |char| {
        if (!std.ascii.isAlphanumeric(char) and char != '_') {
            return false;
        }
    }

    return true;
}

/// Process a field name, handling dot prefix
pub fn processFieldName(text: []const u8) []const u8 {
    if (text.len > 0 and text[0] == '.') {
        return text[1..];
    }
    return text;
}

/// Extract the actual field name from a field node text
/// Handles: .field, @"field", .@"field"
pub fn extractFieldName(text: []const u8) []const u8 {
    var field_name = text;

    // Remove leading dot
    if (field_name.len > 0 and field_name[0] == '.') {
        field_name = field_name[1..];
    }

    // Handle quoted identifiers
    if (extractQuotedIdentifier(field_name)) |unquoted| {
        return unquoted;
    }

    // Handle @"..." format directly
    if (field_name.len >= 4 and field_name[0] == '@' and field_name[1] == '"') {
        if (std.mem.lastIndexOf(u8, field_name, "\"")) |end_pos| {
            if (end_pos > 2) {
                return field_name[2..end_pos];
            }
        }
    }

    return field_name;
}

/// Combine a dot operator and identifier into a field name
/// Returns the input text if it can't be allocated
pub fn combineFieldName(allocator: std.mem.Allocator, dot_text: []const u8, id_text: []const u8) ![]const u8 {
    if (std.mem.eql(u8, dot_text, ".")) {
        return std.fmt.allocPrint(allocator, ".{s}", .{id_text});
    }
    // Fallback if not a simple dot operator
    return allocator.dupe(u8, id_text);
}

/// Combine field name without allocation (into a buffer)
/// Returns the number of bytes written
pub fn combineFieldNameBuf(buffer: []u8, dot_text: []const u8, id_text: []const u8) !usize {
    if (std.mem.eql(u8, dot_text, ".")) {
        if (buffer.len < 1 + id_text.len) return error.BufferTooSmall;
        buffer[0] = '.';
        @memcpy(buffer[1..][0..id_text.len], id_text);
        return 1 + id_text.len;
    }
    // Fallback if not a simple dot operator
    if (buffer.len < id_text.len) return error.BufferTooSmall;
    @memcpy(buffer[0..id_text.len], id_text);
    return id_text.len;
}

/// Add dot prefix to field name if not present
pub fn ensureDotPrefix(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
    if (text.len > 0 and text[0] == '.') {
        return allocator.dupe(u8, text);
    }
    return std.fmt.allocPrint(allocator, ".{s}", .{text});
}

/// Normalize a field name for consistent processing
/// Removes dot prefix and handles quoted identifiers
pub fn normalizeFieldName(text: []const u8) []const u8 {
    return extractFieldName(text);
}

/// Extract field name from quoted identifier (@"name")
pub fn extractQuotedIdentifier(text: []const u8) ?[]const u8 {
    if (text.len < 4) return null; // Need at least @"x"

    if (text[0] == '@' and text[1] == '"') {
        // Find closing quote
        if (std.mem.lastIndexOf(u8, text, "\"")) |end_pos| {
            if (end_pos > 2) {
                return text[2..end_pos];
            }
        }
    }

    // Also handle .@"name" format
    if (text.len >= 5 and text[0] == '.' and text[1] == '@' and text[2] == '"') {
        if (std.mem.lastIndexOf(u8, text, "\"")) |end_pos| {
            if (end_pos > 3) {
                return text[3..end_pos];
            }
        }
    }

    return null;
}

/// Detect number format from text
pub const NumberFormat = enum {
    decimal,
    hexadecimal,
    binary,
    octal,
    float,
    invalid,
};

pub fn detectNumberFormat(text: []const u8) NumberFormat {
    if (text.len == 0) return .invalid;

    // Check for prefixes
    if (text.len > 2) {
        if (std.mem.startsWith(u8, text, "0x") or std.mem.startsWith(u8, text, "0X")) {
            return .hexadecimal;
        }
        if (std.mem.startsWith(u8, text, "0b") or std.mem.startsWith(u8, text, "0B")) {
            return .binary;
        }
        if (std.mem.startsWith(u8, text, "0o") or std.mem.startsWith(u8, text, "0O")) {
            return .octal;
        }
    }

    // Check for float (has decimal point or exponent)
    if (std.mem.indexOf(u8, text, ".") != null or
        std.mem.indexOf(u8, text, "e") != null or
        std.mem.indexOf(u8, text, "E") != null)
    {
        return .float;
    }

    // Default to decimal
    return .decimal;
}

/// Parse number with detected format
pub fn parseNumber(comptime T: type, text: []const u8) !T {
    const format = detectNumberFormat(text);

    const type_info = @typeInfo(T);

    switch (type_info) {
        .int => {
            const base: u8 = switch (format) {
                .hexadecimal => 16,
                .binary => 2,
                .octal => 8,
                .decimal => 10,
                else => return error.InvalidNumber,
            };
            return std.fmt.parseInt(T, text, base);
        },
        .float => {
            if (format == .float or format == .decimal) {
                return std.fmt.parseFloat(T, text);
            }
            return error.InvalidNumber;
        },
        else => return error.UnsupportedType,
    }
}

/// Check if text needs quotes in ZON
pub fn needsQuotes(text: []const u8) bool {
    // Empty string needs quotes
    if (text.len == 0) return true;

    // Check if it's a keyword
    if (isKeyword(text)) return true;

    // Check if it's a valid identifier
    if (!isValidIdentifier(text)) return true;

    return false;
}

/// Check if text is a ZON keyword
pub fn isKeyword(text: []const u8) bool {
    const keywords = [_][]const u8{
        "true",
        "false",
        "null",
        "undefined",
    };

    for (keywords) |keyword| {
        if (std.mem.eql(u8, text, keyword)) {
            return true;
        }
    }

    return false;
}

/// Escape a string for ZON output
pub fn escapeString(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    for (text) |char| {
        switch (char) {
            '\n' => try result.appendSlice("\\n"),
            '\t' => try result.appendSlice("\\t"),
            '\r' => try result.appendSlice("\\r"),
            '\\' => try result.appendSlice("\\\\"),
            '"' => try result.appendSlice("\\\""),
            else => {
                if (std.ascii.isPrint(char)) {
                    try result.append(char);
                } else {
                    // Non-printable character, use hex escape
                    try result.writer().print("\\x{x:0>2}", .{char});
                }
            },
        }
    }

    return result.toOwnedSlice();
}

/// Remove quotes from a string if present
pub fn unquote(text: []const u8) []const u8 {
    if (text.len >= 2) {
        if ((text[0] == '"' and text[text.len - 1] == '"') or
            (text[0] == '\'' and text[text.len - 1] == '\''))
        {
            return text[1 .. text.len - 1];
        }
    }
    return text;
}

/// Check if a character is valid in a ZON identifier
pub fn isIdentifierChar(char: u8) bool {
    return std.ascii.isAlphanumeric(char) or char == '_';
}

/// Check if a character can start a ZON identifier
pub fn isIdentifierStart(char: u8) bool {
    return std.ascii.isAlphabetic(char) or char == '_';
}

/// Get the value node from a field assignment node
/// Handles both "field = value" (3 children) and "field value" (2 children) patterns
pub fn getFieldValue(field_assignment: anytype) ?@TypeOf(field_assignment) {
    if (field_assignment.children.len >= 3) {
        // field_name = value (with equals token)
        return field_assignment.children[2];
    } else if (field_assignment.children.len >= 2) {
        // field_name value (no equals token)
        return field_assignment.children[1];
    }
    return null;
}

/// Check if text is a quoted identifier (@"...")
pub fn isQuotedIdentifier(text: []const u8) bool {
    return text.len >= 4 and
        text[0] == '@' and
        text[1] == '"' and
        text[text.len - 1] == '"';
}

/// Check if a field name needs quoting (@"...")
pub fn needsFieldQuoting(name: []const u8) bool {
    // Keywords need quoting
    if (isKeyword(name)) return true;

    // Non-identifiers need quoting
    if (!isValidIdentifier(name)) return true;

    return false;
}
