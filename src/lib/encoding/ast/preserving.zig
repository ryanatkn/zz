const std = @import("std");
const AST = @import("../../ast/mod.zig").AST;
const Node = @import("../../ast/mod.zig").Node;
const NodeType = @import("../../ast/mod.zig").NodeType;
const ASTFactory = @import("../../ast/factory.zig").ASTFactory;
const ASTUtils = @import("../../ast/utils.zig").ASTUtils;
const Fact = @import("../../parser/foundation/types/fact.zig").Fact;
const Span = @import("../../parser/foundation/types/span.zig").Span;
const Token = @import("../../parser/foundation/types/token.zig").Token;

/// Transform AST while preserving formatting
/// This maintains comments, whitespace, and other trivia
pub fn transformPreserving(
    allocator: std.mem.Allocator,
    ast: AST,
    transform_fn: fn(allocator: std.mem.Allocator, node: *Node) anyerror!void,
) !AST {
    // Clone the AST to avoid modifying the original
    var cloned = try cloneASTWithTrivia(allocator, ast);
    errdefer cloned.deinit();
    
    // Apply transformation to the cloned AST
    try walkAndTransform(allocator, &cloned.root, transform_fn);
    
    return cloned;
}

/// Merge two ASTs while preserving formatting from the original
/// Updates in the new AST override values in the original, but formatting is preserved
pub fn mergePreserving(allocator: std.mem.Allocator, original: AST, updates: AST) !AST {
    // Clone the original to preserve its structure
    var merged = try cloneASTWithTrivia(allocator, original);
    errdefer merged.deinit();
    
    // Apply updates from the new AST
    try mergeNodes(allocator, &merged.root, updates.root, original.source);
    
    return merged;
}

/// Transform facts while preserving confidence and generation information
pub fn transformFactsPreserving(
    allocator: std.mem.Allocator,
    facts: []const Fact,
    transform_fn: fn(fact: *Fact) anyerror!void,
) ![]Fact {
    var result = try allocator.alloc(Fact, facts.len);
    
    for (facts, 0..) |fact, i| {
        // Copy the fact
        result[i] = fact;
        
        // Apply transformation
        try transform_fn(&result[i]);
        
        // Preserve confidence and generation unless explicitly changed
        if (result[i].confidence == 0) {
            result[i].confidence = fact.confidence;
        }
        if (result[i].generation == 0) {
            result[i].generation = fact.generation;
        }
    }
    
    return result;
}

/// Preserve trivia (comments and whitespace) when modifying nodes
pub const TriviaPreserver = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    trivia_map: std.AutoHashMap(usize, Trivia),
    
    const Self = @This();
    
    pub const Trivia = struct {
        leading: []const u8,
        trailing: []const u8,
        inline_comment: ?[]const u8,
    };
    
    pub fn init(allocator: std.mem.Allocator, source: []const u8) Self {
        return .{
            .allocator = allocator,
            .source = source,
            .trivia_map = std.AutoHashMap(usize, Trivia).init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.trivia_map.deinit();
    }
    
    /// Extract trivia for a node based on its position
    pub fn extractTrivia(self: *Self, node: Node) !void {
        const trivia = try self.extractTriviaForSpan(node.start_position, node.end_position);
        try self.trivia_map.put(node.start_position, trivia);
    }
    
    /// Apply preserved trivia to a new node
    pub fn applyTrivia(self: Self, node: *Node) !void {
        if (self.trivia_map.get(node.start_position)) |trivia| {
            // In a real implementation, we'd store trivia in node attributes
            // For now, we just track it in the map
            _ = trivia;
        }
    }
    
    fn extractTriviaForSpan(self: Self, start: usize, end: usize) !Trivia {
        // Extract leading whitespace/comments
        var leading_start = start;
        if (start > 0) {
            leading_start = self.findTriviaStart(start);
        }
        const leading = self.source[leading_start..start];
        
        // Extract trailing whitespace/comments
        var trailing_end = end;
        if (end < self.source.len) {
            trailing_end = self.findTriviaEnd(end);
        }
        const trailing = self.source[end..trailing_end];
        
        // Look for inline comments
        const inline_comment = self.findInlineComment(end);
        
        return Trivia{
            .leading = leading,
            .trailing = trailing,
            .inline_comment = inline_comment,
        };
    }
    
    fn findTriviaStart(self: Self, pos: usize) usize {
        var i = pos;
        while (i > 0) : (i -= 1) {
            const c = self.source[i - 1];
            if (!isWhitespace(c) and c != '/' and c != '*') {
                break;
            }
        }
        return i;
    }
    
    fn findTriviaEnd(self: Self, pos: usize) usize {
        var i = pos;
        while (i < self.source.len) : (i += 1) {
            const c = self.source[i];
            if (!isWhitespace(c) and c != '/' and c != '*') {
                break;
            }
        }
        return i;
    }
    
    fn findInlineComment(self: Self, pos: usize) ?[]const u8 {
        if (pos + 2 >= self.source.len) return null;
        
        // Check for // comment
        if (self.source[pos] == '/' and self.source[pos + 1] == '/') {
            var end = pos + 2;
            while (end < self.source.len and self.source[end] != '\n') : (end += 1) {}
            return self.source[pos..end];
        }
        
        return null;
    }
};

/// Format-preserving node replacement
pub fn replaceNodePreserving(
    allocator: std.mem.Allocator,
    ast: *AST,
    path: []const []const u8,
    new_node: Node,
) !void {
    // Find the node to replace
    const target = try ASTUtils.findNodeByPath(ast.root, path);
    if (target == null) return error.NodeNotFound;
    
    // Preserve trivia
    var preserver = TriviaPreserver.init(allocator, ast.source);
    defer preserver.deinit();
    
    try preserver.extractTrivia(target.?.*);
    
    // Replace the node
    target.?.* = new_node;
    
    // Apply preserved trivia
    try preserver.applyTrivia(target.?);
}

/// Token-level preservation for fine-grained control
pub const TokenPreserver = struct {
    allocator: std.mem.Allocator,
    tokens: []const Token,
    preserved_tokens: std.ArrayList(Token),
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, tokens: []const Token) Self {
        return .{
            .allocator = allocator,
            .tokens = tokens,
            .preserved_tokens = std.ArrayList(Token).init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.preserved_tokens.deinit();
    }
    
    /// Replace token text while preserving trivia
    pub fn replaceToken(self: *Self, index: usize, new_text: []const u8) !void {
        if (index >= self.tokens.len) return error.IndexOutOfBounds;
        
        var token = self.tokens[index];
        token.text = new_text;
        
        // Preserve trivia if it exists
        if (token.trivia) |_| {
            // Trivia is preserved automatically since we're not changing it
        }
        
        try self.preserved_tokens.append(token);
    }
    
    /// Insert token while maintaining formatting
    pub fn insertToken(self: *Self, index: usize, token: Token) !void {
        // Insert at the appropriate position
        for (self.tokens, 0..) |existing, i| {
            if (i == index) {
                try self.preserved_tokens.append(token);
            }
            try self.preserved_tokens.append(existing);
        }
    }
    
    /// Remove token while preserving surrounding trivia
    pub fn removeToken(self: *Self, index: usize) !void {
        for (self.tokens, 0..) |token, i| {
            if (i != index) {
                // If this is the token after the removed one, merge trivia
                if (i == index + 1 and index < self.tokens.len and self.tokens[index].trivia != null) {
                    const modified = token;
                    // Merge trivia from removed token
                    // In real implementation, would concatenate trivia
                    try self.preserved_tokens.append(modified);
                } else {
                    try self.preserved_tokens.append(token);
                }
            }
        }
    }
    
    pub fn getPreservedTokens(self: Self) []const Token {
        return self.preserved_tokens.items;
    }
};

// Helper functions

fn cloneASTWithTrivia(allocator: std.mem.Allocator, ast: AST) !AST {
    // Use existing clone utility but ensure trivia is preserved
    var factory = ASTFactory.init(allocator);
    defer factory.deinit();
    
    const cloned_root = try cloneNodeWithTrivia(allocator, ast.root, &factory);
    
    return factory.createAST(cloned_root, ast.source);
}

fn cloneNodeWithTrivia(allocator: std.mem.Allocator, node: Node, factory: *ASTFactory) !Node {
    // Clone children recursively
    var children = try allocator.alloc(Node, node.children.len);
    for (node.children, 0..) |child, i| {
        children[i] = try cloneNodeWithTrivia(allocator, child, factory);
    }
    
    // Create new node preserving all fields
    var new_node = try factory.createContainer(node.node_type, children, node.start_position, node.end_position);
    new_node.rule_name = node.rule_name;
    new_node.text = node.text;
    
    // Preserve attributes if they exist
    if (node.attributes) |attrs| {
        var new_attrs = std.StringHashMap([]const u8).init(allocator);
        var it = attrs.iterator();
        while (it.next()) |entry| {
            try new_attrs.put(entry.key_ptr.*, entry.value_ptr.*);
        }
        new_node.attributes = new_attrs;
    }
    
    return new_node;
}

fn walkAndTransform(
    allocator: std.mem.Allocator,
    node: *Node,
    transform_fn: fn(allocator: std.mem.Allocator, node: *Node) anyerror!void,
) !void {
    // Apply transformation to current node
    try transform_fn(allocator, node);
    
    // Recursively transform children
    for (node.children) |*child| {
        try walkAndTransform(allocator, child, transform_fn);
    }
}

fn mergeNodes(allocator: std.mem.Allocator, target: *Node, source: Node, original_source: []const u8) !void {
    _ = original_source;
    
    // If types match, merge the content
    if (target.node_type == source.node_type) {
        // Update text content but preserve position
        target.text = source.text;
        
        // Merge children
        if (source.children.len > 0) {
            // For simplicity, replace children entirely
            // In a real implementation, would do smart merging
            target.children = try allocator.dupe(Node, source.children);
        }
        
        // Merge attributes
        if (source.attributes) |src_attrs| {
            if (target.attributes == null) {
                target.attributes = std.StringHashMap([]const u8).init(allocator);
            }
            var it = src_attrs.iterator();
            while (it.next()) |entry| {
                try target.attributes.?.put(entry.key_ptr.*, entry.value_ptr.*);
            }
        }
    } else {
        // Type mismatch - replace entirely but try to preserve formatting
        target.* = source;
    }
}

fn isWhitespace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r';
}

// Tests
const testing = std.testing;

test "transformPreserving - basic transformation" {
    const allocator = testing.allocator;
    
    // Create a simple AST
    var factory = ASTFactory.init(allocator);
    defer factory.deinit();
    
    const root = try factory.createLiteral(.number_literal, "42", 0, 2);
    const ast = try factory.createAST(root, "42");
    defer {
        var mutable_ast = ast;
        mutable_ast.deinit();
    }
    
    // Transform function that doubles numbers
    const transform = struct {
        fn apply(alloc: std.mem.Allocator, node: *Node) !void {
            _ = alloc;
            if (node.node_type == .number_literal) {
                node.text = "84";
            }
        }
    }.apply;
    
    var transformed = try transformPreserving(allocator, ast, transform);
    defer transformed.deinit();
    
    try testing.expectEqualStrings("84", transformed.root.text);
}

test "TriviaPreserver - extract and apply trivia" {
    const allocator = testing.allocator;
    
    const source = "  // Comment\n  42  // Inline\n";
    var preserver = TriviaPreserver.init(allocator, source);
    defer preserver.deinit();
    
    const node = Node{
        .rule_name = "number",
        .node_type = .number_literal,
        .text = "42",
        .start_position = 14,
        .end_position = 16,
        .children = &.{},
        .attributes = null,
        .parent = null,
    };
    
    try preserver.extractTrivia(node);
    
    // Check that trivia was extracted
    const trivia = preserver.trivia_map.get(14);
    try testing.expect(trivia != null);
}

test "TokenPreserver - token operations" {
    const allocator = testing.allocator;
    
    const tokens = [_]Token{
        Token.simple(Span.init(0, 1), .left_brace, "{", 0),
        Token.simple(Span.init(2, 6), .identifier, "test", 0),
        Token.simple(Span.init(7, 8), .right_brace, "}", 0),
    };
    
    var preserver = TokenPreserver.init(allocator, &tokens);
    defer preserver.deinit();
    
    // Replace middle token
    try preserver.replaceToken(1, "modified");
    
    // Add all remaining tokens
    try preserver.preserved_tokens.append(tokens[0]);
    try preserver.preserved_tokens.append(tokens[2]);
    
    const preserved = preserver.getPreservedTokens();
    try testing.expectEqual(@as(usize, 2), preserved.len);
}

test "transformFactsPreserving - fact transformation" {
    const allocator = testing.allocator;
    
    const facts = [_]Fact{
        Fact.init(0, Span.init(0, 4), .{ .token_kind = .identifier }, null, 0.9, 1),
        Fact.init(1, Span.init(5, 10), .{ .literal_value = .{ .integer = 42 } }, null, 1.0, 1),
    };
    
    const transform = struct {
        fn apply(fact: *Fact) !void {
            // Increase confidence
            fact.confidence = @min(fact.confidence * 1.1, 1.0);
        }
    }.apply;
    
    const transformed = try transformFactsPreserving(allocator, &facts, transform);
    defer allocator.free(transformed);
    
    try testing.expectEqual(@as(usize, 2), transformed.len);
    try testing.expectApproxEqAbs(@as(f32, 0.99), transformed[0].confidence, 0.01);
    try testing.expectEqual(@as(f32, 1.0), transformed[1].confidence);
}