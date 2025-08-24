const std = @import("std");
const char_utils = @import("../../../char/mod.zig");

// Using local ZON AST types
const Node = @import("../ast/nodes.zig").Node;

/// ZON-specific utility functions
///
/// This module contains ONLY helpers specific to ZON syntax and semantics.
/// Generic AST manipulation functions have been moved to src/lib/ast/utils.zig
/// for reuse across all language modules.

// ============================================================================
// ZON Node Utility Functions (using tagged unions)
// ============================================================================

/// Check if a node is empty (for containers)
pub fn isEmpty(node: Node) bool {
    return switch (node) {
        .object => |obj| obj.fields.len == 0,
        .array => |arr| arr.elements.len == 0,
        else => false, // Non-containers are not considered "empty"
    };
}

/// Check if a container has at least minimum elements/fields
pub fn hasMinimumElements(node: Node, min_count: usize) bool {
    return switch (node) {
        .object => |obj| obj.fields.len >= min_count,
        .array => |arr| arr.elements.len >= min_count,
        else => false,
    };
}

/// Count the number of field assignments in an object
pub fn countFieldAssignments(node: Node) u32 {
    return switch (node) {
        .object => |obj| @intCast(obj.fields.len),
        else => 0,
    };
}

/// Check if a node is an object
pub fn isObjectNode(node: Node) bool {
    return node == .object;
}

/// Check if a node is an array
pub fn isArrayNode(node: Node) bool {
    return node == .array;
}

/// Check if a node has a specific tag (replaces rule_id checking)
pub fn hasTag(node: Node, tag: @typeInfo(Node).Union.tag_type.?) bool {
    return @as(@typeInfo(Node).Union.tag_type.?, node) == tag;
}

// ============================================================================
// ZON-Specific Identifier and Field Name Processing
// ============================================================================

/// Check if a string is a valid ZON identifier
pub fn isValidIdentifier(text: []const u8) bool {
    if (text.len == 0) return false;

    // Check first character
    if (!char_utils.isAlpha(text[0]) and text[0] != '_') {
        return false;
    }

    // Check remaining characters
    for (text[1..]) |char| {
        if (!char_utils.isAlphaNumeric(char) and char != '_') {
            return false;
        }
    }

    return true;
}

/// Process a field name, handling ZON dot prefix
pub fn processFieldName(text: []const u8) []const u8 {
    if (text.len > 0 and text[0] == '.') {
        return text[1..];
    }
    return text;
}

/// Extract the actual field name from a ZON field node text
/// Handles ZON-specific formats: .field, @"field", .@"field"
pub fn extractFieldName(text: []const u8) []const u8 {
    var field_name = text;

    // Remove leading dot (ZON field prefix)
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

/// Extract field name from ZON quoted identifier (@"name")
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

    // Also handle .@"name" format (ZON field with quoted identifier)
    if (text.len >= 5 and text[0] == '.' and text[1] == '@' and text[2] == '"') {
        if (std.mem.lastIndexOf(u8, text, "\"")) |end_pos| {
            if (end_pos > 3) {
                return text[3..end_pos];
            }
        }
    }

    return null;
}

/// Combine a dot operator and identifier into a ZON field name
pub fn combineFieldName(allocator: std.mem.Allocator, dot_text: []const u8, id_text: []const u8) ![]const u8 {
    if (std.mem.eql(u8, dot_text, ".")) {
        return std.fmt.allocPrint(allocator, ".{s}", .{id_text});
    }
    // Fallback if not a simple dot operator
    return allocator.dupe(u8, id_text);
}

/// Combine field name without allocation (into a buffer) - ZON specific
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

/// Add dot prefix to field name if not present (ZON convention)
pub fn ensureDotPrefix(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
    if (text.len > 0 and text[0] == '.') {
        return allocator.dupe(u8, text);
    }
    return std.fmt.allocPrint(allocator, ".{s}", .{text});
}

/// Normalize a ZON field name for consistent processing
pub fn normalizeFieldName(text: []const u8) []const u8 {
    return extractFieldName(text);
}

/// Check if text is a quoted identifier (@"...") - ZON specific
pub fn isQuotedIdentifier(text: []const u8) bool {
    return text.len >= 4 and
        text[0] == '@' and
        text[1] == '"' and
        text[text.len - 1] == '"';
}

/// Check if a ZON field name needs quoting (@"...")
pub fn needsFieldQuoting(name: []const u8) bool {
    // Keywords need quoting
    if (isKeyword(name)) return true;

    // Non-identifiers need quoting
    if (!isValidIdentifier(name)) return true;

    return false;
}

// ============================================================================
// ZON-Specific Number and Literal Processing
// ============================================================================

/// Detect ZON number format from text
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

    // Check for ZON prefixes
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

/// Parse ZON number with detected format
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

/// Check if text needs quotes in ZON output
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

// ============================================================================
// ZON-Specific AST Helper Functions
// ============================================================================

/// Get the value node from a ZON field assignment node
pub fn getFieldValue(field_assignment: Node) ?*Node {
    return switch (field_assignment) {
        .field => |field| field.value,
        else => null,
    };
}

/// Get ZON field name from a field_assignment node
pub fn getFieldName(node: Node) ?[]const u8 {
    return switch (node) {
        .field => |field| field.getFieldName(),
        else => null,
    };
}

/// Check if a node represents a ZON field assignment
pub fn isFieldAssignment(node: Node) bool {
    return node == .field;
}

/// Process a ZON field assignment node and return field name and value node
pub fn processFieldAssignment(node: Node) ?struct {
    field_name: []const u8,
    value_node: *Node,
} {
    return switch (node) {
        .field => |field| .{
            .field_name = field.getFieldName() orelse return null,
            .value_node = field.value,
        },
        else => null,
    };
}

/// Get field value by name from a ZON object node using ZON-specific field processing
pub fn getFieldByName(node: Node, target_field_name: []const u8) ?*Node {
    return switch (node) {
        .object => |obj| obj.findField(target_field_name),
        else => null,
    };
}

// Note: Generic AST manipulation functions like isObjectNode, isArrayNode,
// isTerminalOfType, etc. have been moved to src/lib/ast/utils.zig for reuse
// across all language modules. Import them from there when needed.

// ============================================================================
// ZON-Specific Validation and Conversion
// ============================================================================

/// Validate that a string is a valid ZON field name format
pub fn validateFieldName(name: []const u8) bool {
    if (name.len == 0) return false;

    // Check if it starts with a dot (optional in ZON)
    var actual_name = name;
    if (name[0] == '.') {
        actual_name = name[1..];
    }

    // Handle quoted identifiers
    if (isQuotedIdentifier(actual_name)) {
        const inner = extractQuotedIdentifier(actual_name) orelse return false;
        return inner.len > 0;
    }

    // Must be a valid identifier
    return isValidIdentifier(actual_name);
}

/// Convert a ZON field name to its canonical form for comparison
pub fn canonicalizeFieldName(name: []const u8) []const u8 {
    return normalizeFieldName(name);
}

/// Check if two ZON field names are equivalent (handles different representations)
pub fn fieldNamesEqual(name1: []const u8, name2: []const u8) bool {
    const canonical1 = canonicalizeFieldName(name1);
    const canonical2 = canonicalizeFieldName(name2);
    return std.mem.eql(u8, canonical1, canonical2);
}

/// Get text content from a node with fallback
pub fn getNodeText(node: Node, fallback: []const u8) []const u8 {
    return switch (node) {
        .field_name => |n| n.name,
        .identifier => |n| n.name,
        .string => |n| n.value, // String content, not the raw text with quotes
        else => fallback,
    };
}

/// Check if node has text content
pub fn hasText(node: Node) bool {
    return getNodeText(node, "").len > 0;
}

/// Check if a field assignment has simple values (no nested objects/arrays)
pub fn isSimpleFieldAssignment(node: Node) bool {
    if (!isFieldAssignment(node)) return false;

    const value_node = getFieldValue(node) orelse return false;
    return isSimpleTerminal(value_node.*);
}

/// Check if a node is a simple terminal (for formatting decisions)
pub fn isSimpleTerminal(node: Node) bool {
    return switch (node) {
        .string, .number, .boolean, .null, .identifier => true,
        else => false,
    };
}
