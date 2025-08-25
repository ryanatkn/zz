/// JSON Streaming Parser - Core Structure and Main Methods
///
/// SIMPLIFIED: Uses streaming lexer directly, no token arrays
/// Handles trivia inline, direct field access to tokens
const std = @import("std");
const Span = @import("../../../span/mod.zig").Span;
const unpackSpan = @import("../../../span/mod.zig").unpackSpan;
const TokenIterator = @import("../../../token/iterator.zig").TokenIterator;
const Token = @import("../../../token/stream_token.zig").Token;
const JsonToken = @import("../token/types.zig").Token;
const TokenKind = @import("../token/mod.zig").TokenKind;
const ErrorCode = @import("../token/types.zig").ErrorCode;
const UnicodeMode = @import("../mod.zig").UnicodeMode;

// Use local JSON AST
const json_ast = @import("../ast/mod.zig");
const AST = json_ast.AST;
const Node = json_ast.Node;
const NodeKind = json_ast.NodeKind;

// Import value parsing methods
const parser_values = @import("values.zig");

/// JSON Parser using streaming lexer
///
/// Features:
/// - Direct streaming tokenization (no intermediate array)
/// - Recursive descent parsing
/// - Error recovery
/// - Zero-allocation tokenization
pub const Parser = struct {
    allocator: std.mem.Allocator,
    iterator: TokenIterator,
    source: []const u8,
    current: ?Token,
    errors: std.ArrayList(ParseError),
    allow_trailing_commas: bool,
    allow_comments: bool,
    collect_all_errors: bool,

    const Self = @This();

    pub const ParseError = struct {
        message: []const u8,
        span: Span,
        severity: Severity,

        pub const Severity = enum { err, warning };
    };

    pub const ParserOptions = struct {
        allow_trailing_commas: bool = true, // Permissive about fixable issues
        allow_comments: bool = true, // Default: permissive about JSON5 comments
        collect_all_errors: bool = true, // Default: collect all errors for comprehensive diagnostics
        unicode_mode: UnicodeMode = .strict, // Default: RFC 9839 strict validation
    };

    /// Initialize parser with streaming lexer
    pub fn init(allocator: std.mem.Allocator, source: []const u8, options: ParserOptions) !Self {
        const lexer_options = @import("../../lexer_registry.zig").LexerOptions{
            .json = .{ .unicode_mode = options.unicode_mode },
        };

        var parser = Self{
            .allocator = allocator,
            .iterator = try TokenIterator.initWithOptions(source, .json, lexer_options),
            .source = source,
            .current = null,
            .errors = std.ArrayList(ParseError).init(allocator),
            .allow_trailing_commas = options.allow_trailing_commas,
            .allow_comments = options.allow_comments,
            .collect_all_errors = options.collect_all_errors,
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

    /// Parse JSON into AST
    pub fn parse(self: *Self) !AST {
        // Allocate arena on heap so it persists with AST
        const arena = try self.allocator.create(std.heap.ArenaAllocator);
        arena.* = std.heap.ArenaAllocator.init(self.allocator);
        var arena_needs_cleanup = true;
        defer if (arena_needs_cleanup) {
            arena.deinit();
            self.allocator.destroy(arena);
        };

        const arena_allocator = arena.allocator();

        // Parse root value - handle errors according to collect_all_errors setting
        const root_value = self.parseValue(arena_allocator) catch |err| blk: {
            if (!self.collect_all_errors) {
                // In fail-fast mode, propagate error immediately
                // arena_needs_cleanup is true, so defer will handle cleanup
                return err;
            }
            // In collect-all-errors mode, create null node and continue
            break :blk Node{ .null = Span.init(0, 0) };
        };

        // Create root node
        const root_node = try arena_allocator.create(Node);
        root_node.* = root_value;

        // Check for trailing content
        if (self.current) |token| {
            switch (token) {
                .json => |t| {
                    if (t.kind != .eof) {
                        const span = unpackSpan(t.span);
                        try self.addError("Unexpected token after JSON value", span);
                    }
                },
                else => unreachable,
            }
        }

        // After parsing, if we have actual errors (not just warnings), signal invalid JSON
        // Only return error for actual errors, not warnings (like trailing commas when allowed)
        var has_errors = false;
        for (self.errors.items) |parse_error| {
            if (parse_error.severity == .err) {
                has_errors = true;
                break;
            }
        }
        if (has_errors) {
            // The AST is still created for partial analysis, but we signal it's invalid
            // arena_needs_cleanup is true, so defer will handle cleanup
            return error.ParseError;
        }

        // Create nodes array
        var nodes = std.ArrayList(Node).init(arena_allocator);
        try nodes.append(root_value);
        const nodes_slice = try nodes.toOwnedSlice();

        // Success! Transfer arena ownership to AST
        arena_needs_cleanup = false;

        return AST{
            .root = root_node,
            .arena = arena,
            .source = self.source,
            .nodes = nodes_slice,
        };
    }

    /// Get parse errors
    pub fn getErrors(self: *Self) []const ParseError {
        return self.errors.items;
    }

    // =========================================================================
    // Token Navigation
    // =========================================================================

    /// Advance to next meaningful token (skip trivia)
    pub fn advance(self: *Self) !?Token {
        while (self.iterator.next()) |token| {
            switch (token) {
                .json => |t| {
                    // Skip whitespace always
                    if (t.kind == .whitespace) {
                        continue;
                    }
                    // Handle comments based on allow_comments option
                    if (t.kind == .comment) {
                        if (self.allow_comments) {
                            continue; // Skip allowed comments
                        } else {
                            // Comments not allowed - treat as error
                            const span = unpackSpan(t.span);
                            try self.addError("Comments not allowed in JSON", span);
                            continue; // Skip the comment token but record error
                        }
                    }
                    // Handle error tokens from lexer
                    if (t.kind == .err) {
                        const span = unpackSpan(t.span);
                        const error_code = @as(ErrorCode, @enumFromInt(t.data));
                        const message = error_code.getMessage();
                        try self.addError(message, span);
                        // Return the error token to prevent infinite loop
                        self.current = token;
                        return token;
                    }
                    self.current = token;
                    return token;
                },
                else => unreachable, // Parser only handles JSON
            }
        }
        self.current = null;
        return null;
    }

    /// Peek at current JSON token (extracts from union)
    pub fn peekJson(self: *Self) ?@import("../token/types.zig").Token {
        if (self.current) |token| {
            switch (token) {
                .json => |json_token| return json_token,
                else => unreachable,
            }
        }
        return null;
    }

    /// Expect and consume a specific JSON token kind
    pub fn expectJson(self: *Self, kind: TokenKind) !@import("../token/types.zig").Token {
        if (self.peekJson()) |json_token| {
            if (json_token.kind == kind) {
                const result = json_token;
                _ = try self.advance();
                return result;
            }
            const span = unpackSpan(json_token.span);
            // Use a static buffer to avoid memory leaks for error messages
            var buf: [128]u8 = undefined;
            const msg = if (json_token.kind == .err) blk: {
                // Extract error code from data field and get specific message
                const error_code: @import("../token/types.zig").ErrorCode = @enumFromInt(json_token.data);
                break :blk error_code.getMessage();
            } else blk: {
                break :blk std.fmt.bufPrint(&buf, "Expected {s}, got {s}", .{ @tagName(kind), @tagName(json_token.kind) }) catch "Parse error";
            };
            try self.addError(msg, span);
            return error.UnexpectedToken;
        }

        try self.addError("Unexpected end of input", Span.init(@intCast(self.source.len), @intCast(self.source.len)));
        return error.UnexpectedEndOfInput;
    }

    // =========================================================================
    // Value Parsing Dispatcher
    // =========================================================================

    pub fn parseValue(self: *Self, allocator: std.mem.Allocator) anyerror!Node {
        const token = self.peekJson() orelse {
            try self.addError("Unexpected end of input", Span.init(0, 0));
            return self.createErrorNode(allocator);
        };

        return switch (token.kind) {
            .string_value => parser_values.parseString(self, allocator),
            .number_value => parser_values.parseNumber(self, allocator),
            .boolean_true, .boolean_false => parser_values.parseBoolean(self, allocator),
            .null_value => parser_values.parseNull(self, allocator),
            .object_start => self.parseObject(allocator),
            .array_start => self.parseArray(allocator),
            else => {
                const span = unpackSpan(token.span);
                const msg = if (token.kind == .err) blk: {
                    // Extract error code from data field and get specific message
                    const error_code: @import("../token/types.zig").ErrorCode = @enumFromInt(token.data);
                    break :blk try allocator.dupe(u8, error_code.getMessage());
                } else blk: {
                    break :blk try std.fmt.allocPrint(allocator, "Unexpected token: {s}", .{@tagName(token.kind)});
                };
                try self.addError(msg, span);
                _ = try self.advance(); // Skip bad token
                return self.createErrorNode(allocator);
            },
        };
    }

    pub fn parseObject(self: *Self, allocator: std.mem.Allocator) !Node {
        const start_token = try self.expectJson(.object_start);
        const start_span = unpackSpan(start_token.span);

        var properties = std.ArrayList(Node).init(allocator);
        defer properties.deinit();

        // Check for empty object
        if (self.peekJson()) |token| {
            if (token.kind == .object_end) {
                const end_token = try self.expectJson(.object_end);
                const end_span = unpackSpan(end_token.span);

                return Node{
                    .object = .{
                        .span = Span.init(start_span.start, end_span.end),
                        .properties = try properties.toOwnedSlice(),
                    },
                };
            }
        }

        // Parse properties
        while (true) {
            // Parse property name - handle malformed keys gracefully
            const name_token = self.expectJson(.property_name) catch |err| switch (err) {
                error.UnexpectedToken, error.UnexpectedEndOfInput => blk: {
                    // Try to use current token as key, skip malformed object
                    if (self.peekJson()) |token| {
                        _ = try self.advance(); // consume the bad token
                        // Create a synthetic property name token using the malformed token's span
                        const span = unpackSpan(token.span);
                        break :blk JsonToken.init(span, .property_name, 0);
                    } else {
                        // End of input, break out of property parsing
                        break;
                    }
                },
                else => return err,
            };
            const name_span = unpackSpan(name_token.span);
            const name_raw = self.source[name_span.start..name_span.end];
            const name_value = try parser_values.processStringEscapes(self, allocator, name_raw);

            // Expect colon - handle missing colon gracefully
            _ = self.expectJson(.colon) catch |err| switch (err) {
                error.UnexpectedToken, error.UnexpectedEndOfInput => {
                    // Error already recorded, continue with value parsing
                },
                else => return err,
            };

            // Parse value - handle missing value gracefully
            const value_node = self.parseValue(allocator) catch |err| switch (err) {
                // parseValue already handles errors gracefully by returning error nodes
                else => return err,
            };

            // Create key node for property
            const key_node = try allocator.create(Node);
            key_node.* = Node{
                .string = .{
                    .span = name_span,
                    .value = name_value,
                },
            };

            // Create value node for property
            const value_ptr = try allocator.create(Node);
            value_ptr.* = value_node;

            // Create property node
            const property = Node{
                .property = .{
                    .span = Span.init(name_span.start, value_node.span().end),
                    .key = key_node,
                    .value = value_ptr,
                },
            };

            try properties.append(property);

            // Check for continuation
            if (self.peekJson()) |token| {
                if (token.kind == .comma) {
                    _ = try self.advance();

                    // Check for trailing comma
                    if (self.peekJson()) |next| {
                        if (next.kind == .object_end) {
                            if (!self.allow_trailing_commas) {
                                const span = unpackSpan(next.span);
                                try self.addError("Trailing comma not allowed", span);
                            }
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
                try self.addError("Unexpected end of input in object", Span.init(@intCast(self.source.len), @intCast(self.source.len)));
                break;
            }
        }

        // Try to expect closing brace, but handle missing brace gracefully
        const end_span = if (self.expectJson(.object_end)) |end_token|
            unpackSpan(end_token.span)
        else |err| switch (err) {
            error.UnexpectedToken, error.UnexpectedEndOfInput =>
            // Error already recorded by expect(), use last valid position
            Span.init(@intCast(self.source.len), @intCast(self.source.len)),
            else => return err,
        };

        return Node{
            .object = .{
                .span = Span.init(start_span.start, end_span.end),
                .properties = try properties.toOwnedSlice(),
            },
        };
    }

    pub fn parseArray(self: *Self, allocator: std.mem.Allocator) !Node {
        const start_token = try self.expectJson(.array_start);
        const start_span = unpackSpan(start_token.span);

        var elements = std.ArrayList(Node).init(allocator);
        defer elements.deinit();

        // Check for empty array
        if (self.peekJson()) |token| {
            if (token.kind == .array_end) {
                const end_token = try self.expectJson(.array_end);
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
            if (self.peekJson()) |token| {
                if (token.kind == .comma) {
                    _ = try self.advance();

                    // Check for trailing comma
                    if (self.peekJson()) |next| {
                        if (next.kind == .array_end) {
                            if (!self.allow_trailing_commas) {
                                const span = unpackSpan(next.span);
                                try self.addError("Trailing comma not allowed", span);
                            }
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
                try self.addError("Unexpected end of input in array", Span.init(@intCast(self.source.len), @intCast(self.source.len)));
                break;
            }
        }

        // Try to expect closing bracket, but handle missing bracket gracefully
        const end_span = if (self.expectJson(.array_end)) |end_token|
            unpackSpan(end_token.span)
        else |err| switch (err) {
            error.UnexpectedToken, error.UnexpectedEndOfInput =>
            // Error already recorded by expect(), use last valid position
            Span.init(@intCast(self.source.len), @intCast(self.source.len)),
            else => return err,
        };

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

    pub fn createErrorNode(self: *Self, allocator: std.mem.Allocator) Node {
        _ = self;
        const message = allocator.dupe(u8, "Parse error") catch "Parse error";
        return Node{
            .err = .{
                .span = Span.init(0, 0),
                .message = message,
                .partial = null,
            },
        };
    }

    pub fn addError(self: *Self, message: []const u8, span: Span) !void {
        const msg = try self.allocator.dupe(u8, message);
        try self.errors.append(.{
            .message = msg,
            .span = span,
            .severity = .err,
        });

        // If not collecting all errors, stop immediately after first error
        if (!self.collect_all_errors) {
            return error.ParseError;
        }
    }

    pub fn addWarning(self: *Self, message: []const u8, span: Span) !void {
        const msg = try self.allocator.dupe(u8, message);
        try self.errors.append(.{
            .message = msg,
            .span = span,
            .severity = .warning,
        });
        // Warnings never cause immediate failure, even in fail-fast mode
    }
};
