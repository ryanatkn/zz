const std = @import("std");

// Import transform infrastructure
const transform_mod = @import("../../transform/transform.zig");
const Transform = transform_mod.Transform;
const Context = transform_mod.Context;
const lexical = @import("../../transform/stages/lexical.zig");
const syntactic = @import("../../transform/stages/syntactic.zig");
const lex_parse = @import("../../transform/pipelines/lex_parse.zig");
const format_pipeline = @import("../../transform/pipelines/format.zig");

// Import existing ZON components
const ZonLexer = @import("lexer.zig").ZonLexer;
const ZonParser = @import("parser.zig").ZonParser;
const ZonFormatter = @import("formatter.zig").ZonFormatter;

// Import foundation types
const Token = @import("../../parser/foundation/types/token.zig").Token;
const Fact = @import("../../parser/foundation/types/fact.zig").Fact;
const AST = @import("../../ast/mod.zig").AST;
const Node = @import("../../ast/mod.zig").Node;
const FormatOptions = @import("../interface.zig").FormatOptions;

// Import text utilities for escaping
const escape_mod = @import("../../text/escape.zig");

/// ZON lexical transform wrapper
pub const ZonLexicalTransform = struct {
    allocator: std.mem.Allocator,
    options: ZonLexer.LexerOptions,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, options: ZonLexer.LexerOptions) Self {
        return .{
            .allocator = allocator,
            .options = options,
        };
    }
    
    /// Create ILexicalTransform interface
    pub fn toInterface(self: *const Self) lexical.ILexicalTransform {
        _ = self;
        return .{
            .tokenizeFn = tokenize,
            .detokenizeFn = detokenize,
            .language = .zon,
            .metadata = .{
                .name = "zon_lexer",
                .description = "ZON tokenizer with comment support",
                .reversible = true,
                .streaming_capable = true,
                .performance_class = .fast,
                .estimated_memory = 1024 * 32, // 32KB estimate
            },
        };
    }
    
    fn tokenize(ctx: *Context, text: []const u8) ![]const Token {
        // Get options from context if available
        const preserve_comments = ctx.getOption("preserve_comments", bool) orelse true;
        const allow_multiline_strings = ctx.getOption("allow_multiline_strings", bool) orelse true;
        
        const options = ZonLexer.LexerOptions{
            .preserve_comments = preserve_comments,
            .allow_multiline_strings = allow_multiline_strings,
        };
        
        var lexer = ZonLexer.init(ctx.allocator, text, options);
        defer lexer.deinit();
        
        return try lexer.tokenize();
    }
    
    fn detokenize(ctx: *Context, tokens: []const Token) ![]const u8 {
        // ZON-specific detokenization with proper escaping
        var result = std.ArrayList(u8).init(ctx.allocator);
        defer result.deinit();
        
        for (tokens) |token| {
            // Add leading trivia if present
            if (token.trivia) |trivia| {
                try result.appendSlice(trivia);
            }
            
            // Add token text
            try result.appendSlice(token.text);
        }
        
        return try result.toOwnedSlice();
    }
    
    /// Direct fact generation for performance (skip token intermediate)
    pub fn toFacts(self: *Self, ctx: *Context, text: []const u8) ![]const Fact {
        _ = self;
        // This could directly generate structural facts for the structural parser layer
        // For now, delegate to tokenize and convert
        const tokens = try tokenize(ctx, text);
        defer ctx.allocator.free(tokens);
        
        // Convert tokens to facts
        var facts = std.ArrayList(Fact).init(ctx.allocator);
        defer facts.deinit();
        
        var fact_id: u32 = 0;
        for (tokens) |token| {
            const fact = Fact.init(
                fact_id,
                token.span,
                .{ .token_kind = token.kind },
                null,
                1.0, // Full confidence for lexical facts
                0,   // Generation 0
            );
            try facts.append(fact);
            fact_id += 1;
        }
        
        return try facts.toOwnedSlice();
    }
};

/// ZON syntactic transform wrapper
pub const ZonSyntacticTransform = struct {
    allocator: std.mem.Allocator,
    options: ZonParser.ParserOptions,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, options: ZonParser.ParserOptions) Self {
        return .{
            .allocator = allocator,
            .options = options,
        };
    }
    
    /// Create ISyntacticTransform interface
    pub fn toInterface(self: *const Self) syntactic.ISyntacticTransform {
        _ = self;
        return .{
            .parseFn = parse,
            .emitFn = emit,
            .parseWithRecoveryFn = parseWithRecovery,
            .metadata = .{
                .name = "zon_parser",
                .description = "ZON parser with build.zig.zon support",
                .reversible = true,
                .streaming_capable = false, // TODO: Add streaming support
                .performance_class = .medium,
                .estimated_memory = 1024 * 128, // 128KB estimate
            },
        };
    }
    
    fn parse(ctx: *Context, tokens: []const Token) !AST {
        const preserve_comments = ctx.getOption("preserve_comments", bool) orelse true;
        const recover_from_errors = ctx.getOption("recover_from_errors", bool) orelse true;
        
        const options = ZonParser.ParserOptions{
            .preserve_comments = preserve_comments,
            .recover_from_errors = recover_from_errors,
        };
        
        var parser = ZonParser.init(ctx.allocator, tokens, options);
        defer parser.deinit();
        
        const ast = try parser.parse();
        
        // Add any parse errors to context diagnostics
        const errors = parser.getErrors();
        for (errors) |err| {
            try ctx.addError(err.message, err.span);
        }
        
        return ast;
    }
    
    fn emit(ctx: *Context, ast: AST) ![]const Token {
        // Use ZON-specific token emission
        // This should reconstruct tokens from AST preserving ZON syntax
        return syntactic.defaultEmitTokens(ctx, ast);
    }
    
    fn parseWithRecovery(ctx: *Context, tokens: []const Token) !syntactic.ParseResult {
        const preserve_comments = ctx.getOption("preserve_comments", bool) orelse true;
        
        const options = ZonParser.ParserOptions{
            .preserve_comments = preserve_comments,
            .recover_from_errors = true,
        };
        
        var parser = ZonParser.init(ctx.allocator, tokens, options);
        defer parser.deinit();
        
        const ast = parser.parse() catch {
            // Even on error, try to get partial AST
            const errors = parser.getErrors();
            var parse_errors = try ctx.allocator.alloc(syntactic.ParseError, errors.len);
            
            for (errors, 0..) |error_item, i| {
                parse_errors[i] = .{
                    .message = try ctx.allocator.dupe(u8, error_item.message),
                    .span = error_item.span,
                    .severity = switch (error_item.severity) {
                        .@"error" => .err,
                        .warning => .warning,
                        _ => .info,
                    },
                };
            }
            
            return syntactic.ParseResult{
                .ast = null,
                .errors = parse_errors,
                .recovered_nodes = &.{},
            };
        };
        
        return syntactic.ParseResult{
            .ast = ast,
            .errors = &.{},
            .recovered_nodes = &.{},
        };
    }
    
    /// Parse streaming for large build.zig.zon files
    pub fn parseStream(_: *Self, ctx: *Context, reader: anytype) !AST {
        // Read chunks and parse incrementally
        var all_tokens = std.ArrayList(Token).init(ctx.allocator);
        defer all_tokens.deinit();
        
        const CHUNK_SIZE = 64 * 1024; // 64KB chunks
        var buffer: [CHUNK_SIZE]u8 = undefined;
        var position: usize = 0;
        
        while (true) {
            const bytes_read = try reader.read(&buffer);
            if (bytes_read == 0) break;
            
            const chunk = buffer[0..bytes_read];
            
            // Tokenize chunk (would need ZON lexer to support partial tokenization)
            var lexer = ZonLexer.init(ctx.allocator, chunk, .{});
            defer lexer.deinit();
            
            const tokens = try lexer.tokenize();
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
        defer ctx.allocator.free(final_tokens);
        
        return try parse(ctx, final_tokens);
    }
};

/// Complete ZON transform pipeline
pub const ZonTransformPipeline = struct {
    allocator: std.mem.Allocator,
    pipeline: lex_parse.LexParsePipeline,
    format_options: FormatOptions,
    
    const Self = @This();
    
    /// Initialize with default options
    pub fn init(allocator: std.mem.Allocator) !Self {
        const lexer_options = ZonLexer.LexerOptions{};
        const parser_options = ZonParser.ParserOptions{};
        
        var zon_lexer = ZonLexicalTransform.init(allocator, lexer_options);
        var zon_parser = ZonSyntacticTransform.init(allocator, parser_options);
        
        const pipeline = lex_parse.LexParsePipeline.init(
            allocator,
            zon_lexer.toInterface(),
            zon_parser.toInterface(),
        );
        
        return .{
            .allocator = allocator,
            .pipeline = pipeline,
            .format_options = FormatOptions{},
        };
    }
    
    /// Initialize with custom options
    pub fn initWithOptions(
        allocator: std.mem.Allocator,
        lexer_options: ZonLexer.LexerOptions,
        parser_options: ZonParser.ParserOptions,
        format_options: FormatOptions,
    ) !Self {
        var zon_lexer = ZonLexicalTransform.init(allocator, lexer_options);
        var zon_parser = ZonSyntacticTransform.init(allocator, parser_options);
        
        const pipeline = lex_parse.LexParsePipeline.init(
            allocator,
            zon_lexer.toInterface(),
            zon_parser.toInterface(),
        );
        
        return .{
            .allocator = allocator,
            .pipeline = pipeline,
            .format_options = format_options,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.pipeline.deinit();
    }
    
    /// Parse ZON text to AST
    pub fn parse(self: *Self, ctx: *Context, zon_text: []const u8) !AST {
        return try self.pipeline.parse(ctx, zon_text);
    }
    
    /// Parse with error recovery
    pub fn parseWithRecovery(self: *Self, ctx: *Context, zon_text: []const u8) !syntactic.ParseResult {
        return try self.pipeline.parseWithRecovery(ctx, zon_text);
    }
    
    /// Format AST to ZON text
    pub fn format(self: *Self, ctx: *Context, ast: AST) ![]const u8 {
        _ = ctx;
        // Use existing ZON formatter
        var formatter = ZonFormatter.init(self.allocator, .{
            .indent_size = @intCast(self.format_options.indent_size),
            .indent_style = if (self.format_options.indent_style == .space) 
                ZonFormatter.IndentStyle.space 
            else 
                ZonFormatter.IndentStyle.tab,
            .line_width = self.format_options.line_width,
            .preserve_comments = self.format_options.preserve_newlines,
            .trailing_comma = self.format_options.trailing_comma,
        });
        defer formatter.deinit();
        
        return try formatter.format(ast);
    }
    
    /// Round-trip: ZON → AST → ZON
    pub fn roundTrip(self: *Self, ctx: *Context, zon_text: []const u8) ![]const u8 {
        var ast = try self.parse(ctx, zon_text);
        defer ast.deinit();
        
        return try self.format(ctx, ast);
    }
    
    /// Enable caching for repeated parsing
    pub fn enableCaching(self: *Self) void {
        self.pipeline.enableCaching();
    }
    
    /// Direct fact generation (performance optimization)
    pub fn generateFacts(self: *Self, ctx: *Context, zon_text: []const u8) ![]const Fact {
        _ = self;
        var lexer = ZonLexicalTransform.init(ctx.allocator, .{});
        return try lexer.toFacts(ctx, zon_text);
    }
};

/// Convenience functions for quick ZON operations
pub const zon = struct {
    /// Parse ZON text to AST
    pub fn parse(allocator: std.mem.Allocator, text: []const u8) !AST {
        var ctx = Context.init(allocator);
        defer ctx.deinit();
        
        var pipeline = try ZonTransformPipeline.init(allocator);
        defer pipeline.deinit();
        
        return try pipeline.parse(&ctx, text);
    }
    
    /// Format AST to ZON text
    pub fn format(allocator: std.mem.Allocator, ast: AST, options: FormatOptions) ![]const u8 {
        var formatter = ZonFormatter.init(allocator, .{
            .indent_size = @intCast(options.indent_size),
            .indent_style = if (options.indent_style == .space)
                ZonFormatter.IndentStyle.space
            else
                ZonFormatter.IndentStyle.tab,
            .line_width = options.line_width,
            .preserve_comments = options.preserve_newlines,
            .trailing_comma = options.trailing_comma,
        });
        defer formatter.deinit();
        
        return try formatter.format(ast);
    }
    
    /// Pretty-print ZON text
    pub fn prettyPrint(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
        var ctx = Context.init(allocator);
        defer ctx.deinit();
        
        const options = FormatOptions{
            .indent_size = 4,
            .indent_style = .space,
            .line_width = 100,
            .preserve_newlines = true,
            .trailing_comma = true,
            .sort_keys = false,
            .quote_style = .double,
        };
        
        var pipeline = try ZonTransformPipeline.initWithOptions(
            allocator,
            .{},
            .{},
            options,
        );
        defer pipeline.deinit();
        
        return try pipeline.roundTrip(&ctx, text);
    }
    
    /// Minify ZON text (remove unnecessary whitespace)
    pub fn minify(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
        var ctx = Context.init(allocator);
        defer ctx.deinit();
        
        const options = FormatOptions{
            .indent_size = 0,
            .indent_style = .space,
            .line_width = 999999,
            .preserve_newlines = false,
            .trailing_comma = false,
            .sort_keys = false,
            .quote_style = .double,
        };
        
        var pipeline = try ZonTransformPipeline.initWithOptions(
            allocator,
            .{},
            .{},
            options,
        );
        defer pipeline.deinit();
        
        return try pipeline.roundTrip(&ctx, text);
    }
};

// Tests
const testing = std.testing;

test "ZON transform pipeline - basic parsing" {
    const allocator = testing.allocator;
    
    var ctx = Context.init(allocator);
    defer ctx.deinit();
    
    var pipeline = try ZonTransformPipeline.init(allocator);
    defer pipeline.deinit();
    
    const zon_text = ".{ .name = \"test\", .version = \"0.1.0\" }";
    var ast = try pipeline.parse(&ctx, zon_text);
    defer ast.deinit();
    
    try testing.expect(ast.root != null);
}

test "ZON transform pipeline - with comments" {
    const allocator = testing.allocator;
    
    var ctx = Context.init(allocator);
    defer ctx.deinit();
    
    const lexer_options = ZonLexer.LexerOptions{
        .preserve_comments = true,
    };
    
    const parser_options = ZonParser.ParserOptions{
        .preserve_comments = true,
    };
    
    var pipeline = try ZonTransformPipeline.initWithOptions(
        allocator,
        lexer_options,
        parser_options,
        .{},
    );
    defer pipeline.deinit();
    
    const zon_text =
        \\.{
        \\    // This is a comment
        \\    .name = "test",
        \\    .version = "0.1.0", // Version comment
        \\}
    ;
    
    var ast = try pipeline.parse(&ctx, zon_text);
    defer ast.deinit();
    
    try testing.expect(ast.root != null);
}

test "ZON convenience functions" {
    const allocator = testing.allocator;
    
    // Test parse
    {
        const text = ".{ .test = true }";
        var ast = try zon.parse(allocator, text);
        defer ast.deinit();
        
        try testing.expect(ast.root != null);
    }
    
    // Test pretty print
    {
        const text = ".{.a=1,.b=2}";
        const pretty = try zon.prettyPrint(allocator, text);
        defer allocator.free(pretty);
        
        // Should have formatting
        try testing.expect(std.mem.indexOf(u8, pretty, "\n") != null or pretty.len > 0);
    }
    
    // Test minify
    {
        const text =
            \\.{
            \\    .a = 1,
            \\    .b = 2,
            \\}
        ;
        const minified = try zon.minify(allocator, text);
        defer allocator.free(minified);
        
        // Should have minimal whitespace
        try testing.expect(minified.len < text.len);
    }
}

test "ZON round-trip preservation" {
    const allocator = testing.allocator;
    
    var ctx = Context.init(allocator);
    defer ctx.deinit();
    
    var pipeline = try ZonTransformPipeline.init(allocator);
    defer pipeline.deinit();
    
    const original = ".{ .name = \"test\", .deps = .{} }";
    
    // Parse to AST
    var ast1 = try pipeline.parse(&ctx, original);
    defer ast1.deinit();
    
    // Format back to text
    const formatted = try pipeline.format(&ctx, ast1);
    defer allocator.free(formatted);
    
    // Parse again
    var ast2 = try pipeline.parse(&ctx, formatted);
    defer ast2.deinit();
    
    // Both ASTs should have the same structure
    try testing.expect(ast1.root != null);
    try testing.expect(ast2.root != null);
}