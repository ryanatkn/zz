/// ZON Streaming Parser - Direct streaming lexer integration
///
/// SIMPLIFIED: Uses streaming lexer directly, no token arrays
/// Handles ZON-specific features like .field syntax and enum literals
const std = @import("std");
const Span = @import("../../../span/mod.zig").Span;
const unpackSpan = @import("../../../span/mod.zig").unpackSpan;
const TokenIterator = @import("../../../token/iterator.zig").TokenIterator;
const Token = @import("../../../token/stream_token.zig").Token;
const ZonToken = @import("../token/types.zig").Token;
const TokenKind = @import("../token/types.zig").TokenKind;

// Use local ZON AST
const ast_nodes = @import("../ast/nodes.zig");
const AST = ast_nodes.AST;
const Node = ast_nodes.Node;
const NodeKind = ast_nodes.NodeKind;

/// ZON Parser using streaming lexer
///
/// Features:
/// - Direct streaming tokenization (no intermediate array)
/// - Support for ZON-specific syntax (.field, enum literals, etc.)
/// - Recursive descent parsing
/// - Error recovery
pub const Parser = struct {
    allocator: std.mem.Allocator,
    iterator: TokenIterator,
    source: []const u8,
    current: ?Token,
    errors: std.ArrayList(ParseError),
    allow_trailing_commas: bool,

    const Self = @This();

    pub const ParseError = struct {
        message: []const u8,
        span: Span,
        severity: Severity,

        pub const Severity = enum { err, warning };
    };

    pub const ParserOptions = struct {
        allow_trailing_commas: bool = true, // ZON commonly has trailing commas
        recover_from_errors: bool = true,
    };

    /// Initialize parser with streaming lexer
    pub fn init(allocator: std.mem.Allocator, source: []const u8, options: ParserOptions) !Self {
        var parser = Self{
            .allocator = allocator,
            .iterator = try TokenIterator.init(source, .zon),
            .source = source,
            .current = null,
            .errors = std.ArrayList(ParseError).init(allocator),
            .allow_trailing_commas = options.allow_trailing_commas,
        };

        // Prime the pump - get first token
        _ = try parser.advance();

        return parser;
    }

    pub fn deinit(self: *Self) void {
        for (self.errors.items) |err| {
            self.allocator.free(err.message);
        }
        self.errors.deinit();
    }

    /// Parse ZON into AST
    pub fn parse(self: *Self) !AST {
        // Allocate arena on heap so it persists with AST (same pattern as JSON)
        const arena = try self.allocator.create(std.heap.ArenaAllocator);
        arena.* = std.heap.ArenaAllocator.init(self.allocator);
        errdefer {
            arena.deinit();
            self.allocator.destroy(arena);
        }

        const arena_allocator = arena.allocator();

        // Parse root value using arena allocator
        const root_value = try self.parseValue(arena_allocator);

        // Create root node in arena
        const root_node = try arena_allocator.create(Node);
        root_node.* = root_value;

        // Check for trailing content
        if (self.current) |token| {
            switch (token) {
                .zon => |t| {
                    if (t.kind != .eof) {
                        const span = unpackSpan(t.span);
                        try self.addError("Unexpected token after ZON value", span);
                    }
                },
                else => unreachable,
            }
        }

        // Create AST with arena allocator
        var ast = AST.init(self.allocator);
        ast.root = root_node;
        ast.source = self.source; // Store source reference for formatting
        ast.arena = arena; // Store arena for cleanup

        return ast;
    }

    /// Get parse errors
    pub fn getErrors(self: *Self) []const ParseError {
        return self.errors.items;
    }

    // =========================================================================
    // Token Navigation
    // =========================================================================

    /// Advance to next meaningful token (skip trivia)
    fn advance(self: *Self) !?Token {
        while (self.iterator.next()) |token| {
            switch (token) {
                .zon => |t| {
                    // Skip trivia
                    if (t.kind == .whitespace or t.kind == .comment) {
                        continue;
                    }
                    self.current = token;
                    return token;
                },
                else => unreachable, // Parser only handles ZON
            }
        }
        self.current = null;
        return null;
    }

    /// Peek at current token
    fn peek(self: *Self) ?ZonToken {
        if (self.current) |token| {
            switch (token) {
                .zon => |t| return t,
                else => unreachable,
            }
        }
        return null;
    }

    /// Expect and consume a specific token kind
    fn expect(self: *Self, kind: TokenKind) !ZonToken {
        if (self.peek()) |token| {
            if (token.kind == kind) {
                const result = token;
                _ = try self.advance();
                return result;
            }
            const span = unpackSpan(token.span);
            // Use a static buffer to avoid memory leaks for error messages
            var buf: [128]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "Expected {s}, got {s}", .{ @tagName(kind), @tagName(token.kind) }) catch "Parse error";
            try self.addError(msg, span);
            return error.UnexpectedToken;
        }

        try self.addError("Unexpected end of input", Span.init(@intCast(self.source.len), @intCast(self.source.len)));
        return error.UnexpectedEndOfInput;
    }

    // =========================================================================
    // Value Parsing
    // =========================================================================

    fn parseValue(self: *Self, allocator: std.mem.Allocator) anyerror!Node {
        const token = self.peek() orelse {
            try self.addError("Unexpected end of input", Span.init(0, 0));
            return self.createErrorNode(allocator);
        };

        return switch (token.kind) {
            .string_value => self.parseString(allocator),
            .number_value => self.parseNumber(allocator),
            .boolean_true, .boolean_false => self.parseBoolean(allocator),
            .null_value => self.parseNull(allocator),
            .undefined => self.parseUndefined(allocator),
            .struct_start => self.parseStruct(allocator),
            .object_start => self.parseObject(allocator),
            .array_start => self.parseArray(allocator),
            .dot => self.parseEnumLiteral(allocator),
            .field_name => self.parseFieldName(allocator),
            .identifier => self.parseIdentifier(allocator),
            .import => self.parseImport(allocator),
            else => {
                const span = unpackSpan(token.span);
                const msg = try std.fmt.allocPrint(allocator, // Use arena allocator
                    "Unexpected token: {s}", .{@tagName(token.kind)});
                try self.addError(msg, span);
                _ = try self.advance(); // Skip bad token
                return self.createErrorNode(allocator);
            },
        };
    }

    fn parseString(self: *Self, allocator: std.mem.Allocator) !Node {
        const token = try self.expect(.string_value);
        const span = unpackSpan(token.span);

        // Extract string value from source
        const raw = self.source[span.start..span.end];

        // Process escape sequences
        const value = try self.processStringEscapes(allocator, raw);

        return Node{
            .string = .{
                .span = span,
                .value = value,
            },
        };
    }

    fn parseNumber(self: *Self, allocator: std.mem.Allocator) !Node {
        _ = allocator;
        const token = try self.expect(.number_value);
        const span = unpackSpan(token.span);

        // Extract number text from source
        const text = self.source[span.start..span.end];

        // ZON supports various number formats
        const value = if (std.mem.indexOf(u8, text, ".") != null or
            std.mem.indexOf(u8, text, "e") != null or
            std.mem.indexOf(u8, text, "E") != null)
            try std.fmt.parseFloat(f64, text)
        else blk: {
            const int_val = try std.fmt.parseInt(i64, text, 0);
            break :blk @as(f64, @floatFromInt(int_val));
        };

        return Node{
            .number = .{
                .span = span,
                .value = .{ .float = value },
                .raw = text,
            },
        };
    }

    fn parseBoolean(self: *Self, allocator: std.mem.Allocator) !Node {
        _ = allocator;
        const token = self.peek() orelse return error.UnexpectedEndOfInput;

        const value = switch (token.kind) {
            .boolean_true => true,
            .boolean_false => false,
            else => unreachable,
        };

        const span = unpackSpan(token.span);
        _ = try self.advance();

        return Node{
            .boolean = .{
                .span = span,
                .value = value,
            },
        };
    }

    fn parseNull(self: *Self, allocator: std.mem.Allocator) !Node {
        _ = allocator;
        const token = try self.expect(.null_value);
        const span = unpackSpan(token.span);

        return Node{
            .null = span,
        };
    }

    fn parseUndefined(self: *Self, allocator: std.mem.Allocator) !Node {
        _ = allocator;
        const token = try self.expect(.undefined);
        const span = unpackSpan(token.span);

        // ZON doesn't have undefined in AST, use null
        return Node{
            .null = span,
        };
    }

    fn parseIdentifier(self: *Self, allocator: std.mem.Allocator) !Node {
        const token = try self.expect(.identifier);
        const span = unpackSpan(token.span);
        const name = self.source[span.start..span.end];

        return Node{
            .identifier = .{
                .span = span,
                .name = try allocator.dupe(u8, name),
            },
        };
    }

    fn parseFieldName(self: *Self, allocator: std.mem.Allocator) !Node {
        const token = try self.expect(.field_name);
        const span = unpackSpan(token.span);
        const name = self.source[span.start..span.end];

        return Node{
            .field_name = .{
                .span = span,
                .name = try allocator.dupe(u8, name),
            },
        };
    }

    fn parseEnumLiteral(self: *Self, allocator: std.mem.Allocator) !Node {
        _ = try self.expect(.dot); // Consume the dot
        const token = try self.expect(.enum_literal);
        const span = unpackSpan(token.span);
        const name = self.source[span.start..span.end];

        // Use identifier for enum literals
        return Node{
            .identifier = .{
                .span = span,
                .name = try allocator.dupe(u8, name),
            },
        };
    }

    fn parseImport(self: *Self, allocator: std.mem.Allocator) !Node {
        _ = try self.expect(.import);

        _ = try self.expect(.paren_open);
        const path_node = try self.parseString(allocator);
        _ = try self.expect(.paren_close);

        // Return the string node for import path
        return path_node;
    }

    fn parseStruct(self: *Self, allocator: std.mem.Allocator) !Node {
        const start_token = try self.expect(.struct_start);
        const start_span = unpackSpan(start_token.span);

        var fields = std.ArrayList(Node).init(allocator);
        defer fields.deinit();

        // Check for empty struct
        if (self.peek()) |token| {
            if (token.kind == .struct_end) {
                const end_token = try self.expect(.struct_end);
                const end_span = unpackSpan(end_token.span);

                return Node{
                    .object = .{
                        .span = Span.init(start_span.start, end_span.end),
                        .fields = try fields.toOwnedSlice(),
                    },
                };
            }
        }

        // Parse fields - handle both named fields (.field = value) and positional values
        while (true) {
            // Check if this is a named field or positional value
            if (self.peek()) |token| {
                if (token.kind == .field_name) {
                    // Named field: .field = value
                    const field_token = try self.expect(.field_name);
                    const field_span = unpackSpan(field_token.span);
                    const field_name = self.source[field_span.start..field_span.end];

                    // Expect equals
                    _ = try self.expect(.equals);

                    // Check if we have a missing value (comma or } immediately after =)
                    if (self.peek()) |next| {
                        if (next.kind == .comma or next.kind == .struct_end) {
                            const span = unpackSpan(next.span);
                            try self.addError("Missing value after '='", span);
                            return error.MissingValue;
                        }
                    }

                    // Parse value
                    const value = try self.parseValue(allocator);

                    // Create field node
                    const field_name_node = try allocator.create(Node);
                    field_name_node.* = Node{
                        .field_name = .{
                            .span = field_span,
                            .name = try allocator.dupe(u8, field_name),
                        },
                    };
                    const value_node = try allocator.create(Node);
                    value_node.* = value;
                    const field = Node{
                        .field = .{
                            .span = Span.init(field_span.start, value.span().end),
                            .name = field_name_node,
                            .value = value_node,
                        },
                    };

                    try fields.append(field);
                } else if (token.kind == .struct_end) {
                    // End of struct
                    break;
                } else {
                    // Positional value (no field name) - for anonymous struct like .{ "a", "b", "c" }
                    const value = try self.parseValue(allocator);
                    try fields.append(value);
                }
            } else {
                try self.addError("Unexpected end of input in struct", Span.init(@intCast(self.source.len), @intCast(self.source.len)));
                break;
            }

            // Check for continuation
            if (self.peek()) |next_token| {
                if (next_token.kind == .comma) {
                    _ = try self.advance();

                    // Check for trailing comma
                    if (self.peek()) |next| {
                        if (next.kind == .struct_end) {
                            break;
                        }
                    }
                } else if (next_token.kind == .struct_end) {
                    break;
                } else {
                    const span = unpackSpan(next_token.span);
                    try self.addError("Expected ',' or '}'", span);
                    break;
                }
            } else {
                try self.addError("Unexpected end of input in struct", Span.init(@intCast(self.source.len), @intCast(self.source.len)));
                break;
            }
        }

        const end_token = try self.expect(.struct_end);
        const end_span = unpackSpan(end_token.span);

        return Node{
            .object = .{
                .span = Span.init(start_span.start, end_span.end),
                .fields = try fields.toOwnedSlice(),
            },
        };
    }

    fn parseObject(self: *Self, allocator: std.mem.Allocator) !Node {
        // ZON objects are similar to structs but without dots
        const start_token = try self.expect(.object_start);
        const start_span = unpackSpan(start_token.span);

        var properties = std.ArrayList(Node).init(allocator);
        defer properties.deinit();

        // Check for empty object
        if (self.peek()) |token| {
            if (token.kind == .object_end) {
                const end_token = try self.expect(.object_end);
                const end_span = unpackSpan(end_token.span);

                return Node{
                    .object = .{
                        .span = Span.init(start_span.start, end_span.end),
                        .fields = try properties.toOwnedSlice(),
                    },
                };
            }
        }

        // Parse properties
        while (true) {
            // Parse property (could be identifier or string key)
            const property = try self.parseValue(allocator);

            // Expect colon
            _ = try self.expect(.colon);

            // Parse value
            const value = try self.parseValue(allocator);

            // Create field node (using field for properties in ZON)
            const key_node = try allocator.create(Node);
            key_node.* = property;
            const value_node = try allocator.create(Node);
            value_node.* = value;
            const prop_node = Node{
                .field = .{
                    .span = Span.init(property.span().start, value.span().end),
                    .name = key_node,
                    .value = value_node,
                },
            };

            try properties.append(prop_node);

            // Check for continuation
            if (self.peek()) |token| {
                if (token.kind == .comma) {
                    _ = try self.advance();

                    // Check for trailing comma
                    if (self.peek()) |next| {
                        if (next.kind == .object_end) {
                            break;
                        }
                    }
                } else if (token.kind == .object_end) {
                    break;
                } else {
                    const span = unpackSpan(token.span);
                    try self.addError("Expected ',' or '}'", span);
                    break;
                }
            } else {
                break;
            }
        }

        const end_token = try self.expect(.object_end);
        const end_span = unpackSpan(end_token.span);

        return Node{
            .object = .{
                .span = Span.init(start_span.start, end_span.end),
                .fields = try properties.toOwnedSlice(),
            },
        };
    }

    fn parseArray(self: *Self, allocator: std.mem.Allocator) !Node {
        const start_token = try self.expect(.array_start);
        const start_span = unpackSpan(start_token.span);

        var elements = std.ArrayList(Node).init(allocator);
        defer elements.deinit();

        // Check for empty array
        if (self.peek()) |token| {
            if (token.kind == .array_end) {
                const end_token = try self.expect(.array_end);
                const end_span = unpackSpan(end_token.span);

                return Node{
                    .array = .{
                        .span = Span.init(start_span.start, end_span.end),
                        .elements = try elements.toOwnedSlice(),
                    },
                };
            }
        }

        // Parse elements
        while (true) {
            const element = try self.parseValue(allocator);
            try elements.append(element);

            // Check for continuation
            if (self.peek()) |token| {
                if (token.kind == .comma) {
                    _ = try self.advance();

                    // Check for trailing comma
                    if (self.peek()) |next| {
                        if (next.kind == .array_end) {
                            break;
                        }
                    }
                } else if (token.kind == .array_end) {
                    break;
                } else {
                    const span = unpackSpan(token.span);
                    try self.addError("Expected ',' or ']'", span);
                    break;
                }
            } else {
                break;
            }
        }

        const end_token = try self.expect(.array_end);
        const end_span = unpackSpan(end_token.span);

        return Node{
            .array = .{
                .span = Span.init(start_span.start, end_span.end),
                .elements = try elements.toOwnedSlice(),
            },
        };
    }

    // =========================================================================
    // Utilities
    // =========================================================================

    fn processStringEscapes(self: *Self, allocator: std.mem.Allocator, raw: []const u8) ![]const u8 {
        _ = self;
        // Remove quotes if present
        const content = if (raw.len >= 2 and raw[0] == '"' and raw[raw.len - 1] == '"')
            raw[1 .. raw.len - 1]
        else
            raw;

        // Parse ZON escape sequences (includes JSON escapes + multiline)
        return try parseZonEscapeSequences(allocator, content);
    }

    /// Parse escape sequences in a ZON string (includes JSON escapes + multiline strings)
    fn parseZonEscapeSequences(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
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
                    // Standard Zig/ZON escapes
                    '"' => try result.append('"'),
                    '\\' => try result.append('\\'), // \\ produces single backslash
                    '\'' => try result.append('\''), // Single quote (Zig has this, JSON doesn't)
                    'n' => try result.append('\n'),
                    'r' => try result.append('\r'),
                    't' => try result.append('\t'),
                    'x' => {
                        // Hex byte escape: \xNN (exactly 2 hex digits)
                        if (i + 4 <= input.len) {
                            const hex_digits = input[i + 2 .. i + 4];
                            if (isValidHexDigits(hex_digits)) {
                                const byte_val = std.fmt.parseInt(u8, hex_digits, 16) catch {
                                    // Invalid hex, keep as-is
                                    try result.append(input[i]);
                                    i += 1;
                                    continue;
                                };
                                try result.append(byte_val);
                                i += 4;
                                continue;
                            }
                        }
                        // Invalid hex escape, keep as-is
                        try result.append(input[i]);
                        i += 1;
                        continue;
                    },
                    'u' => {
                        // Unicode escape: \u{...} (1 or more hex digits)
                        if (i + 3 < input.len and input[i + 2] == '{') {
                            // Find closing brace
                            var end_pos: usize = i + 3;
                            while (end_pos < input.len and input[end_pos] != '}') {
                                end_pos += 1;
                            }

                            if (end_pos < input.len) { // Found closing brace
                                const hex_digits = input[i + 3 .. end_pos];
                                if (hex_digits.len > 0 and hex_digits.len <= 6 and isValidHexDigits(hex_digits)) {
                                    const code_point = std.fmt.parseInt(u32, hex_digits, 16) catch {
                                        // Invalid hex, keep as-is
                                        try result.append(input[i]);
                                        i += 1;
                                        continue;
                                    };

                                    // Validate Unicode range
                                    if (code_point <= 0x10FFFF and !(code_point >= 0xD800 and code_point <= 0xDFFF)) {
                                        // Convert Unicode code point to UTF-8
                                        var utf8_bytes: [4]u8 = undefined;
                                        const len = std.unicode.utf8Encode(@intCast(code_point), &utf8_bytes) catch {
                                            // Invalid Unicode, keep as-is
                                            try result.append(input[i]);
                                            i += 1;
                                            continue;
                                        };
                                        try result.appendSlice(utf8_bytes[0..len]);
                                        i = end_pos + 1; // Skip past the closing brace
                                        continue;
                                    }
                                }
                            }
                        }
                        // Invalid unicode escape, keep as-is
                        try result.append(input[i]);
                        i += 1;
                        continue;
                    },
                    else => {
                        // Unknown escape, keep as-is (don't include JSON-only escapes like \b, \f, \/)
                        try result.append(input[i]);
                        i += 1;
                        continue;
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
    fn isValidHexDigits(hex: []const u8) bool {
        for (hex) |c| {
            switch (c) {
                '0'...'9', 'a'...'f', 'A'...'F' => {},
                else => return false,
            }
        }
        return true;
    }

    fn createErrorNode(self: *Self, allocator: std.mem.Allocator) Node {
        _ = self;
        _ = allocator;
        return Node{
            .err = .{
                .message = "Parse error",
                .span = Span.init(0, 0),
                .partial = null,
            },
        };
    }

    fn addError(self: *Self, message: []const u8, span: Span) !void {
        const msg = try self.allocator.dupe(u8, message);
        try self.errors.append(.{
            .message = msg,
            .span = span,
            .severity = .err,
        });
    }
};

// ============================================================================
// Tests
// ============================================================================

test "ZON streaming parser - simple values" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const inputs = [_][]const u8{
        "\"hello\"",
        "123",
        "true",
        "false",
        "null",
        "undefined",
        ".red", // enum literal
    };

    for (inputs) |input| {
        var parser = try Parser.init(allocator, input, .{});
        defer parser.deinit();

        var ast = try parser.parse();
        defer ast.deinit();

        try testing.expect(ast.root != null);
    }
}

test "ZON streaming parser - structs" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const input = ".{ .name = \"test\", .value = 42 }";

    var parser = try Parser.init(allocator, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    try testing.expect(ast.root != null);
    try testing.expectEqual(NodeKind.object, std.meta.activeTag(ast.root.?.*));
}

test "ZON streaming parser - arrays" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const input = "[1, 2, 3, \"test\", true, null, .red]";

    var parser = try Parser.init(allocator, input, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    try testing.expect(ast.root != null);
    try testing.expectEqual(NodeKind.array, std.meta.activeTag(ast.root.?.*));
}
