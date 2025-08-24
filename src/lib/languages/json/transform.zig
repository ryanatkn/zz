const std = @import("std");

// JSON Transform System - AST-based transformation with streaming parser support
// Provides unified interface for parsing JSON source into AST and extracting semantic facts.

// Import JSON-specific types
const json_mod = @import("mod.zig");
const StreamToken = @import("../../token/mod.zig").StreamToken;
const AST = @import("ast.zig").AST;
const Node = @import("ast.zig").Node;

// Import fact system (optional)
const Fact = @import("../../fact/mod.zig").Fact;
const Value = @import("../../fact/mod.zig").Value;
const FactStore = @import("../../fact/mod.zig").FactStore;
const Span = @import("../../span/mod.zig").Span;
const packSpan = @import("../../span/mod.zig").packSpan;

/// Transform result containing AST and optional semantic facts
pub const TransformResult = struct {
    /// Legacy token array (not used in streaming architecture)
    tokens: []StreamToken,
    /// Legacy token facts (not used in streaming architecture)
    token_facts: ?[]Fact = null,
    /// Parsed AST from streaming parser
    ast: ?AST = null,
    /// Optional: AST facts extracted from AST
    ast_facts: ?[]Fact = null,
    /// Source text reference
    source: []const u8,

    pub fn deinit(self: *TransformResult, allocator: std.mem.Allocator) void {
        allocator.free(self.tokens);
        if (self.token_facts) |facts| {
            allocator.free(facts);
        }
        if (self.ast) |ast| {
            // TODO: Call AST deinit when implemented
            _ = ast;
        }
        if (self.ast_facts) |facts| {
            allocator.free(facts);
        }
    }
};

/// Transform options - controls what stages to execute
pub const TransformOptions = struct {
    // What to build
    extract_token_facts: bool = false,
    build_ast: bool = true,
    extract_ast_facts: bool = false,

    // Parser options
    parser_options: json_mod.ParserOptions = .{},

    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
        };
    }

    pub fn process(self: *Self, source: []const u8) !TransformResult {
        // Step 1: Parse to AST using streaming parser
        var ast = try json_mod.parse(self.allocator, source);
        errdefer ast.deinit();

        // Step 2: Extract facts from AST if requested
        const ast_facts = if (self.extract_ast_facts)
            try self.extractAstFacts(ast)
        else
            null;

        return TransformResult{
            .tokens = &[_]StreamToken{}, // Not used in streaming architecture
            .token_facts = null, // Not used in streaming architecture
            .ast = ast,
            .ast_facts = ast_facts,
            .source = source,
        };
    }

    fn extractTokenFacts(self: *Self, tokens: []StreamToken, source: []const u8) ![]Fact {
        // Token-based fact extraction not used in streaming architecture
        _ = self;
        _ = tokens;
        _ = source;
        return &[_]Fact{};
    }

    fn extractAstFacts(self: *Self, ast: AST) ![]Fact {
        var facts = std.ArrayList(Fact).init(self.allocator);

        // Walk AST and extract semantic facts
        const full_span = Span.init(0, @intCast(ast.source.len));
        try self.walkNode(ast.root, &facts, full_span);

        return facts.toOwnedSlice();
    }

    fn walkNode(self: *Self, node: *Node, facts: *std.ArrayList(Fact), parent_span: Span) !void {
        switch (node.*) {
            .object => |obj| {
                // Create fact for object
                try facts.append(Fact.simple(
                    @intCast(facts.items.len),
                    packSpan(parent_span),
                    .starts_block,
                ));

                // Walk properties
                for (obj.properties) |*prop| {
                    if (prop.* == .property) {
                        const prop_span = prop.property.span;
                        try self.walkNode(prop.property.value, facts, prop_span);
                    }
                }
            },
            .array => |arr| {
                // Create fact for array
                try facts.append(Fact.simple(
                    @intCast(facts.items.len),
                    packSpan(parent_span),
                    .starts_block,
                ));

                // Walk elements
                for (arr.elements) |*elem| {
                    const elem_span = elem.span();
                    try self.walkNode(elem, facts, elem_span);
                }
            },
            .string => |str| {
                try facts.append(Fact.certain(
                    @intCast(facts.items.len),
                    packSpan(parent_span),
                    .is_string,
                    Value{ .span = packSpan(str.span) },
                ));
            },
            .number => |num| {
                try facts.append(Fact.certain(
                    @intCast(facts.items.len),
                    packSpan(parent_span),
                    .is_number,
                    Value{ .span = packSpan(num.span) },
                ));
            },
            .boolean => {
                try facts.append(Fact.simple(
                    @intCast(facts.items.len),
                    packSpan(parent_span),
                    .is_keyword, // boolean literals
                ));
            },
            .null => {
                try facts.append(Fact.simple(
                    @intCast(facts.items.len),
                    packSpan(parent_span),
                    .is_keyword, // null literal
                ));
            },
            .property, .root, .err => {
                // These are structural nodes, handled by walking logic
            },
        }
    }
};

/// Convenience functions for common use cases
pub const transform = struct {
    /// Parse only - AST without facts
    pub fn parseOnly(allocator: std.mem.Allocator, source: []const u8) !AST {
        return json_mod.parse(allocator, source);
    }

    /// Full pipeline: AST + facts
    pub fn full(allocator: std.mem.Allocator, source: []const u8) !TransformResult {
        var transformer = TransformOptions.init(allocator);
        transformer.extract_ast_facts = true;
        // No deinit needed for TransformOptions
        return transformer.process(source);
    }

    /// Parse and extract facts in one step
    pub fn parseWithFacts(allocator: std.mem.Allocator, source: []const u8) !struct { ast: AST, facts: []Fact } {
        const result = try full(allocator, source);
        return .{ .ast = result.ast.?, .facts = result.ast_facts orelse &[_]Fact{} };
    }
};

test "JSON transform - basic parsing" {
    const allocator = std.testing.allocator;
    const simple_json = "{\"key\": \"value\", \"number\": 42}";

    var ast = try transform.parseOnly(allocator, simple_json);
    defer ast.deinit();

    // Should have parsed successfully
    try std.testing.expect(ast.root.* == .object);
    try std.testing.expect(ast.root.object.properties.len == 2);
}

test "JSON transform - full pipeline with facts" {
    const allocator = std.testing.allocator;
    const simple_json = "{\"key\": \"value\"}";

    var result = try transform.full(allocator, simple_json);
    defer {
        if (result.ast) |*ast| ast.deinit();
        if (result.ast_facts) |facts| allocator.free(facts);
    }

    // Should have AST and facts
    try std.testing.expect(result.ast != null);
    try std.testing.expect(result.ast_facts != null);
    try std.testing.expect(result.ast_facts.?.len > 0);
}

test "JSON transform - parse with facts convenience" {
    const allocator = std.testing.allocator;
    const simple_json = "{\"test\": true}";

    const result = try transform.parseWithFacts(allocator, simple_json);
    defer {
        var ast_mut = result.ast;
        ast_mut.deinit();
        allocator.free(result.facts);
    }

    // Should have both AST and facts
    try std.testing.expect(result.ast.root.* == .object);
    try std.testing.expect(result.facts.len > 0);
}
