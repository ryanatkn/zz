const std = @import("std");

// Import ZON-specific types
const zon_mod = @import("mod.zig");
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

/// Composable ZON transform pipeline
pub const ZonTransform = struct {
    allocator: std.mem.Allocator,

    // Stage configuration - caller decides what to pay for
    extract_token_facts: bool = false,
    build_ast: bool = true,
    extract_ast_facts: bool = false,

    // Parser options
    parser_options: zon_mod.ParserOptions = .{},

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
        const tokens = try zon_mod.tokenize(self.allocator, source);
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
            result.ast = try zon_mod.parse(self.allocator, tokens, source);
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

        // Simple example: ZON-specific token analysis
        for (tokens) |token| {
            // TODO: Create ZON-specific facts (field names, dependencies, etc.)
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

        // TODO: Walk AST and extract ZON-specific structural facts
        // - Dependencies and their versions
        // - Build configuration facts
        // - Schema validation facts
        if (ast.root) |root| {
            const span = root.span();
            const fact = Fact{
                .subject = packSpan(span),
                .predicate = .is_boundary, // Root is a boundary
                .object = .{ .none = 0 },
                .id = 0,
                .confidence = 1.0,
            };
            try facts.append(fact);
        }

        return facts.toOwnedSlice();
    }
};

/// Convenience functions for common use cases
pub const transform = struct {
    /// Just tokenize - no AST, no facts
    pub fn tokenizeOnly(allocator: std.mem.Allocator, source: []const u8) ![]Token {
        return zon_mod.tokenize(allocator, source);
    }

    /// Full pipeline: tokens + AST
    pub fn parseZON(allocator: std.mem.Allocator, source: []const u8) !TransformResult {
        var transformer = ZonTransform.init(allocator);
        return transformer.process(source);
    }

    /// Tokens + facts (no AST) - useful for fast dependency analysis
    pub fn extractTokenFacts(allocator: std.mem.Allocator, source: []const u8) !TransformResult {
        var transformer = ZonTransform.init(allocator).withTokenFacts().withoutAST();
        return transformer.process(source);
    }

    /// Full analysis: tokens + AST + all facts
    pub fn fullAnalysis(allocator: std.mem.Allocator, source: []const u8) !TransformResult {
        var transformer = ZonTransform.init(allocator).withTokenFacts().withASTFacts();
        return transformer.process(source);
    }

    /// Extract build.zon dependencies (specialized for zz CLI)
    pub fn extractDependencies(allocator: std.mem.Allocator, build_zon_source: []const u8) !TransformResult {
        // TODO: Implement ZON-specific dependency extraction
        // This would be used by zz deps command
        var transformer = ZonTransform.init(allocator).withASTFacts();
        return transformer.process(build_zon_source);
    }
};

// Tests
const testing = std.testing;

test "ZON transform - tokenize only" {
    const allocator = testing.allocator;
    const zon_text = ".{ .name = \"test\" }";

    const tokens = try transform.tokenizeOnly(allocator, zon_text);
    defer allocator.free(tokens);

    try testing.expect(tokens.len > 0);
}

test "ZON transform - full pipeline" {
    const allocator = testing.allocator;
    const zon_text = ".{ .name = \"test\", .version = \"1.0.0\" }";

    var result = try transform.parseZON(allocator, zon_text);
    defer result.deinit(allocator);

    try testing.expect(result.tokens.len > 0);
    try testing.expect(result.ast != null);
}

test "ZON transform - custom pipeline" {
    const allocator = testing.allocator;
    const zon_text = ".{ .dependencies = .{} }";

    var transformer = ZonTransform.init(allocator).withTokenFacts().withASTFacts();
    var result = try transformer.process(zon_text);
    defer result.deinit(allocator);

    try testing.expect(result.tokens.len > 0);
    try testing.expect(result.token_facts != null);
    try testing.expect(result.ast != null);
    try testing.expect(result.ast_facts != null);
}
