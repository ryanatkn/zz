const std = @import("std");

// TODO: Transform functionality disabled - needs update for streaming architecture
// The old transform system used batch tokenization which no longer exists.
// This stub prevents compilation errors until transform is rewritten for streaming.

// Import ZON-specific types
const zon_mod = @import("mod.zig");
const StreamToken = @import("../../token/mod.zig").StreamToken;
const AST = @import("ast.zig").AST;
const Node = @import("ast.zig").Node;

// Import fact system (optional)
const Fact = @import("../../fact/mod.zig").Fact;
const FactStore = @import("../../fact/mod.zig").FactStore;
const Span = @import("../../span/mod.zig").Span;
const packSpan = @import("../../span/mod.zig").packSpan;

/// Transform result containing optional stages - DISABLED
pub const TransformResult = struct {
    /// Always present: tokenized input
    tokens: []StreamToken,
    /// Optional: facts extracted from tokens
    token_facts: ?[]Fact = null,
    /// Optional: parsed AST
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

/// Transform options - controls what stages to execute - DISABLED
pub const ZonTransform = struct {
    extract_token_facts: bool = false,
    build_ast: bool = true,
    extract_ast_facts: bool = false,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
        };
    }

    // TODO: All transform functionality disabled - needs rewrite for streaming
    pub fn process(self: *Self, source: []const u8) !TransformResult {
        _ = self;
        _ = source;
        return error.NotImplemented; // Transform not implemented for streaming
    }

    fn extractTokenFacts(self: *Self, tokens: []StreamToken, source: []const u8) ![]Fact {
        _ = self;
        _ = tokens;
        _ = source;
        return error.NotImplemented;
    }

    fn extractAstFacts(self: *Self, ast: AST) ![]Fact {
        _ = self;
        _ = ast;
        return error.NotImplemented;
    }
};

/// Convenience functions for common use cases - DISABLED
pub const transform = struct {
    /// Just tokenize - no AST, no facts - DISABLED
    pub fn tokenizeOnly(allocator: std.mem.Allocator, source: []const u8) ![]StreamToken {
        _ = allocator;
        _ = source;
        return error.NotImplemented; // Tokenize not implemented for streaming
    }

    /// Full pipeline: tokens + AST - DISABLED
    pub fn full(allocator: std.mem.Allocator, source: []const u8) !TransformResult {
        _ = allocator;
        _ = source;
        return error.NotImplemented; // Full transform not implemented for streaming
    }
};

// TODO: Transform tests disabled - need rewrite for streaming
test "ZON transform - disabled" {
    return error.SkipZigTest;
    // TODO: Rewrite transform tests for streaming architecture
}
