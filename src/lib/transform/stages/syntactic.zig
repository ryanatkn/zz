const std = @import("std");
const transform_mod = @import("../transform.zig");
const Transform = transform_mod.Transform;
const Context = transform_mod.Context;
const types = @import("../types.zig");

// Import foundation types
const Token = @import("../../parser/foundation/types/token.zig").Token;
const AST = @import("../../ast/mod.zig").AST;
const Node = @import("../../ast/mod.zig").Node;
const Span = @import("../../parser/foundation/types/span.zig").Span;

// Import AST utilities
const visitor = @import("../../ast/visitor.zig");
const traversal = @import("../../ast/traversal.zig");
const builder = @import("../../ast/builder.zig");

/// Syntactic stage transform: Tokens ↔ AST
/// Provides bidirectional transformation between token streams and abstract syntax trees
pub const SyntacticTransform = Transform([]const Token, AST);

/// Interface for syntactic transforms (similar to IParser pattern)
/// Languages implement this to provide parsing capabilities
pub const ISyntacticTransform = struct {
    /// Forward: parse tokens into AST
    parseFn: *const fn (ctx: *Context, tokens: []const Token) anyerror!AST,

    /// Reverse: emit tokens from AST (format-preserving)
    emitFn: ?*const fn (ctx: *Context, ast: AST) anyerror![]const Token,

    /// Optional: parse with error recovery
    parseWithRecoveryFn: ?*const fn (ctx: *Context, tokens: []const Token) anyerror!ParseResult,

    /// Metadata about the transform
    metadata: types.TransformMetadata,

    const Self = @This();

    /// Convert to Transform interface
    pub fn toTransform(self: *const Self) SyntacticTransform {
        return .{
            .forward = self.parseFn,
            .reverse = self.emitFn,
            .forward_async = null,
            .reverse_async = null,
            .metadata = self.metadata,
            .impl = @constCast(@ptrCast(self)),
        };
    }
};

/// Parse result with error recovery information
pub const ParseResult = struct {
    ast: ?AST,
    errors: []ParseError,
    recovered_nodes: []RecoveredNode,

    pub fn deinit(self: *ParseResult, allocator: std.mem.Allocator) void {
        if (self.ast) |*ast| {
            ast.deinit();
        }
        for (self.errors) |err| {
            allocator.free(err.message);
        }
        allocator.free(self.errors);
        allocator.free(self.recovered_nodes);
    }
};

/// Parse error information
pub const ParseError = struct {
    message: []const u8,
    span: Span,
    severity: Severity,
    expected: ?[]const TokenKind = null,

    pub const Severity = enum {
        err, // Fatal error
        warning, // Warning
        info, // Information
    };

    pub const TokenKind = @import("../../parser/foundation/types/predicate.zig").TokenKind;
};

/// Recovered node during error recovery
pub const RecoveredNode = struct {
    node: *Node,
    confidence: f32, // 0.0 to 1.0
    missing_tokens: []const Token,
};

/// Helper to create a syntactic transform from existing parser
pub fn createSyntacticTransform(
    parse_fn: *const fn (*Context, []const Token) anyerror!AST,
    emit_fn: ?*const fn (*Context, AST) anyerror![]const Token,
    metadata: types.TransformMetadata,
) SyntacticTransform {
    return .{
        .forward = parse_fn,
        .reverse = emit_fn,
        .forward_async = null,
        .reverse_async = null,
        .metadata = metadata,
    };
}

/// Default token emitter that reconstructs tokens from AST
/// Uses visitor pattern to traverse AST and generate tokens
pub fn defaultEmitTokens(ctx: *Context, ast: AST) ![]const Token {
    var emitter = TokenEmitter.init(ctx.allocator);
    defer emitter.deinit();

    // Visit all nodes in the AST using the updated API
    var walker = traversal.ASTTraversal.init(ctx.allocator);
    try walker.walk(&ast.root, emitNode, &emitter, .depth_first_pre);

    return emitter.getTokens();
}

/// Token emitter visitor
const TokenEmitter = struct {
    allocator: std.mem.Allocator,
    tokens: std.ArrayList(Token),
    current_position: usize,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .tokens = std.ArrayList(Token).init(allocator),
            .current_position = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.tokens.deinit();
    }

    pub fn addToken(self: *Self, kind: @import("../../parser/foundation/types/predicate.zig").TokenKind, text: []const u8) !void {
        const span = Span.init(self.current_position, self.current_position + text.len);
        try self.tokens.append(Token.simple(span, kind, text, 0));
        self.current_position += text.len + 1; // +1 for space
    }

    pub fn getTokens(self: *Self) ![]const Token {
        return self.tokens.toOwnedSlice();
    }
};

fn emitNode(node: *const Node, context: ?*anyopaque) !bool {
    const emitter = @as(*TokenEmitter, @ptrCast(@alignCast(context.?)));
    const JsonRules = @import("../../ast/rules.zig").JsonRules;
    const CommonRules = @import("../../ast/rules.zig").CommonRules;

    // Use rule IDs for language-specific behavior
    switch (node.rule_id) {
        JsonRules.object => {
            try emitter.addToken(.delimiter, "{");
            // Process children
            for (node.children, 0..) |child, i| {
                if (i > 0) try emitter.addToken(.delimiter, ",");
                _ = try emitNode(&child, context);
            }
            try emitter.addToken(.delimiter, "}");
        },
        JsonRules.array => {
            try emitter.addToken(.delimiter, "[");
            for (node.children, 0..) |child, i| {
                if (i > 0) try emitter.addToken(.delimiter, ",");
                _ = try emitNode(&child, context);
            }
            try emitter.addToken(.delimiter, "]");
        },
        JsonRules.string_literal => {
            try emitter.addToken(.string_literal, node.text);
        },
        JsonRules.number_literal => {
            try emitter.addToken(.number_literal, node.text);
        },
        JsonRules.boolean_literal => {
            try emitter.addToken(.boolean_literal, node.text);
        },
        @intFromEnum(CommonRules.null_literal) => {
            try emitter.addToken(.null_literal, node.text);
        },
        JsonRules.member => {
            // Key-value pair handled by walker traversal
            try emitter.addToken(.delimiter, ":");
        },
        else => {
            // Generic handling for other node types
            if (node.text.len > 0) {
                try emitter.addToken(.identifier, node.text);
            }
        },
    }

    return true; // Continue traversal
}

/// Incremental parser interface for editor integration
pub const IncrementalParser = struct {
    ctx: *Context,
    parser: ISyntacticTransform,
    current_ast: ?AST,
    current_tokens: []const Token,
    generation: u32,

    const Self = @This();

    pub fn init(ctx: *Context, parser: ISyntacticTransform) Self {
        return .{
            .ctx = ctx,
            .parser = parser,
            .current_ast = null,
            .current_tokens = &.{},
            .generation = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.current_ast) |*ast| {
            ast.deinit();
        }
        if (self.current_tokens.len > 0) {
            self.ctx.allocator.free(self.current_tokens);
        }
    }

    /// Update AST with new tokens
    pub fn update(self: *Self, tokens: []const Token) !void {
        // Free old AST
        if (self.current_ast) |*ast| {
            ast.deinit();
        }

        // Parse new tokens
        self.current_ast = try self.parser.parseFn(self.ctx, tokens);

        // Update stored tokens
        if (self.current_tokens.len > 0) {
            self.ctx.allocator.free(self.current_tokens);
        }
        self.current_tokens = try self.ctx.allocator.dupe(Token, tokens);
        self.generation += 1;
    }

    /// Get current AST
    pub fn getAST(self: Self) ?AST {
        return self.current_ast;
    }

    /// Get generation number for change tracking
    pub fn getGeneration(self: Self) u32 {
        return self.generation;
    }
};

/// AST differ for incremental updates
pub const ASTDiffer = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    /// Compare two ASTs and find differences
    pub fn diff(self: Self, old_ast: AST, new_ast: AST) ![]ASTDelta {
        var deltas = std.ArrayList(ASTDelta).init(self.allocator);
        defer deltas.deinit();

        try self.diffNodes(old_ast.root, new_ast.root, &deltas);

        return deltas.toOwnedSlice();
    }

    fn diffNodes(self: Self, old_node: ?*Node, new_node: ?*Node, deltas: *std.ArrayList(ASTDelta)) !void {
        if (old_node == null and new_node == null) return;

        if (old_node == null and new_node != null) {
            try deltas.append(.{ .kind = .added, .node = new_node.? });
            return;
        }

        if (old_node != null and new_node == null) {
            try deltas.append(.{ .kind = .removed, .node = old_node.? });
            return;
        }

        // Both nodes exist - check if modified
        if (!nodesEqual(old_node.?, new_node.?)) {
            try deltas.append(.{ .kind = .modified, .node = new_node.?, .old_node = old_node });
        }

        // Recursively diff children
        const max_children = @max(old_node.?.children.len, new_node.?.children.len);
        var i: usize = 0;
        while (i < max_children) : (i += 1) {
            const old_child = if (i < old_node.?.children.len) old_node.?.children[i] else null;
            const new_child = if (i < new_node.?.children.len) new_node.?.children[i] else null;
            try self.diffNodes(old_child, new_child, deltas);
        }
    }

    fn nodesEqual(a: *Node, b: *Node) bool {
        if (a.type != b.type) return false;

        const a_value = a.value orelse "";
        const b_value = b.value orelse "";
        if (!std.mem.eql(u8, a_value, b_value)) return false;

        return a.children.len == b.children.len;
    }
};

/// AST delta for incremental updates
pub const ASTDelta = struct {
    kind: DeltaKind,
    node: *Node,
    old_node: ?*Node = null,

    pub const DeltaKind = enum {
        added,
        removed,
        modified,
    };
};

// Tests
const testing = std.testing;

test "TokenEmitter basic functionality" {
    const allocator = testing.allocator;

    var emitter = TokenEmitter.init(allocator);
    defer emitter.deinit();

    try emitter.addToken(.delimiter, "{");
    try emitter.addToken(.string_literal, "key");
    try emitter.addToken(.delimiter, ":");
    try emitter.addToken(.string_literal, "value");
    try emitter.addToken(.delimiter, "}");

    const tokens = try emitter.getTokens();
    defer allocator.free(tokens);

    try testing.expectEqual(@as(usize, 5), tokens.len);
    try testing.expectEqual(@import("../../parser/foundation/types/predicate.zig").TokenKind.delimiter, tokens[0].kind);
    try testing.expectEqualStrings("{", tokens[0].text);
}

test "IncrementalParser basic usage" {
    const allocator = testing.allocator;

    var ctx = Context.init(allocator);
    defer ctx.deinit();

    const mock_parser = ISyntacticTransform{
        .parseFn = struct {
            fn parse(context: *Context, tokens: []const Token) !AST {
                _ = tokens;
                var ast = AST.init(context.allocator);
                ast.root = try @import("../../ast/node.zig").createLeafNode(context.allocator, @intFromEnum(@import("../../ast/rules.zig").CommonRules.null_literal), "null", 0, 4);
                return ast;
            }
        }.parse,
        .emitFn = null,
        .parseWithRecoveryFn = null,
        .metadata = .{
            .name = "mock_parser",
            .description = "Test parser",
        },
    };

    var incremental = IncrementalParser.init(&ctx, mock_parser);
    defer incremental.deinit();

    const tokens = [_]Token{
        Token.simple(Span.init(0, 4), .null_literal, "null", 0),
    };

    try incremental.update(&tokens);

    try testing.expectEqual(@as(u32, 1), incremental.getGeneration());
    try testing.expect(incremental.getAST() != null);
}
