const std = @import("std");
const Token = @import("../../token/token.zig").Token;
const TokenKind = @import("../../token/token.zig").TokenKind;
const Span = @import("../../span/span.zig").Span;
// Use local ZON AST
const zon_ast = @import("ast.zig");
const AST = zon_ast.AST;
const Node = zon_ast.Node;
const NodeKind = zon_ast.NodeKind;
const patterns = @import("patterns.zig");
const char_utils = @import("../../char/mod.zig");

/// High-performance ZON parser producing proper AST
///
/// Features:
/// - Recursive descent parser for all ZON constructs
/// - Error recovery with detailed diagnostics
/// - Support for .field syntax, structs, arrays, literals
/// - Incremental parsing capability
/// - Performance target: <1ms for typical config files
pub const ZonParser = struct {
    allocator: std.mem.Allocator,
    tokens: []const Token,
    source: []const u8,
    current: usize,
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
        recover_from_errors: bool = true, // Continue parsing after errors
    };

    pub fn init(allocator: std.mem.Allocator, tokens: []const Token, source: []const u8, options: ParserOptions) ZonParser {
        return ZonParser{
            .allocator = allocator,
            .tokens = tokens,
            .source = source,
            .current = 0,
            .errors = std.ArrayList(ParseError).init(allocator),
            .allow_trailing_commas = options.allow_trailing_commas,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.errors.items) |err| {
            self.allocator.free(err.message);
        }
        self.errors.deinit();
    }

    /// Parse tokens into ZON AST
    pub fn parse(self: *Self) !AST {
        // Create arena for AST allocation
        const arena = try self.allocator.create(std.heap.ArenaAllocator);
        arena.* = std.heap.ArenaAllocator.init(self.allocator);

        // Parse root value - handle empty input
        const root_value = if (self.tokens.len == 0 or (self.tokens.len == 1 and self.tokens[0].kind == .eof)) blk: {
            break :blk Node{
                .err = .{
                    .span = Span{ .start = 0, .end = 0 },
                    .message = "Empty input",
                    .partial = null,
                },
            };
        } else try self.parseValue();

        // Allocate root node
        const root_node_ptr = try self.allocator.create(Node);
        root_node_ptr.* = root_value;

        return AST{
            .root = root_node_ptr,
            .allocator = self.allocator,
            .owned_texts = std.ArrayList([]const u8).init(self.allocator),
        };
    }

    /// Parse a ZON value
    fn parseValue(self: *Self) std.mem.Allocator.Error!Node {
        if (self.isAtEnd()) {
            return self.createErrorNode("Unexpected end of input");
        }

        const token = self.peek();
        return switch (token.kind) {
            .string => try self.parseString(),
            .number => try self.parseNumber(),
            .identifier => blk: {
                const text = token.getText(self.source);
                if (std.mem.eql(u8, text, "true") or std.mem.eql(u8, text, "false")) {
                    break :blk try self.parseBoolean();
                } else if (std.mem.eql(u8, text, "null")) {
                    break :blk try self.parseNull();
                } else {
                    break :blk try self.parseIdentifier();
                }
            },
            .left_brace => try self.parseObject(),
            .left_bracket => try self.parseArray(),
            .dot => try self.parseFieldName(),
            .eof => self.createErrorNode("Unexpected end of file"),
            else => self.createErrorNode("Unexpected token"),
        };
    }

    fn parseString(self: *Self) std.mem.Allocator.Error!Node {
        const token = self.advance();
        const text = token.getText(self.source);
        // Remove quotes and handle escaping
        const content = if (text.len >= 2 and text[0] == '"' and text[text.len - 1] == '"')
            text[1 .. text.len - 1]
        else
            text;

        return Node{
            .string = .{
                .span = token.span,
                .value = content,
                .quote_style = .double,
            },
        };
    }

    fn parseNumber(self: *Self) std.mem.Allocator.Error!Node {
        const token = self.advance();
        const text = token.getText(self.source);

        // Simple number parsing - could be enhanced to detect integer vs float
        const number_value = if (std.mem.indexOf(u8, text, ".")) |_|
            @import("ast.zig").NumberNode.NumberValue{ .float = std.fmt.parseFloat(f64, text) catch 0.0 }
        else
            @import("ast.zig").NumberNode.NumberValue{ .integer = std.fmt.parseInt(i64, text, 10) catch 0 };

        return Node{
            .number = .{
                .span = token.span,
                .raw = text,
                .value = number_value,
            },
        };
    }

    fn parseBoolean(self: *Self) std.mem.Allocator.Error!Node {
        const token = self.advance();
        const text = token.getText(self.source);

        return Node{
            .boolean = .{
                .span = token.span,
                .value = std.mem.eql(u8, text, "true"),
            },
        };
    }

    fn parseNull(self: *Self) std.mem.Allocator.Error!Node {
        const token = self.advance();
        return Node{
            .null = token.span,
        };
    }

    fn parseIdentifier(self: *Self) std.mem.Allocator.Error!Node {
        const token = self.advance();
        const text = token.getText(self.source);

        // Check for quoted identifier syntax @"name"
        const is_quoted = text.len >= 3 and text[0] == '@' and text[1] == '"' and text[text.len - 1] == '"';
        const name = if (is_quoted) text[2 .. text.len - 1] else text;

        return Node{
            .identifier = .{
                .span = token.span,
                .name = name,
                .is_quoted = is_quoted,
            },
        };
    }

    fn parseFieldName(self: *Self) std.mem.Allocator.Error!Node {
        const dot_token = self.advance(); // consume '.'
        if (self.isAtEnd() or self.peek().kind != .identifier) {
            return self.createErrorNode("Expected identifier after '.'");
        }

        const name_token = self.advance();
        const name_text = name_token.getText(self.source);

        return Node{
            .field_name = .{
                .span = Span{ .start = dot_token.span.start, .end = name_token.span.end },
                .name = name_text,
            },
        };
    }

    fn parseObject(self: *Self) std.mem.Allocator.Error!Node {
        const start_token = self.advance(); // consume '{'
        var fields = std.ArrayList(Node).init(self.allocator);

        // Handle empty object
        if (self.match(.right_brace)) {
            return Node{
                .object = .{
                    .span = Span{ .start = start_token.span.start, .end = self.previous().span.end },
                    .fields = try fields.toOwnedSlice(),
                },
            };
        }

        // Parse fields
        while (!self.isAtEnd() and !self.check(.right_brace)) {
            const field = try self.parseField();
            try fields.append(field);

            if (!self.match(.comma) and !self.check(.right_brace)) {
                _ = try self.addError("Expected ',' or '}' after field", self.peek().span);
                break;
            }
        }

        if (!self.match(.right_brace)) {
            _ = try self.addError("Expected '}' to close object", self.peek().span);
        }

        return Node{
            .object = .{
                .span = Span{ .start = start_token.span.start, .end = if (self.current > 0) self.tokens[self.current - 1].span.end else start_token.span.end },
                .fields = try fields.toOwnedSlice(),
            },
        };
    }

    fn parseArray(self: *Self) std.mem.Allocator.Error!Node {
        const start_token = self.advance(); // consume '['
        var elements = std.ArrayList(Node).init(self.allocator);

        // Handle empty array
        if (self.match(.right_bracket)) {
            return Node{
                .array = .{
                    .span = Span{ .start = start_token.span.start, .end = self.previous().span.end },
                    .elements = try elements.toOwnedSlice(),
                    .is_anonymous_list = false,
                },
            };
        }

        // Parse elements
        while (!self.isAtEnd() and !self.check(.right_bracket)) {
            const element = try self.parseValue();
            try elements.append(element);

            if (!self.match(.comma) and !self.check(.right_bracket)) {
                _ = try self.addError("Expected ',' or ']' after array element", self.peek().span);
                break;
            }
        }

        if (!self.match(.right_bracket)) {
            _ = try self.addError("Expected ']' to close array", self.peek().span);
        }

        return Node{
            .array = .{
                .span = Span{ .start = start_token.span.start, .end = if (self.current > 0) self.tokens[self.current - 1].span.end else start_token.span.end },
                .elements = try elements.toOwnedSlice(),
                .is_anonymous_list = false,
            },
        };
    }

    fn parseField(self: *Self) std.mem.Allocator.Error!Node {
        const name_node = try self.parseValue(); // Can be field_name or identifier

        if (!self.match(.equal)) {
            _ = try self.addError("Expected '=' after field name", self.peek().span);
        }

        const name_node_ptr = try self.allocator.create(Node);
        name_node_ptr.* = name_node;

        const value_node_ptr = try self.allocator.create(Node);
        value_node_ptr.* = try self.parseValue();

        const name_span = name_node.span();
        const value_span = value_node_ptr.span();

        return Node{
            .field = .{
                .span = Span{ .start = name_span.start, .end = value_span.end },
                .name = name_node_ptr,
                .value = value_node_ptr,
            },
        };
    }

    // Utility methods
    fn isAtEnd(self: *Self) bool {
        return self.current >= self.tokens.len or self.peek().kind == .eof;
    }

    fn peek(self: *Self) Token {
        if (self.current >= self.tokens.len) {
            return Token{ .kind = .eof, .span = Span{ .start = 0, .end = 0 } };
        }
        return self.tokens[self.current];
    }

    fn previous(self: *Self) Token {
        if (self.current == 0) {
            return Token{ .kind = .eof, .span = Span{ .start = 0, .end = 0 } };
        }
        return self.tokens[self.current - 1];
    }

    fn advance(self: *Self) Token {
        if (!self.isAtEnd()) {
            self.current += 1;
        }
        return self.previous();
    }

    fn check(self: *Self, kind: TokenKind) bool {
        if (self.isAtEnd()) return false;
        return self.peek().kind == kind;
    }

    fn match(self: *Self, kind: TokenKind) bool {
        if (self.check(kind)) {
            _ = self.advance();
            return true;
        }
        return false;
    }

    fn createErrorNode(self: *Self, message: []const u8) Node {
        const span = if (self.isAtEnd())
            Span{ .start = 0, .end = 0 }
        else
            self.peek().span;

        _ = self.addError(message, span) catch {};

        return Node{
            .err = .{
                .span = span,
                .message = message,
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
};

// No convenience function needed - callers should use mod.zig parse() which provides source text
// TODO: If we need a convenience function in the future, it should require source text parameter
