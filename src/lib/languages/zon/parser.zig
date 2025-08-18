const std = @import("std");
const Token = @import("../../parser/foundation/types/token.zig").Token;
const TokenKind = @import("../../parser/foundation/types/predicate.zig").TokenKind;
const AST = @import("../../parser/ast/mod.zig").AST;
const Node = @import("../../ast/mod.zig").Node;
const NodeType = @import("../../ast/mod.zig").NodeType;
const Span = @import("../../parser/foundation/types/span.zig").Span;
const ParseContext = @import("memory.zig").ParseContext;
const utils = @import("utils.zig");

/// ZON parser using our AST infrastructure
///
/// Features:
/// - Recursive descent parsing for ZON structures
/// - Error recovery with detailed diagnostics
/// - Support for all ZON value types (.field, structs, arrays, literals)
/// - Integration with stratified parser foundation
/// - Performance target: <1ms for typical config files
pub const ZonParser = struct {
    allocator: std.mem.Allocator,
    tokens: []const Token,
    position: usize,
    errors: std.ArrayList(ParseError),
    context: ParseContext,

    const Self = @This();

    pub const ParseError = struct {
        message: []const u8,
        span: Span,
        severity: Severity,

        pub const Severity = enum {
            @"error",
            warning,
            info,
        };

        pub fn deinit(self: ParseError, allocator: std.mem.Allocator) void {
            allocator.free(self.message);
        }
    };

    pub const ParseOptions = struct {
        allow_trailing_commas: bool = true, // ZON commonly has trailing commas
        recover_from_errors: bool = true, // Continue parsing after errors
        preserve_comments: bool = true, // Include comments in AST
    };

    pub fn init(allocator: std.mem.Allocator, tokens: []const Token, options: ParseOptions) ZonParser {
        _ = options; // TODO: Use parse options
        return ZonParser{
            .allocator = allocator,
            .tokens = tokens,
            .position = 0,
            .errors = std.ArrayList(ParseError).init(allocator),
            .context = ParseContext.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.errors.items) |err| {
            err.deinit(self.allocator);
        }
        self.errors.deinit();
        self.context.deinit();
    }

    /// Parse tokens into ZON AST
    pub fn parse(self: *Self) !AST {
        const root_node = try self.parseValue();
        return AST{
            .root = root_node,
            .allocator = self.allocator,
        };
    }

    /// Get parse errors
    pub fn getErrors(self: *Self) []const ParseError {
        return self.errors.items;
    }

    fn parseValue(self: *Self) std.mem.Allocator.Error!Node {
        self.skipTrivia();

        if (self.position >= self.tokens.len) {
            return self.createErrorNode("Unexpected end of input");
        }

        const token = self.currentToken();

        switch (token.kind) {
            .delimiter => {
                if (std.mem.eql(u8, token.text, "{")) {
                    return self.parseObject();
                } else if (std.mem.eql(u8, token.text, "[")) {
                    return self.parseArray();
                } else {
                    return self.createErrorNode("Unexpected delimiter");
                }
            },
            .operator => {
                if (std.mem.eql(u8, token.text, ".")) {
                    return self.parseDotExpression();
                } else {
                    return self.createErrorNode("Unexpected operator");
                }
            },
            .identifier => {
                // Regular identifiers (without leading dot)
                return self.parseIdentifier();
            },
            .string_literal => return self.parseStringLiteral(),
            .number_literal => return self.parseNumberLiteral(),
            .keyword => return self.parseKeyword(),
            else => return self.createErrorNode("Unexpected token"),
        }
    }

    fn parseObject(self: *Self) !Node {
        const start_token = self.currentToken();
        const start_span = start_token.span;

        if (!std.mem.eql(u8, start_token.text, "{")) {
            return self.createErrorNode("Expected '{'");
        }
        self.advance(); // Skip '{'

        var children = std.ArrayList(Node).init(self.allocator);
        defer children.deinit();

        self.skipTrivia();

        // Handle empty object
        if (self.position < self.tokens.len and
            self.currentToken().kind == .delimiter and
            std.mem.eql(u8, self.currentToken().text, "}"))
        {
            const end_span = self.currentToken().span;
            self.advance(); // Skip '}'

            return Node{
                .rule_name = "object",
                .node_type = .list,
                .text = self.getTextSpan(start_span, end_span),
                .start_position = start_span.start,
                .end_position = end_span.end,
                .children = try children.toOwnedSlice(),
                .attributes = null,
                .parent = null,
            };
        }

        // Parse object fields
        while (self.position < self.tokens.len) {
            self.skipTrivia();

            if (self.position >= self.tokens.len) break;

            const token = self.currentToken();
            if (token.kind == .delimiter and std.mem.eql(u8, token.text, "}")) {
                break;
            }

            // Parse field (either .field_name = value or bare value)
            const field_node = try self.parseField();
            try children.append(field_node);

            self.skipTrivia();

            // Check for comma or end
            if (self.position < self.tokens.len) {
                const next_token = self.currentToken();
                if (next_token.kind == .delimiter and std.mem.eql(u8, next_token.text, ",")) {
                    self.advance(); // Skip comma
                } else if (next_token.kind == .delimiter and std.mem.eql(u8, next_token.text, "}")) {
                    // End of object
                    break;
                } else {
                    try self.addError("Expected ',' or '}'", next_token.span);
                    break;
                }
            }
        }

        // Expect closing brace
        if (self.position >= self.tokens.len) {
            try self.addError("Expected '}'", start_span);
        } else {
            const end_token = self.currentToken();
            if (end_token.kind == .delimiter and std.mem.eql(u8, end_token.text, "}")) {
                self.advance(); // Skip '}'
            } else {
                try self.addError("Expected '}'", end_token.span);
            }
        }

        const end_pos = if (self.position > 0) self.tokens[self.position - 1].span.end else start_span.end;

        return Node{
            .rule_name = "object",
            .node_type = .list,
            .text = &[_]u8{}, // Empty array literal is safer than ""
            .start_position = start_span.start,
            .end_position = end_pos,
            .children = try children.toOwnedSlice(),
            .attributes = null,
            .parent = null,
        };
    }

    fn parseArray(self: *Self) !Node {
        const start_token = self.currentToken();
        const start_span = start_token.span;

        if (!std.mem.eql(u8, start_token.text, "[")) {
            return self.createErrorNode("Expected '['");
        }
        self.advance(); // Skip '['

        var children = std.ArrayList(Node).init(self.allocator);
        defer children.deinit();

        self.skipTrivia();

        // Handle empty array
        if (self.position < self.tokens.len and
            self.currentToken().kind == .delimiter and
            std.mem.eql(u8, self.currentToken().text, "]"))
        {
            const end_span = self.currentToken().span;
            self.advance(); // Skip ']'

            return Node{
                .rule_name = "array",
                .node_type = .list,
                .text = self.getTextSpan(start_span, end_span),
                .start_position = start_span.start,
                .end_position = end_span.end,
                .children = try children.toOwnedSlice(),
                .attributes = null,
                .parent = null,
            };
        }

        // Parse array elements
        while (self.position < self.tokens.len) {
            self.skipTrivia();

            if (self.position >= self.tokens.len) break;

            const token = self.currentToken();
            if (token.kind == .delimiter and std.mem.eql(u8, token.text, "]")) {
                break;
            }

            const element = try self.parseValue();
            try children.append(element);

            self.skipTrivia();

            // Check for comma or end
            if (self.position < self.tokens.len) {
                const next_token = self.currentToken();
                if (next_token.kind == .delimiter and std.mem.eql(u8, next_token.text, ",")) {
                    self.advance(); // Skip comma
                } else if (next_token.kind == .delimiter and std.mem.eql(u8, next_token.text, "]")) {
                    // End of array
                    break;
                } else {
                    try self.addError("Expected ',' or ']'", next_token.span);
                    break;
                }
            }
        }

        // Expect closing bracket
        if (self.position >= self.tokens.len) {
            try self.addError("Expected ']'", start_span);
        } else {
            const end_token = self.currentToken();
            if (end_token.kind == .delimiter and std.mem.eql(u8, end_token.text, "]")) {
                self.advance(); // Skip ']'
            } else {
                try self.addError("Expected ']'", end_token.span);
            }
        }

        const end_pos = if (self.position > 0) self.tokens[self.position - 1].span.end else start_span.end;

        return Node{
            .rule_name = "array",
            .node_type = .list,
            .text = &[_]u8{},
            .start_position = start_span.start,
            .end_position = end_pos,
            .children = try children.toOwnedSlice(),
            .attributes = null,
            .parent = null,
        };
    }

    fn parseField(self: *Self) !Node {
        // Parse .field_name = value or just value

        // Check if this is a field assignment (.field = value)
        if (self.position < self.tokens.len) {
            const token = self.currentToken();

            // Check for field assignment (either . operator or old-style .identifier)
            if ((token.kind == .operator and std.mem.eql(u8, token.text, ".")) or
                (token.kind == .identifier and token.text.len > 0 and token.text[0] == '.'))
            {
                // Field assignment
                const field_name_node = try self.parseFieldName();

                self.skipTrivia();

                // Expect '='
                if (self.position >= self.tokens.len) {
                    try self.addError("Expected '=' after field name", token.span);
                    return field_name_node;
                }

                const equals_token = self.currentToken();
                if (equals_token.kind != .operator or !std.mem.eql(u8, equals_token.text, "=")) {
                    try self.addError("Expected '=' after field name", equals_token.span);
                    return field_name_node;
                }

                // Create equals node
                const equals_node = Node{
                    .rule_name = "equals",
                    .node_type = .terminal,
                    .text = equals_token.text,
                    .start_position = equals_token.span.start,
                    .end_position = equals_token.span.end,
                    .children = &[_]Node{},
                    .attributes = null,
                    .parent = null,
                };

                self.advance(); // Skip '='

                self.skipTrivia();

                // Parse value
                const value_node = try self.parseValue();

                // Create field assignment node with 3 children: field_name, equals, value
                var children = std.ArrayList(Node).init(self.allocator);
                defer children.deinit();
                try children.append(field_name_node);
                try children.append(equals_node);
                try children.append(value_node);

                const end_pos = value_node.end_position;

                return Node{
                    .rule_name = "field_assignment",
                    .node_type = .rule,
                    .text = &[_]u8{},
                    .start_position = field_name_node.start_position,
                    .end_position = end_pos,
                    .children = try children.toOwnedSlice(),
                    .attributes = null,
                    .parent = null,
                };
            }
        }

        // Just a value
        return self.parseValue();
    }

    fn parseDotExpression(self: *Self) !Node {
        const token = self.currentToken();

        if (!std.mem.eql(u8, token.text, ".")) {
            return self.createErrorNode("Expected '.'");
        }

        self.advance(); // Skip '.'

        // Check what follows the dot
        if (self.position < self.tokens.len) {
            const next_token = self.currentToken();
            if (next_token.kind == .delimiter and std.mem.eql(u8, next_token.text, "{")) {
                // Anonymous struct literal .{}
                return self.parseObject();
            } else if (next_token.kind == .delimiter and std.mem.eql(u8, next_token.text, "[")) {
                // Anonymous array literal .[]
                return self.parseArray();
            }
        }

        // Just a dot - treat as operator
        return Node{
            .rule_name = "dot",
            .node_type = .terminal,
            .text = token.text,
            .start_position = token.span.start,
            .end_position = token.span.end,
            .children = &[_]Node{},
            .attributes = null,
            .parent = null,
        };
    }

    fn parseFieldName(self: *Self) !Node {
        const start_token = self.currentToken();

        // Field names now come as two tokens: '.' followed by identifier
        if (start_token.kind == .operator and std.mem.eql(u8, start_token.text, ".")) {
            // We have a dot, advance and get the identifier
            const dot_start = start_token.span.start;
            self.advance();

            if (self.position >= self.tokens.len) {
                return self.createErrorNode("Expected identifier after '.'");
            }

            const id_token = self.currentToken();
            if (id_token.kind != .identifier) {
                return self.createErrorNode("Expected identifier after '.'");
            }

            // Combine the dot and identifier into the field name
            // Use utils function for consistency
            const combined_text = try utils.combineFieldName(self.allocator, start_token.text, id_token.text);
            // Transfer ownership to AST
            try self.context.transferred_texts.append(combined_text);

            self.advance();

            return Node{
                .rule_name = "field_name",
                .node_type = .terminal,
                .text = combined_text,
                .start_position = dot_start,
                .end_position = id_token.span.end,
                .children = &[_]Node{},
                .attributes = null,
                .parent = null,
            };
        } else if (start_token.kind == .identifier and start_token.text.len > 0 and start_token.text[0] == '.') {
            // Old-style single token field name (for backward compatibility)
            self.advance();

            return Node{
                .rule_name = "field_name",
                .node_type = .terminal,
                .text = start_token.text,
                .start_position = start_token.span.start,
                .end_position = start_token.span.end,
                .children = &[_]Node{},
                .attributes = null,
                .parent = null,
            };
        } else {
            return self.createErrorNode("Expected field name starting with '.'");
        }
    }

    fn parseIdentifier(self: *Self) !Node {
        const token = self.currentToken();

        if (token.kind != .identifier) {
            return self.createErrorNode("Expected identifier");
        }

        self.advance();

        return Node{
            .rule_name = "identifier",
            .node_type = .terminal,
            .text = token.text,
            .start_position = token.span.start,
            .end_position = token.span.end,
            .children = &[_]Node{},
            .attributes = null,
            .parent = null,
        };
    }

    fn parseStringLiteral(self: *Self) !Node {
        const token = self.currentToken();

        if (token.kind != .string_literal) {
            return self.createErrorNode("Expected string literal");
        }

        self.advance();

        return Node{
            .rule_name = "string_literal",
            .node_type = .terminal,
            .text = token.text,
            .start_position = token.span.start,
            .end_position = token.span.end,
            .children = &[_]Node{},
            .attributes = null,
            .parent = null,
        };
    }

    fn parseNumberLiteral(self: *Self) !Node {
        const token = self.currentToken();

        if (token.kind != .number_literal) {
            return self.createErrorNode("Expected number literal");
        }

        self.advance();

        return Node{
            .rule_name = "number_literal",
            .node_type = .terminal,
            .text = token.text,
            .start_position = token.span.start,
            .end_position = token.span.end,
            .children = &[_]Node{},
            .attributes = null,
            .parent = null,
        };
    }

    fn parseKeyword(self: *Self) !Node {
        const token = self.currentToken();

        if (token.kind != .keyword) {
            return self.createErrorNode("Expected keyword");
        }

        self.advance();

        // Determine specific keyword type
        const rule_name = if (std.mem.eql(u8, token.text, "true") or std.mem.eql(u8, token.text, "false"))
            "boolean_literal"
        else if (std.mem.eql(u8, token.text, "null"))
            "null_literal"
        else if (std.mem.eql(u8, token.text, "undefined"))
            "undefined_literal"
        else
            "keyword";

        return Node{
            .rule_name = rule_name,
            .node_type = .terminal,
            .text = token.text,
            .start_position = token.span.start,
            .end_position = token.span.end,
            .children = &[_]Node{},
            .attributes = null,
            .parent = null,
        };
    }

    fn currentToken(self: *const Self) Token {
        if (self.position >= self.tokens.len) {
            // Return EOF token
            const last_span = if (self.tokens.len > 0)
                self.tokens[self.tokens.len - 1].span
            else
                Span{ .start = 0, .end = 0 };

            return Token{
                .kind = .eof,
                .span = last_span,
                .text = &[_]u8{},
                .bracket_depth = 0,
                .flags = .{},
            };
        }
        return self.tokens[self.position];
    }

    fn advance(self: *Self) void {
        if (self.position < self.tokens.len) {
            self.position += 1;
        }
    }

    fn skipTrivia(self: *Self) void {
        while (self.position < self.tokens.len) {
            const token = self.currentToken();
            if (token.kind == .whitespace or token.kind == .comment or token.kind == .newline) {
                self.advance();
            } else {
                break;
            }
        }
    }

    fn createErrorNode(self: *Self, message: []const u8) !Node {
        const current = self.currentToken();
        try self.addError(message, current.span);

        return Node{
            .rule_name = "error",
            .node_type = .error_recovery,
            .text = current.text,
            .start_position = current.span.start,
            .end_position = current.span.end,
            .children = &[_]Node{},
            .attributes = null,
            .parent = null,
        };
    }

    fn addError(self: *Self, message: []const u8, span: Span) !void {
        const owned_message = try self.allocator.dupe(u8, message);
        const error_obj = ParseError{
            .message = owned_message,
            .span = span,
            .severity = .@"error",
        };
        try self.errors.append(error_obj);
    }

    fn getTextSpan(self: *const Self, start_span: Span, end_span: Span) []const u8 {
        // This would need access to the original source text
        // For now, return empty string
        _ = self;
        _ = start_span;
        _ = end_span;
        return "";
    }
};

/// Convenience function for parsing ZON tokens
pub fn parse(allocator: std.mem.Allocator, tokens: []const Token) !AST {
    var parser = ZonParser.init(allocator, tokens, .{});
    defer {
        // Clean up errors but not the context (texts are transferred)
        for (parser.errors.items) |err| {
            err.deinit(allocator);
        }
        parser.errors.deinit();
    }

    const ast = try parser.parse();

    // Transfer ownership of allocated texts to AST
    // For now we still leak them, but they're properly tracked
    const owned_texts = parser.context.transferOwnership();
    _ = owned_texts; // TODO: Store in AST for proper cleanup

    return ast;
}

// Note: parseFromSlice and free functions have been moved to ast_converter.zig
// for better separation of concerns. The parser module now focuses solely on
// AST generation, while ast_converter handles type conversion.
