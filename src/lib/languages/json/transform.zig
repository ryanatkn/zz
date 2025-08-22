const std = @import("std");

// Import JSON-specific types
const json_mod = @import("mod.zig");
const Token = @import("../../token/mod.zig").Token;
const AST = @import("ast.zig").AST;
const Node = @import("ast.zig").Node;

// Import fact system (optional)
const Fact = @import("../../fact/mod.zig").Fact;
const FactStore = @import("../../fact/mod.zig").FactStore;
const Span = @import("../../span/mod.zig").Span;
const packSpan = @import("../../span/mod.zig").packSpan;

/// Transform result containing optional stages
pub const TransformResult = struct {
    /// Always present: tokenized input
    tokens: []Token,
    /// Optional: facts extracted from tokens
    token_facts: ?[]Fact = null,
    /// Optional: parsed AST
    ast: ?AST = null,
    /// Optional: facts extracted from AST
    ast_facts: ?[]Fact = null,
    /// Source text for token.getText() calls
    source: []const u8,

    pub fn deinit(self: *TransformResult, allocator: std.mem.Allocator) void {
        allocator.free(self.tokens);

        if (self.token_facts) |facts| {
            allocator.free(facts);
        }

        if (self.ast) |*ast| {
            ast.deinit();
        }

        if (self.ast_facts) |facts| {
            allocator.free(facts);
        }
    }
};

/// Composable JSON transform pipeline
pub const JsonTransform = struct {
    allocator: std.mem.Allocator,

    // Stage configuration - caller decides what to pay for
    extract_token_facts: bool = false,
    build_ast: bool = true,
    extract_ast_facts: bool = false,

    // Parser options
    parser_options: json_mod.ParserOptions = .{},

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
        };
    }

    /// Configure what stages to run
    pub fn withTokenFacts(self: Self) Self {
        var result = self;
        result.extract_token_facts = true;
        return result;
    }

    pub fn withoutAST(self: Self) Self {
        var result = self;
        result.build_ast = false;
        return result;
    }

    pub fn withASTFacts(self: Self) Self {
        var result = self;
        result.extract_ast_facts = true;
        return result;
    }

    /// Main transform pipeline
    pub fn process(self: *Self, source: []const u8) !TransformResult {
        // Stage 1: Always tokenize
        const tokens = try json_mod.tokenize(self.allocator, source);
        errdefer self.allocator.free(tokens);

        var result = TransformResult{
            .tokens = tokens,
            .source = source,
        };

        // Stage 2: Optional token facts extraction
        if (self.extract_token_facts) {
            result.token_facts = try self.extractTokenFacts(tokens, source);
        }

        // Stage 3: Optional AST building
        if (self.build_ast) {
            result.ast = try json_mod.parse(self.allocator, tokens, source);
        }

        // Stage 4: Optional AST facts extraction
        if (self.extract_ast_facts and result.ast != null) {
            result.ast_facts = try self.extractASTFacts(result.ast.?);
        }

        return result;
    }

    /// Extract facts from tokens (TODO: implement full extraction)
    fn extractTokenFacts(self: *Self, tokens: []Token, source: []const u8) ![]Fact {
        _ = source;

        var facts = std.ArrayList(Fact).init(self.allocator);

        // Simple example: count tokens by type
        for (tokens) |token| {
            // TODO: Create meaningful facts from tokens
            // For now, just create placeholder facts
            const fact = Fact{
                .subject = packSpan(token.span),
                .predicate = .is_token,
                .object = .{ .none = 0 },
                .id = 0,
                .confidence = 1.0,
            };
            try facts.append(fact);
        }

        return facts.toOwnedSlice();
    }

    /// Extract facts from AST (TODO: implement full extraction)
    fn extractASTFacts(self: *Self, ast: AST) ![]Fact {
        var facts = std.ArrayList(Fact).init(self.allocator);

        // TODO: Walk AST and extract structural facts
        // For now, create placeholder for root node
        const span = ast.root.span();
        const fact = Fact{
            .subject = packSpan(span),
            .predicate = .is_boundary, // Mark root as a structural boundary
            .object = .{ .none = 0 },
            .id = 0,
            .confidence = 1.0,
        };
        try facts.append(fact);

        return facts.toOwnedSlice();
    }
};

/// Convenience functions for common use cases
pub const transform = struct {
    /// Just tokenize - no AST, no facts
    pub fn tokenizeOnly(allocator: std.mem.Allocator, source: []const u8) ![]Token {
        return json_mod.tokenize(allocator, source);
    }

    /// Full pipeline: tokens + AST
    pub fn parseJSON(allocator: std.mem.Allocator, source: []const u8) !TransformResult {
        var transformer = JsonTransform.init(allocator);
        return transformer.process(source);
    }

    /// Tokens + facts (no AST) - useful for fast analysis
    pub fn extractTokenFacts(allocator: std.mem.Allocator, source: []const u8) !TransformResult {
        var transformer = JsonTransform.init(allocator).withTokenFacts().withoutAST();
        return transformer.process(source);
    }

    /// Full analysis: tokens + AST + all facts
    pub fn fullAnalysis(allocator: std.mem.Allocator, source: []const u8) !TransformResult {
        var transformer = JsonTransform.init(allocator).withTokenFacts().withASTFacts();
        return transformer.process(source);
    }
};

// Tests
const testing = std.testing;

test "JSON transform - tokenize only" {
    const allocator = testing.allocator;
    const json_text = "{\"key\": \"value\"}";

    const tokens = try transform.tokenizeOnly(allocator, json_text);
    defer allocator.free(tokens);

    try testing.expect(tokens.len > 0);
}

test "JSON transform - full pipeline" {
    const allocator = testing.allocator;
    const json_text = "{\"key\": \"value\"}";

    var result = try transform.parseJSON(allocator, json_text);
    defer result.deinit(allocator);

    try testing.expect(result.tokens.len > 0);
    try testing.expect(result.ast != null);
}

test "JSON transform - custom pipeline" {
    const allocator = testing.allocator;
    const json_text = "{\"key\": \"value\"}";

    var transformer = JsonTransform.init(allocator).withTokenFacts().withASTFacts();
    var result = try transformer.process(json_text);
    defer result.deinit(allocator);

    try testing.expect(result.tokens.len > 0);
    try testing.expect(result.token_facts != null);
    try testing.expect(result.ast != null);
    try testing.expect(result.ast_facts != null);
}
