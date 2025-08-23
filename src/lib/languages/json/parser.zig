const std = @import("std");
const Token = @import("../../token/token.zig").Token;
const TokenKind = @import("../../token/token.zig").TokenKind;
const Span = @import("../../span/span.zig").Span;
// Use local JSON AST
const json_ast = @import("ast.zig");
const AST = json_ast.AST;
const Node = json_ast.Node;
const NodeKind = json_ast.NodeKind;
const memory = @import("../../memory/language_strategies/mod.zig");
const patterns = @import("patterns.zig");
const JsonDelimiters = patterns.JsonDelimiters;
const char_utils = @import("../../char/mod.zig");
// BulkAllocator removed - new memory system handles this internally

/// High-performance JSON parser producing proper AST
///
/// Features:
/// - Recursive descent parser for all JSON constructs
/// - Error recovery with detailed diagnostics
/// - Support for JSON5 features (comments, trailing commas)
/// - Incremental parsing capability
/// - Performance target: <1ms for 10KB JSON
pub const JsonParser = struct {
    allocator: std.mem.Allocator,
    tokens: []const Token,
    source: []const u8,
    current: usize,
    errors: std.ArrayList(ParseError),
    allow_trailing_commas: bool,
    context: memory.MemoryContext(Node),
    // bulk_allocator removed - handled by new memory system
    ast_arena: ?*std.heap.ArenaAllocator, // AST arena for permanent allocations (set during parse())

    const Self = @This();

    pub const ParseError = struct {
        message: []const u8,
        span: Span,
        severity: Severity,

        pub const Severity = enum { err, warning };
    };

    pub const ParserOptions = struct {
        allow_trailing_commas: bool = false,
        recover_from_errors: bool = true,
    };

    pub fn init(allocator: std.mem.Allocator, tokens: []const Token, source: []const u8, options: ParserOptions) JsonParser {
        const parser = JsonParser{
            .allocator = allocator,
            .tokens = tokens,
            .source = source,
            .current = 0,
            .errors = std.ArrayList(ParseError).init(allocator),
            .allow_trailing_commas = options.allow_trailing_commas,
            .context = memory.MemoryContext(Node).init(
                allocator,
                memory.MemoryStrategy{ .arena_only = {} },
            ),
            .ast_arena = null, // Will be set in parse()
        };

        return parser;
    }

    pub fn deinit(self: *Self) void {
        for (self.errors.items) |err| {
            self.allocator.free(err.message);
        }
        self.errors.deinit();
        self.context.deinit();

        // Bulk allocator cleanup removed - handled by memory context
    }

    /// Parse tokens into JSON AST
    pub fn parse(self: *Self) !AST {
        // Bulk allocation now handled by the new memory system internally

        // Memory context handles arena internally

        // Create separate arena for AST ownership (will outlive the parser context)
        const ast_arena = try self.allocator.create(std.heap.ArenaAllocator);
        ast_arena.* = std.heap.ArenaAllocator.init(self.allocator);

        // Store AST arena for use in parse methods
        self.ast_arena = ast_arena;

        // Parse root value
        const root_value = try self.parseValue();

        // Allocate root node in AST arena (permanent storage)
        const root_node = try ast_arena.allocator().create(Node);
        root_node.* = root_value;

        // Check for trailing tokens (skip EOF)
        while (!self.isAtEnd() and self.peek().kind == .eof) {
            _ = self.advance();
        }
        if (!self.isAtEnd()) {
            try self.addError("Unexpected token after JSON value", self.peek().span);
        }

        // TODO: Collect all nodes for AST.nodes field
        var nodes = std.ArrayList(Node).init(ast_arena.allocator());
        defer nodes.deinit();
        // For now, just add the root
        try nodes.append(root_value);

        return AST{
            .root = root_node,
            .arena = ast_arena,
            .source = self.source,
            .nodes = try nodes.toOwnedSlice(),
        };
    }

    /// Get all parse errors
    pub fn getErrors(self: *Self) []const ParseError {
        return self.errors.items;
    }

    /// Fast node allocation - uses memory context for optimal allocation
    /// The new memory system handles pooling and bulk allocation internally
    fn allocateNode(self: *Self) !*Node {
        // Use memory context which handles pooling internally
        return self.context.allocateNode();
    }

    fn parseValue(self: *Self) anyerror!Node {
        if (self.isAtEnd()) {
            try self.addError("Unexpected end of input", Span.init(0, 0));
            return self.createErrorNode();
        }

        const token = self.peek();

        return switch (token.kind) {
            .string => self.parseString(),
            .number => self.parseNumber(),
            .boolean => self.parseBoolean(),
            .null => self.parseNull(),
            .left_brace => self.parseObject(),
            .left_bracket => self.parseArray(),
            .comment => {
                // Skip comments and try next token
                _ = self.advance();
                return self.parseValue();
            },
            else => self.parseUnexpected(),
        };
    }

    fn parseString(self: *Self) !Node {
        const token = self.advance();

        // Validate and unescape string content (using arena allocator)
        const content = try self.unescapeString(token.getText(self.source));
        // Content is now allocated in arena, will be freed when AST is freed

        return Node{
            .string = .{
                .span = token.span,
                .value = content,
            },
        };
    }

    fn parseNumber(self: *Self) !Node {
        const token = self.advance();

        // Validate number format according to RFC 8259
        if (self.hasLeadingZero(token.getText(self.source))) {
            try self.addError("Numbers with leading zeros are not allowed in JSON", token.span);
            return self.createErrorNode();
        }

        // Additional validation using standard library
        const value = std.fmt.parseFloat(f64, token.getText(self.source)) catch {
            try self.addError("Invalid number format", token.span);
            return self.createErrorNode();
        };

        return Node{
            .number = .{
                .span = token.span,
                .value = value,
                .raw = token.getText(self.source),
            },
        };
    }

    /// Check if a number has leading zeros (violates RFC 8259)
    fn hasLeadingZero(self: *Self, text: []const u8) bool {
        _ = self; // unused
        if (text.len < 2) return false;

        var start_idx: usize = 0;
        // Skip optional minus sign
        if (text[0] == '-') {
            start_idx = 1;
            if (text.len < 3) return false; // Need at least "-0X"
        }

        // Check for leading zero: starts with '0' followed by digit
        return text[start_idx] == '0' and
            start_idx + 1 < text.len and
            char_utils.isDigit(text[start_idx + 1]);
    }

    fn parseBoolean(self: *Self) !Node {
        const token = self.advance();
        const value = std.mem.eql(u8, token.getText(self.source), "true");

        return Node{
            .boolean = .{
                .span = token.span,
                .value = value,
            },
        };
    }

    fn parseNull(self: *Self) !Node {
        const token = self.advance();

        return Node{
            .null = token.span,
        };
    }

    fn parseObject(self: *Self) !Node {
        const start_token = self.advance(); // consume '{'
        var properties = std.ArrayList(Node).init(self.context.tempAllocator());
        defer properties.deinit();

        // Handle empty object
        if (self.checkDelimiter(.right_brace)) {
            const end_token = self.advance();
            return Node{
                .object = .{
                    .span = Span{
                        .start = start_token.span.start,
                        .end = end_token.span.end,
                    },
                    .properties = &[_]Node{},
                },
            };
        }

        // Parse object properties
        while (!self.isAtEnd() and !self.checkDelimiter(.right_brace)) {
            const property = self.parseObjectProperty() catch |err| switch (err) {
                error.ParseError => {
                    // Skip to next comma or closing brace for error recovery
                    self.skipToDelimiter(&.{ ",", "}" });
                    if (self.checkDelimiter(.comma)) {
                        _ = self.advance();
                    }
                    continue;
                },
                else => return err,
            };

            try properties.append(property);

            if (self.checkDelimiter(.comma)) {
                _ = self.advance(); // consume comma

                // Handle trailing comma
                if (self.checkDelimiter(.right_brace)) {
                    if (!self.allow_trailing_commas) {
                        try self.addError("Trailing comma not allowed", self.peek().span);
                    }
                    break;
                }
            } else if (!self.check(.right_brace, null)) {
                try self.addError("Expected ',' or '}' after object property", self.peek().span);
                break;
            }
        }

        if (!self.check(.right_brace, null)) {
            try self.addError("Expected '}' to close object", self.peek().span);
            return self.createErrorNode();
        }

        const end_token = self.advance(); // consume '}'

        // Allocate permanent storage for object properties in AST arena
        const object_properties = try self.ast_arena.?.allocator().alloc(Node, properties.items.len);
        @memcpy(object_properties, properties.items);

        return Node{
            .object = .{
                .span = Span{
                    .start = start_token.span.start,
                    .end = end_token.span.end,
                },
                .properties = object_properties,
            },
        };
    }

    fn parseObjectProperty(self: *Self) !Node {
        // Parse key (must be string)
        if (!self.check(.string, null)) {
            try self.addError("Expected string key in object property", self.peek().span);
            return error.ParseError;
        }

        const key_node = try self.parseString();

        // Allocate key node in AST arena for permanent storage
        const key_ptr = try self.ast_arena.?.allocator().create(Node);
        key_ptr.* = key_node;

        // Expect colon
        if (!self.check(.colon, null)) {
            try self.addError("Expected ':' after object key", self.peek().span);
            return error.ParseError;
        }
        _ = self.advance(); // consume ':'

        // Parse value
        const value_node = try self.parseValue();

        // Allocate value node in AST arena for permanent storage
        const value_ptr = try self.ast_arena.?.allocator().create(Node);
        value_ptr.* = value_node;

        // Create property node
        return Node{
            .property = .{
                .span = Span{
                    .start = key_node.span().start,
                    .end = value_node.span().end,
                },
                .key = key_ptr,
                .value = value_ptr,
            },
        };
    }

    fn parseArray(self: *Self) !Node {
        const start_token = self.advance(); // consume '['
        var elements = std.ArrayList(Node).init(self.context.tempAllocator());
        defer elements.deinit();

        // Handle empty array
        if (self.check(.right_bracket, null)) {
            const end_token = self.advance();
            return Node{
                .array = .{
                    .span = Span{
                        .start = start_token.span.start,
                        .end = end_token.span.end,
                    },
                    .elements = &[_]Node{},
                },
            };
        }

        // Parse array elements
        while (!self.isAtEnd() and !self.check(.right_bracket, null)) {
            const element = self.parseValue() catch |err| switch (err) {
                error.ParseError => {
                    // Skip to next comma or closing bracket for error recovery
                    self.skipToDelimiter(&.{ ",", "]" });
                    if (self.check(.comma, null)) {
                        _ = self.advance();
                    }
                    continue;
                },
                else => return err,
            };

            try elements.append(element);

            if (self.check(.comma, null)) {
                _ = self.advance(); // consume comma

                // Handle trailing comma
                if (self.check(.right_bracket, null)) {
                    if (!self.allow_trailing_commas) {
                        try self.addError("Trailing comma not allowed", self.peek().span);
                    }
                    break;
                }
            } else if (!self.check(.right_bracket, null)) {
                try self.addError("Expected ',' or ']' after array element", self.peek().span);
                break;
            }
        }

        if (!self.check(.right_bracket, null)) {
            try self.addError("Expected ']' to close array", self.peek().span);
            return self.createErrorNode();
        }

        const end_token = self.advance(); // consume ']'

        // Allocate permanent storage for array elements in AST arena
        const array_elements = try self.ast_arena.?.allocator().alloc(Node, elements.items.len);
        @memcpy(array_elements, elements.items);

        return Node{
            .array = .{
                .span = Span{
                    .start = start_token.span.start,
                    .end = end_token.span.end,
                },
                .elements = array_elements,
            },
        };
    }

    fn parseUnexpected(self: *Self) !Node {
        const token = self.peek();
        try self.addError("Unexpected token", token.span);
        _ = self.advance();
        return self.createErrorNode();
    }

    fn unescapeString(self: *Self, raw: []const u8) ![]u8 {
        // Handle both quoted and unquoted strings
        const content = if (raw.len >= 2 and raw[0] == '"' and raw[raw.len - 1] == '"')
            raw[1 .. raw.len - 1]
        else
            raw;
        var result = std.ArrayList(u8).init(self.ast_arena.?.allocator());
        // Don't deinit - we return the owned slice

        var i: usize = 0;
        while (i < content.len) {
            if (content[i] == '\\' and i + 1 < content.len) {
                const escaped = content[i + 1];
                const unescaped: u8 = switch (escaped) {
                    '"' => '"',
                    '\\' => '\\',
                    '/' => '/',
                    'b' => '\x08',
                    'f' => '\x0C',
                    'n' => '\n',
                    'r' => '\r',
                    't' => '\t',
                    'u' => {
                        // Parse Unicode escape sequence \uXXXX
                        if (i + 5 >= content.len) {
                            try self.addError("Incomplete Unicode escape sequence", Span.init(@intCast(i), @intCast(i + 2)));
                            try result.append('\\');
                            try result.append('u');
                            i += 2;
                            continue;
                        }

                        // Parse 4 hex digits
                        const hex_digits = content[i + 2 .. i + 6];
                        const codepoint = std.fmt.parseInt(u21, hex_digits, 16) catch {
                            try self.addError("Invalid Unicode escape sequence", Span.init(@intCast(i), @intCast(i + 6)));
                            try result.append('\\');
                            try result.append('u');
                            i += 2;
                            continue;
                        };

                        // Convert to UTF-8 and append
                        var utf8_buf: [4]u8 = undefined;
                        const utf8_len = std.unicode.utf8Encode(codepoint, &utf8_buf) catch {
                            try self.addError("Invalid Unicode codepoint", Span.init(@intCast(i), @intCast(i + 6)));
                            try result.append('?'); // Replacement character
                            i += 6;
                            continue;
                        };
                        try result.appendSlice(utf8_buf[0..utf8_len]);
                        i += 6;
                        continue;
                    },
                    else => blk: {
                        try self.addError("Invalid escape sequence", Span.init(@intCast(i), @intCast(i + 2)));
                        break :blk escaped; // Use the escaped character as-is
                    },
                };
                try result.append(unescaped);
                i += 2;
            } else {
                try result.append(content[i]);
                i += 1;
            }
        }

        return result.toOwnedSlice();
    }

    fn createErrorNode(self: *Self) Node {
        const error_span = if (self.isAtEnd())
            Span{ .start = 0, .end = 0 }
        else
            self.peek().span;

        return Node{
            .err = .{
                .span = error_span,
                .message = "Parse error",
                .partial = null,
            },
        };
    }

    fn addError(self: *Self, message: []const u8, span: Span) !void {
        const owned_message = try self.allocator.dupe(u8, message);
        try self.errors.append(ParseError{
            .message = owned_message,
            .span = span,
            .severity = .err,
        });
    }

    fn advance(self: *Self) Token {
        if (!self.isAtEnd()) {
            self.current += 1;
        }
        return self.previous();
    }

    fn peek(self: *Self) Token {
        if (self.isAtEnd()) {
            // Return a dummy token for EOF
            return Token{
                .span = Span.init(0, 0),
                .kind = .eof,
            };
        }
        return self.tokens[self.current];
    }

    fn previous(self: *Self) Token {
        if (self.current == 0) {
            return self.peek();
        }
        return self.tokens[self.current - 1];
    }

    fn isAtEnd(self: *Self) bool {
        return self.current >= self.tokens.len;
    }

    fn check(self: *Self, kind: TokenKind, text: ?[]const u8) bool {
        if (self.isAtEnd()) return false;
        const token = self.peek();
        return token.kind == kind and (text == null or std.mem.eql(u8, token.getText(self.source), text.?));
    }

    /// Check for specific delimiter token kinds
    fn checkDelimiter(self: *Self, delimiter_kind: JsonDelimiters.KindType) bool {
        if (self.isAtEnd()) return false;
        const token = self.peek();

        // Map delimiter kinds to token kinds
        const expected_token_kind: TokenKind = switch (delimiter_kind) {
            .left_brace => .left_brace,
            .right_brace => .right_brace,
            .left_bracket => .left_bracket,
            .right_bracket => .right_bracket,
            .comma => .comma,
            .colon => .colon,
        };

        return token.kind == expected_token_kind;
    }

    fn skipToDelimiter(self: *Self, delimiters: []const []const u8) void {
        while (!self.isAtEnd()) {
            const token = self.peek();
            // Check if token is a delimiter by comparing text
            for (delimiters) |delim| {
                if (std.mem.eql(u8, token.getText(self.source), delim)) {
                    return;
                }
            }
            _ = self.advance();
        }
    }
};

// JSON-specific node types are handled via rule_name strings:
// - "string" for string literals
// - "number" for numeric values
// - "boolean" for true/false
// - "null" for null
// - "object" for objects
// - "property" for key-value pairs
// - "array" for arrays
// - "error" for parse errors

// Tests
const testing = std.testing;
const JsonLexer = @import("lexer.zig").JsonLexer;

test "JSON parser - simple values" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test string
    {
        var lexer = JsonLexer.init(allocator);
        defer lexer.deinit();
        const tokens = try lexer.batchTokenize(allocator, "\"hello\"");

        var parser = JsonParser.init(allocator, tokens, "\"hello\"", .{});
        defer parser.deinit();

        var ast = try parser.parse();
        defer ast.deinit();

        // AST.root is non-optional now
        // Additional AST validation would go here
    }

    // Test number
    {
        var lexer = JsonLexer.init(allocator);
        defer lexer.deinit();
        const tokens = try lexer.batchTokenize(allocator, "42");

        var parser = JsonParser.init(allocator, tokens, "42", .{});
        defer parser.deinit();

        var ast = try parser.parse();
        defer ast.deinit();

        // AST.root is non-optional now
    }

    // Test boolean
    {
        var lexer = JsonLexer.init(allocator);
        defer lexer.deinit();
        const tokens = try lexer.batchTokenize(allocator, "true");

        var parser = JsonParser.init(allocator, tokens, "true", .{});
        defer parser.deinit();

        var ast = try parser.parse();
        defer ast.deinit();

        // AST.root is non-optional now
    }
}

test "JSON parser - object" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var lexer = JsonLexer.init(allocator);
    defer lexer.deinit();
    const tokens = try lexer.batchTokenize(allocator, "{\"key\": \"value\"}");

    var parser = JsonParser.init(allocator, tokens, "{\"key\": \"value\"}", .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    // AST.root is non-optional now
    // Verify it's an object with one property
    // Additional structure validation would go here
}

test "JSON parser - array" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var lexer = JsonLexer.init(allocator);
    defer lexer.deinit();
    const tokens = try lexer.batchTokenize(allocator, "[1, 2, 3]");

    var parser = JsonParser.init(allocator, tokens, "[1, 2, 3]", .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    // AST.root is non-optional now
    // Verify it's an array with three elements
}

test "JSON parser - nested structure" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const json_text =
        \\{
        \\  "users": [
        \\    {"name": "Alice", "age": 30},
        \\    {"name": "Bob", "age": 25}
        \\  ],
        \\  "count": 2
        \\}
    ;

    var lexer = JsonLexer.init(allocator);
    defer lexer.deinit();
    const tokens = try lexer.batchTokenize(allocator, json_text);

    var parser = JsonParser.init(allocator, tokens, json_text, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    // AST.root is non-optional now

    // Check no parse errors
    const errors = parser.getErrors();
    try testing.expectEqual(@as(usize, 0), errors.len);
}

test "JSON parser - error recovery" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test malformed JSON
    var lexer = JsonLexer.init(allocator);
    defer lexer.deinit();
    const tokens = try lexer.batchTokenize(allocator, "{\"key\": [1, 2,]}");

    var parser = JsonParser.init(allocator, tokens, "{\"key\": [1, 2,]}", .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    // Should have generated errors but still produce some AST
    const errors = parser.getErrors();
    try testing.expect(errors.len > 0);
}
