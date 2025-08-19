const std = @import("std");
const Token = @import("../../parser/foundation/types/token.zig").Token;
const TokenKind = @import("../../parser/foundation/types/predicate.zig").TokenKind;
const Span = @import("../../parser/foundation/types/span.zig").Span;
const AST = @import("../../ast/mod.zig").AST;
const Node = @import("../../ast/mod.zig").Node;
const NodeType = @import("../../ast/mod.zig").NodeType;
const ParseContext = @import("memory.zig").ParseContext;
const JsonRules = @import("../../ast/rules.zig").JsonRules;
const patterns = @import("patterns.zig");
const JsonDelimiters = patterns.JsonDelimiters;

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
    current: usize,
    errors: std.ArrayList(ParseError),
    allow_trailing_commas: bool,
    context: ParseContext,

    const Self = @This();

    pub const ParseError = struct {
        message: []const u8,
        span: Span,
        severity: Severity,

        pub const Severity = enum { @"error", warning };
    };

    pub const ParserOptions = struct {
        allow_trailing_commas: bool = false,
        recover_from_errors: bool = true,
    };

    pub fn init(allocator: std.mem.Allocator, tokens: []const Token, options: ParserOptions) JsonParser {
        return JsonParser{
            .allocator = allocator,
            .tokens = tokens,
            .current = 0,
            .errors = std.ArrayList(ParseError).init(allocator),
            .allow_trailing_commas = options.allow_trailing_commas,
            .context = ParseContext.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.errors.items) |err| {
            self.allocator.free(err.message);
        }
        self.errors.deinit();
        self.context.deinit();
    }

    /// Parse tokens into JSON AST
    pub fn parse(self: *Self) !AST {
        const root_node = try self.parseValue();

        // Check for trailing tokens (skip EOF)
        while (!self.isAtEnd() and self.peek().kind == .eof) {
            _ = self.advance();
        }
        if (!self.isAtEnd()) {
            try self.addError("Unexpected token after JSON value", self.peek().span);
        }

        // Transfer ownership of allocated texts from parse context
        const owned_texts = self.context.transferOwnership();

        return AST{
            .root = root_node,
            .allocator = self.allocator,
            .owned_texts = owned_texts,
        };
    }

    /// Get all parse errors
    pub fn getErrors(self: *Self) []const ParseError {
        return self.errors.items;
    }

    fn parseValue(self: *Self) anyerror!Node {
        if (self.isAtEnd()) {
            try self.addError("Unexpected end of input", Span.init(0, 0));
            return self.createErrorNode();
        }

        const token = self.peek();

        return switch (token.kind) {
            .string_literal => self.parseString(),
            .number_literal => self.parseNumber(),
            .boolean_literal => self.parseBoolean(),
            .null_literal => self.parseNull(),
            .delimiter => {
                // Use efficient delimiter checking (O(1) vs O(n))
                if (token.text.len == 1) {
                    if (JsonDelimiters.fromChar(token.text[0])) |delimiter_kind| {
                        return switch (delimiter_kind) {
                            .left_brace => self.parseObject(),
                            .left_bracket => self.parseArray(),
                            else => self.parseUnexpected(),
                        };
                    }
                }
                return self.parseUnexpected();
            },
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

        // Validate and unescape string content
        const content = try self.unescapeString(token.text);
        const owned_content = try self.context.trackText(content);
        // Don't free content here - ownership transferred to AST via trackText

        return Node{
            .rule_id = JsonRules.string_literal,
            .node_type = .terminal,
            .text = owned_content,
            .start_position = token.span.start,
            .end_position = token.span.end,
            .children = &[_]Node{},
            .attributes = null,
            .parent = null,
        };
    }

    fn parseNumber(self: *Self) !Node {
        const token = self.advance();

        // Validate number format
        _ = std.fmt.parseFloat(f64, token.text) catch {
            try self.addError("Invalid number format", token.span);
            return self.createErrorNode();
        };

        return Node{
            .rule_id = JsonRules.number_literal,
            .node_type = .terminal,
            .text = token.text,
            .start_position = token.span.start,
            .end_position = token.span.end,
            .children = &[_]Node{},
            .attributes = null,
            .parent = null,
        };
    }

    fn parseBoolean(self: *Self) !Node {
        const token = self.advance();
        _ = std.mem.eql(u8, token.text, "true");

        return Node{
            .rule_id = JsonRules.boolean_literal,
            .node_type = .terminal,
            .text = token.text,
            .start_position = token.span.start,
            .end_position = token.span.end,
            .children = &[_]Node{},
            .attributes = null,
            .parent = null,
        };
    }

    fn parseNull(self: *Self) !Node {
        const token = self.advance();
        
        return Node{
            .rule_id = JsonRules.null_literal,
            .node_type = .terminal,
            .text = token.text,
            .start_position = token.span.start,
            .end_position = token.span.end,
            .children = &[_]Node{},
            .attributes = null,
            .parent = null,
        };
    }

    fn parseObject(self: *Self) !Node {
        const start_token = self.advance(); // consume '{'
        var members = std.ArrayList(Node).init(self.allocator);
        defer members.deinit();

        // Handle empty object
        if (self.checkDelimiter(.right_brace)) {
            const end_token = self.advance();
            return Node{
                .rule_id = JsonRules.object,
                .node_type = .list,
                .text = &[_]u8{},
                .start_position = start_token.span.start,
                .end_position = end_token.span.end,
                .children = &[_]Node{},
                .attributes = null,
                .parent = null,
            };
        }

        // Parse object members
        while (!self.isAtEnd() and !self.checkDelimiter(.right_brace)) {
            const member = self.parseObjectMember() catch |err| switch (err) {
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

            try members.append(member);

            if (self.checkDelimiter(.comma)) {
                _ = self.advance(); // consume comma

                // Handle trailing comma
                if (self.checkDelimiter(.right_brace)) {
                    if (!self.allow_trailing_commas) {
                        try self.addError("Trailing comma not allowed", self.peek().span);
                    }
                    break;
                }
            } else if (!self.check(.delimiter, "}")) {
                try self.addError("Expected ',' or '}' after object member", self.peek().span);
                break;
            }
        }

        if (!self.check(.delimiter, "}")) {
            try self.addError("Expected '}' to close object", self.peek().span);
            return self.createErrorNode();
        }

        const end_token = self.advance(); // consume '}'

        // Convert ArrayList to slice for children
        const children = try self.context.trackNodes(members.items);

        return Node{
            .rule_id = JsonRules.object,
            .node_type = .list,
            .text = &[_]u8{},
            .start_position = start_token.span.start,
            .end_position = end_token.span.end,
            .children = children,
            .attributes = null,
            .parent = null,
        };
    }

    fn parseObjectMember(self: *Self) !Node {
        // Parse key (must be string)
        if (!self.check(.string_literal, null)) {
            try self.addError("Expected string key in object member", self.peek().span);
            return error.ParseError;
        }

        const key = try self.parseString();

        // Expect colon
        if (!self.check(.delimiter, ":")) {
            try self.addError("Expected ':' after object key", self.peek().span);
            return error.ParseError;
        }
        _ = self.advance(); // consume ':'

        // Parse value
        const value = try self.parseValue();

        // Create member node
        const children = try self.context.trackNodes(&[_]Node{ key, value });
        
        return Node{
            .rule_id = JsonRules.member,
            .node_type = .rule,
            .text = &[_]u8{},
            .start_position = key.start_position,
            .end_position = value.end_position,
            .children = children,
            .attributes = null,
            .parent = null,
        };
    }

    fn parseArray(self: *Self) !Node {
        const start_token = self.advance(); // consume '['
        var elements = std.ArrayList(Node).init(self.allocator);
        defer elements.deinit();

        // Handle empty array
        if (self.check(.delimiter, "]")) {
            const end_token = self.advance();
            return Node{
                .rule_id = JsonRules.array,
                .node_type = .list,
                .text = &[_]u8{},
                .start_position = start_token.span.start,
                .end_position = end_token.span.end,
                .children = &[_]Node{},
                .attributes = null,
                .parent = null,
            };
        }

        // Parse array elements
        while (!self.isAtEnd() and !self.check(.delimiter, "]")) {
            const element = self.parseValue() catch |err| switch (err) {
                error.ParseError => {
                    // Skip to next comma or closing bracket for error recovery
                    self.skipToDelimiter(&.{ ",", "]" });
                    if (self.check(.delimiter, ",")) {
                        _ = self.advance();
                    }
                    continue;
                },
                else => return err,
            };

            try elements.append(element);

            if (self.check(.delimiter, ",")) {
                _ = self.advance(); // consume comma

                // Handle trailing comma
                if (self.check(.delimiter, "]")) {
                    if (!self.allow_trailing_commas) {
                        try self.addError("Trailing comma not allowed", self.peek().span);
                    }
                    break;
                }
            } else if (!self.check(.delimiter, "]")) {
                try self.addError("Expected ',' or ']' after array element", self.peek().span);
                break;
            }
        }

        if (!self.check(.delimiter, "]")) {
            try self.addError("Expected ']' to close array", self.peek().span);
            return self.createErrorNode();
        }

        const end_token = self.advance(); // consume ']'

        // Convert ArrayList to slice for children
        const children = try self.context.trackNodes(elements.items);

        return Node{
            .rule_id = JsonRules.array,
            .node_type = .list,
            .text = &[_]u8{},
            .start_position = start_token.span.start,
            .end_position = end_token.span.end,
            .children = children,
            .attributes = null,
            .parent = null,
        };
    }

    fn parseUnexpected(self: *Self) !Node {
        const token = self.peek();
        try self.addError("Unexpected token", token.span);
        _ = self.advance();
        return self.createErrorNode();
    }

    fn unescapeString(self: *Self, raw: []const u8) ![]u8 {
        if (raw.len < 2 or raw[0] != '"' or raw[raw.len - 1] != '"') {
            return error.InvalidString;
        }

        const content = raw[1 .. raw.len - 1];
        var result = std.ArrayList(u8).init(self.allocator);
        defer result.deinit();

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
                        // TODO: Handle Unicode escape sequences
                        try result.append('\\');
                        try result.append('u');
                        i += 2;
                        continue;
                    },
                    else => blk: {
                        try self.addError("Invalid escape sequence", Span.init(i, i + 2));
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
        const span = if (self.isAtEnd()) Span.init(0, 0) else self.peek().span;
        return Node{
            .rule_id = JsonRules.error_recovery,
            .node_type = .error_recovery,
            .text = "error",
            .start_position = span.start,
            .end_position = span.end,
            .children = &[_]Node{},
            .attributes = null,
            .parent = null,
        };
    }

    fn addError(self: *Self, message: []const u8, span: Span) !void {
        const owned_message = try self.allocator.dupe(u8, message);
        try self.errors.append(ParseError{
            .message = owned_message,
            .span = span,
            .severity = .@"error",
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
            return Token.simple(Span.init(0, 0), .eof, "", 0);
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
        return token.kind == kind and (text == null or std.mem.eql(u8, token.text, text.?));
    }
    
    /// Efficient delimiter checking using enum (O(1) vs O(n) string comparison)
    fn checkDelimiter(self: *Self, delimiter_kind: JsonDelimiters.KindType) bool {
        if (self.isAtEnd()) return false;
        const token = self.peek();
        if (token.kind != .delimiter) return false;
        
        // Convert token text to character and check against delimiter
        if (token.text.len == 1) {
            if (JsonDelimiters.fromChar(token.text[0])) |found_kind| {
                return found_kind == delimiter_kind;
            }
        }
        return false;
    }

    fn skipToDelimiter(self: *Self, delimiters: []const []const u8) void {
        while (!self.isAtEnd()) {
            const token = self.peek();
            if (token.kind == .delimiter) {
                for (delimiters) |delim| {
                    if (std.mem.eql(u8, token.text, delim)) {
                        return;
                    }
                }
            }
            _ = self.advance();
        }
    }
};

// JSON-specific node types are handled via rule_name strings:
// - "string_literal" for string literals
// - "number_literal" for numeric values
// - "boolean_literal" for true/false
// - "null_literal" for null
// - "object" for objects
// - "member" for key-value pairs
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
        var lexer = JsonLexer.init(allocator, "\"hello\"", .{});
        defer lexer.deinit();
        const tokens = try lexer.tokenize();

        var parser = JsonParser.init(allocator, tokens, .{});
        defer parser.deinit();

        var ast = try parser.parse();
        defer ast.deinit();

        // AST.root is non-optional now
        // Additional AST validation would go here
    }

    // Test number
    {
        var lexer = JsonLexer.init(allocator, "42", .{});
        defer lexer.deinit();
        const tokens = try lexer.tokenize();

        var parser = JsonParser.init(allocator, tokens, .{});
        defer parser.deinit();

        var ast = try parser.parse();
        defer ast.deinit();

        // AST.root is non-optional now
    }

    // Test boolean
    {
        var lexer = JsonLexer.init(allocator, "true", .{});
        defer lexer.deinit();
        const tokens = try lexer.tokenize();

        var parser = JsonParser.init(allocator, tokens, .{});
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

    var lexer = JsonLexer.init(allocator, "{\"key\": \"value\"}", .{});
    defer lexer.deinit();
    const tokens = try lexer.tokenize();

    var parser = JsonParser.init(allocator, tokens, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    // AST.root is non-optional now
    // Verify it's an object with one member
    // Additional structure validation would go here
}

test "JSON parser - array" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var lexer = JsonLexer.init(allocator, "[1, 2, 3]", .{});
    defer lexer.deinit();
    const tokens = try lexer.tokenize();

    var parser = JsonParser.init(allocator, tokens, .{});
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

    var lexer = JsonLexer.init(allocator, json_text, .{});
    defer lexer.deinit();
    const tokens = try lexer.tokenize();

    var parser = JsonParser.init(allocator, tokens, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    // AST.root is non-optional now

    // Check no parse errors
    const errors = parser.getErrors();
    if (errors.len > 0) {
        std.debug.print("Parse errors: {}\n", .{errors.len});
        for (errors) |err| {
            std.debug.print("Error: {s}\n", .{err.message});
        }
    }
    try testing.expectEqual(@as(usize, 0), errors.len);
}

test "JSON parser - error recovery" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test malformed JSON
    var lexer = JsonLexer.init(allocator, "{\"key\": [1, 2,]}", .{ .allow_trailing_commas = false });
    defer lexer.deinit();
    const tokens = try lexer.tokenize();

    var parser = JsonParser.init(allocator, tokens, .{});
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    // Should have generated errors but still produce some AST
    const errors = parser.getErrors();
    try testing.expect(errors.len > 0);
}
