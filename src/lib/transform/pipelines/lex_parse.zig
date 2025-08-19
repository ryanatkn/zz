const std = @import("std");
const transform_mod = @import("../transform.zig");
const Transform = transform_mod.Transform;
const Context = transform_mod.Context;
const types = @import("../types.zig");

// Import stage interfaces
const lexical = @import("../stages/lexical.zig");
const syntactic = @import("../stages/syntactic.zig");

// Import foundation types
const Token = @import("../../parser/foundation/types/token.zig").Token;
const AST = @import("../../ast/mod.zig").AST;

/// LexParsePipeline: Specialized pipeline for Text → Tokens → AST
/// Avoids type erasure by using concrete types throughout
pub const LexParsePipeline = struct {
    allocator: std.mem.Allocator,
    lexer: lexical.ILexicalTransform,
    parser: syntactic.ISyntacticTransform,
    
    // Optional caching
    cache_tokens: bool = false,
    cached_tokens: ?[]const Token = null,
    cached_source: ?[]const u8 = null,
    
    const Self = @This();
    
    /// Initialize pipeline with lexer and parser
    pub fn init(
        allocator: std.mem.Allocator,
        lexer: lexical.ILexicalTransform,
        parser: syntactic.ISyntacticTransform,
    ) Self {
        return .{
            .allocator = allocator,
            .lexer = lexer,
            .parser = parser,
        };
    }
    
    /// Enable token caching for repeated parsing
    pub fn enableCaching(self: *Self) void {
        self.cache_tokens = true;
    }
    
    pub fn deinit(self: *Self) void {
        if (self.cached_tokens) |tokens| {
            self.allocator.free(tokens);
        }
        if (self.cached_source) |source| {
            self.allocator.free(source);
        }
    }
    
    /// Execute the full pipeline: Text → Tokens → AST
    pub fn parse(self: *Self, ctx: *Context, source: []const u8) !AST {
        // Check cache
        if (self.cache_tokens and self.cached_source != null) {
            if (std.mem.eql(u8, self.cached_source.?, source)) {
                // Use cached tokens
                if (self.cached_tokens) |tokens| {
                    return try self.parser.parseFn(ctx, tokens);
                }
            }
        }
        
        // Tokenize
        ctx.startTiming();
        const tokens = try self.lexer.tokenizeFn(ctx, source);
        defer if (!self.cache_tokens) ctx.allocator.free(tokens);
        
        if (ctx.getOption("debug", bool) orelse false) {
            const tokenize_time = ctx.getElapsedMs() orelse 0;
            std.debug.print("Tokenization took {}ms\n", .{tokenize_time});
        }
        
        // Cache tokens if enabled
        if (self.cache_tokens) {
            if (self.cached_tokens) |old_tokens| {
                self.allocator.free(old_tokens);
            }
            if (self.cached_source) |old_source| {
                self.allocator.free(old_source);
            }
            self.cached_tokens = tokens;
            self.cached_source = try self.allocator.dupe(u8, source);
        }
        
        // Parse
        ctx.startTiming();
        const ast = try self.parser.parseFn(ctx, tokens);
        
        if (ctx.getOption("debug", bool) orelse false) {
            const parse_time = ctx.getElapsedMs() orelse 0;
            std.debug.print("Parsing took {}ms\n", .{parse_time});
        }
        
        return ast;
    }
    
    /// Execute with error recovery
    pub fn parseWithRecovery(self: *Self, ctx: *Context, source: []const u8) !syntactic.ParseResult {
        // Tokenize
        const tokens = try self.lexer.tokenizeFn(ctx, source);
        defer ctx.allocator.free(tokens);
        
        // Parse with recovery if available
        if (self.parser.parseWithRecoveryFn) |parse_recovery| {
            return try parse_recovery(ctx, tokens);
        }
        
        // Fallback to regular parsing
        const ast = try self.parser.parseFn(ctx, tokens);
        return syntactic.ParseResult{
            .ast = ast,
            .errors = &.{},
            .recovered_nodes = &.{},
        };
    }
    
    /// Reverse operation: AST → Tokens → Text
    pub fn emit(self: *Self, ctx: *Context, ast: AST) ![]const u8 {
        // Check if transforms are reversible
        if (self.parser.emitFn == null or self.lexer.detokenizeFn == null) {
            return error.NotReversible;
        }
        
        // Emit tokens from AST
        const tokens = try self.parser.emitFn.?(ctx, ast);
        defer ctx.allocator.free(tokens);
        
        // Detokenize to text
        return try self.lexer.detokenizeFn.?(ctx, tokens);
    }
    
    /// Create a transform that represents this pipeline
    pub fn toTransform(_: *Self) Transform([]const u8, AST) {
        const forward_fn = struct {
            fn forward(ctx: *Context, input: []const u8) !AST {
                // This would need proper implementation
                _ = ctx;
                _ = input;
                return error.NotImplemented;
            }
        }.forward;
        
        const reverse_fn = null; // Would need access to self to check reversibility
        
        return transform_mod.createTransform(
            []const u8,
            AST,
            forward_fn,
            reverse_fn,
            .{
                .name = "lex_parse_pipeline",
                .description = "Combined lexer and parser pipeline",
                .reversible = (reverse_fn != null),
                .streaming_capable = false,
                .performance_class = .medium,
            },
        );
    }
};

/// Streaming lex-parse pipeline for large files
pub const StreamingLexParsePipeline = struct {
    allocator: std.mem.Allocator,
    lexer: lexical.ILexicalTransform,
    parser: syntactic.ISyntacticTransform,
    incremental_parser: ?syntactic.IncrementalParser = null,
    
    const Self = @This();
    const CHUNK_SIZE = 64 * 1024; // 64KB chunks
    
    pub fn init(
        allocator: std.mem.Allocator,
        lexer: lexical.ILexicalTransform,
        parser: syntactic.ISyntacticTransform,
    ) Self {
        return .{
            .allocator = allocator,
            .lexer = lexer,
            .parser = parser,
        };
    }
    
    pub fn deinit(self: *Self) void {
        if (self.incremental_parser) |*inc| {
            inc.deinit();
        }
    }
    
    /// Process a stream of text
    pub fn processStream(self: *Self, ctx: *Context, reader: anytype) !AST {
        var all_tokens = std.ArrayList(Token).init(self.allocator);
        defer all_tokens.deinit();
        
        var buffer: [CHUNK_SIZE]u8 = undefined;
        var position: usize = 0;
        
        while (true) {
            const bytes_read = try reader.read(&buffer);
            if (bytes_read == 0) break;
            
            const chunk = buffer[0..bytes_read];
            
            // Tokenize chunk
            const tokens = try self.lexer.tokenizeFn(ctx, chunk);
            defer ctx.allocator.free(tokens);
            
            // Adjust token positions
            for (tokens) |token| {
                var adjusted = token;
                adjusted.span.start += position;
                adjusted.span.end += position;
                try all_tokens.append(adjusted);
            }
            
            position += bytes_read;
            
            // Update progress if available
            if (ctx.progress) |progress| {
                progress.bytes_processed = position;
            }
        }
        
        // Parse all tokens
        const final_tokens = try all_tokens.toOwnedSlice();
        defer self.allocator.free(final_tokens);
        
        return try self.parser.parseFn(ctx, final_tokens);
    }
    
    /// Process incrementally with updates
    pub fn processIncremental(self: *Self, ctx: *Context, chunk: []const u8) !void {
        if (self.incremental_parser == null) {
            self.incremental_parser = syntactic.IncrementalParser.init(ctx, self.parser);
        }
        
        // Tokenize chunk
        const tokens = try self.lexer.tokenizeFn(ctx, chunk);
        defer ctx.allocator.free(tokens);
        
        // Update incremental parser
        try self.incremental_parser.?.update(tokens);
    }
    
    /// Get current AST from incremental processing
    pub fn getCurrentAST(self: Self) ?AST {
        if (self.incremental_parser) |inc| {
            return inc.getAST();
        }
        return null;
    }
};

/// Builder for creating pipelines fluently
pub const PipelineBuilder = struct {
    allocator: std.mem.Allocator,
    lexer: ?lexical.ILexicalTransform = null,
    parser: ?syntactic.ISyntacticTransform = null,
    enable_caching: bool = false,
    enable_streaming: bool = false,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }
    
    pub fn withLexer(self: *Self, lexer: lexical.ILexicalTransform) *Self {
        self.lexer = lexer;
        return self;
    }
    
    pub fn withParser(self: *Self, parser: syntactic.ISyntacticTransform) *Self {
        self.parser = parser;
        return self;
    }
    
    pub fn withCaching(self: *Self) *Self {
        self.enable_caching = true;
        return self;
    }
    
    pub fn withStreaming(self: *Self) *Self {
        self.enable_streaming = true;
        return self;
    }
    
    pub fn build(self: Self) !*LexParsePipeline {
        if (self.lexer == null or self.parser == null) {
            return error.IncompletePipeline;
        }
        
        var pipeline = try self.allocator.create(LexParsePipeline);
        pipeline.* = LexParsePipeline.init(
            self.allocator,
            self.lexer.?,
            self.parser.?,
        );
        
        if (self.enable_caching) {
            pipeline.enableCaching();
        }
        
        return pipeline;
    }
    
    pub fn buildStreaming(self: Self) !*StreamingLexParsePipeline {
        if (self.lexer == null or self.parser == null) {
            return error.IncompletePipeline;
        }
        
        const pipeline = try self.allocator.create(StreamingLexParsePipeline);
        pipeline.* = StreamingLexParsePipeline.init(
            self.allocator,
            self.lexer.?,
            self.parser.?,
        );
        
        return pipeline;
    }
};

// Tests
const testing = std.testing;
const builder = @import("../../ast/builder.zig");
const Span = @import("../../parser/foundation/types/span.zig").Span;

test "LexParsePipeline basic usage" {
    const allocator = testing.allocator;
    
    var ctx = Context.init(allocator);
    defer ctx.deinit();
    
    // Create mock lexer
    const mock_lexer = lexical.ILexicalTransform{
        .tokenizeFn = struct {
            fn tokenize(context: *Context, text: []const u8) ![]const Token {
                _ = text;
                var tokens = try context.allocator.alloc(Token, 1);
                tokens[0] = Token.simple(Span.init(0, 4), .null_literal, "null", 0);
                return tokens;
            }
        }.tokenize,
        .detokenizeFn = null,
        .metadata = .{ .name = "mock_lexer", .description = "Test lexer" },
    };
    
    // Create mock parser
    const mock_parser = syntactic.ISyntacticTransform{
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
        .metadata = .{ .name = "mock_parser", .description = "Test parser" },
    };
    
    var pipeline = LexParsePipeline.init(allocator, mock_lexer, mock_parser);
    defer pipeline.deinit();
    
    var ast = try pipeline.parse(&ctx, "null");
    defer ast.deinit();
    
    // AST.root is no longer optional - just verify it exists
    try testing.expect(ast.root.rule_id == @intFromEnum(@import("../../ast/rules.zig").CommonRules.null_literal));
}

test "PipelineBuilder usage" {
    const allocator = testing.allocator;
    
    const mock_lexer = lexical.ILexicalTransform{
        .tokenizeFn = struct {
            fn tokenize(context: *Context, text: []const u8) ![]const Token {
                _ = text;
                return try context.allocator.alloc(Token, 0);
            }
        }.tokenize,
        .detokenizeFn = null,
        .metadata = .{ .name = "mock", .description = "Mock" },
    };
    
    const mock_parser = syntactic.ISyntacticTransform{
        .parseFn = struct {
            fn parse(context: *Context, tokens: []const Token) !AST {
                _ = tokens;
                return AST.init(context.allocator);
            }
        }.parse,
        .emitFn = null,
        .parseWithRecoveryFn = null,
        .metadata = .{ .name = "mock", .description = "Mock" },
    };
    
    var builder_inst = PipelineBuilder.init(allocator);
    const pipeline = try builder_inst
        .withLexer(mock_lexer)
        .withParser(mock_parser)
        .withCaching()
        .build();
    defer {
        pipeline.deinit();
        allocator.destroy(pipeline);
    }
    
    try testing.expect(pipeline.cache_tokens);
}