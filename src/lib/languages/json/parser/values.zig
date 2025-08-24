/// JSON Parser - Value Parsing and String Processing
///
/// Specialized module for parsing JSON values and handling escape sequences
const std = @import("std");
const Span = @import("../../../span/mod.zig").Span;
const unpackSpan = @import("../../../span/mod.zig").unpackSpan;
const Token = @import("../token/mod.zig").Token;
const TokenKind = @import("../token/mod.zig").TokenKind;

// Use local JSON AST
const json_ast = @import("../ast/mod.zig");
const Node = json_ast.Node;

// Forward declare Parser from parser_core.zig
const Parser = @import("core.zig").Parser;

// =========================================================================
// Value Parsing Methods
// =========================================================================

pub fn parseString(parser: *Parser, allocator: std.mem.Allocator) !Node {
    const token = try parser.expect(.string_value);
    const span = unpackSpan(token.span);

    // Extract string value from source
    const raw = parser.source[span.start..span.end];

    // Process escape sequences (simplified for now)
    const value = try processStringEscapes(parser, allocator, raw);

    return Node{
        .string = .{
            .span = span,
            .value = value,
        },
    };
}

pub fn parseNumber(parser: *Parser, allocator: std.mem.Allocator) !Node {
    _ = allocator;
    const token = try parser.expect(.number_value);
    const span = unpackSpan(token.span);

    // Extract number text from source
    const text = parser.source[span.start..span.end];

    // Parse as float (JSON numbers are always floating point)
    const value = try std.fmt.parseFloat(f64, text);

    return Node{
        .number = .{
            .span = span,
            .value = value,
            .raw = text,
        },
    };
}

pub fn parseBoolean(parser: *Parser, allocator: std.mem.Allocator) !Node {
    _ = allocator;
    const token = parser.peek() orelse return error.UnexpectedEndOfInput;

    const value = switch (token.kind) {
        .boolean_true => true,
        .boolean_false => false,
        else => unreachable,
    };

    const span = unpackSpan(token.span);
    _ = try parser.advance();

    return Node{
        .boolean = .{
            .span = span,
            .value = value,
        },
    };
}

pub fn parseNull(parser: *Parser, allocator: std.mem.Allocator) !Node {
    _ = allocator;
    const token = try parser.expect(.null_value);
    const span = unpackSpan(token.span);

    return Node{
        .null = span,
    };
}

// =========================================================================
// String Processing Utilities
// =========================================================================

pub fn processStringEscapes(parser: *Parser, allocator: std.mem.Allocator, raw: []const u8) ![]const u8 {
    _ = parser;
    // Remove quotes if present
    const content = if (raw.len >= 2 and raw[0] == '"' and raw[raw.len - 1] == '"')
        raw[1 .. raw.len - 1]
    else
        raw;

    // Parse escape sequences
    return try parseEscapeSequences(allocator, content);
}

/// Parse escape sequences in a string
pub fn parseEscapeSequences(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    // Fast path: no escapes
    if (std.mem.indexOf(u8, input, "\\") == null) {
        return try allocator.dupe(u8, input);
    }

    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == '\\' and i + 1 < input.len) {
            switch (input[i + 1]) {
                '"' => try result.append('"'),
                '\\' => try result.append('\\'),
                '/' => try result.append('/'),
                'b' => try result.append('\x08'), // backspace
                'f' => try result.append('\x0C'), // form feed
                'n' => try result.append('\n'),
                'r' => try result.append('\r'),
                't' => try result.append('\t'),
                'u' => {
                    // Unicode escape: \uXXXX
                    if (i + 5 < input.len) {
                        const hex_digits = input[i + 2 .. i + 6];
                        if (isValidHexDigits(hex_digits)) {
                            const code_point = std.fmt.parseInt(u16, hex_digits, 16) catch {
                                // Invalid hex, keep as-is
                                try result.append(input[i]);
                                i += 1;
                                continue;
                            };

                            // Convert Unicode code point to UTF-8
                            var utf8_bytes: [4]u8 = undefined;
                            const len = std.unicode.utf8Encode(code_point, &utf8_bytes) catch {
                                // Invalid Unicode, keep as-is
                                try result.append(input[i]);
                                i += 1;
                                continue;
                            };
                            try result.appendSlice(utf8_bytes[0..len]);
                            i += 6;
                            continue;
                        }
                    }
                    // Invalid unicode escape, keep as-is
                    try result.append(input[i]);
                    i += 1;
                },
                else => {
                    // Unknown escape, keep as-is
                    try result.append(input[i]);
                    i += 1;
                },
            }
            i += 2;
        } else {
            try result.append(input[i]);
            i += 1;
        }
    }

    return result.toOwnedSlice();
}

/// Check if all characters are valid hex digits
pub fn isValidHexDigits(hex: []const u8) bool {
    for (hex) |c| {
        switch (c) {
            '0'...'9', 'a'...'f', 'A'...'F' => {},
            else => return false,
        }
    }
    return true;
}

// ============================================================================
// Tests
// ============================================================================

test "parseEscapeSequences - basic escapes" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const test_cases = [_]struct { input: []const u8, expected: []const u8 }{
        .{ .input = "hello", .expected = "hello" },
        .{ .input = "hello\\nworld", .expected = "hello\nworld" },
        .{ .input = "say \\\"hello\\\"", .expected = "say \"hello\"" },
        .{ .input = "path\\\\file", .expected = "path\\file" },
        .{ .input = "tab\\ttab", .expected = "tab\ttab" },
    };

    for (test_cases) |case| {
        const result = try parseEscapeSequences(allocator, case.input);
        defer allocator.free(result);
        try testing.expectEqualStrings(case.expected, result);
    }
}

test "parseEscapeSequences - unicode escapes" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const result = try parseEscapeSequences(allocator, "hello\\u0041world");
    defer allocator.free(result);
    try testing.expectEqualStrings("helloAworld", result);
}

test "isValidHexDigits" {
    const testing = std.testing;

    try testing.expect(isValidHexDigits("0123"));
    try testing.expect(isValidHexDigits("ABEF"));
    try testing.expect(isValidHexDigits("9aF2"));
    try testing.expect(!isValidHexDigits("GHIJ"));
    try testing.expect(!isValidHexDigits("012G"));
}
