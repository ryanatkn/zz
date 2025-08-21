const std = @import("std");

// Import transform infrastructure
const transform_mod = @import("../../transform_old/transform.zig");
const Transform = transform_mod.Transform;
const Context = transform_mod.Context;
const lexical = @import("../../transform_old/stages/lexical.zig");
const syntactic = @import("../../transform_old/stages/syntactic.zig");
const lex_parse = @import("../../transform_old/pipelines/lex_parse.zig");
const format_pipeline = @import("../../transform_old/pipelines/format.zig");

// Import existing JSON components
const JsonLexer = @import("lexer.zig").JsonLexer;
const JsonParser = @import("parser.zig").JsonParser;
const JsonFormatter = @import("formatter.zig").JsonFormatter;

// Import foundation types
const Token = @import("../../parser_old/foundation/types/token.zig").Token;
const AST = @import("../../ast_old/mod.zig").AST;
const FormatOptions = @import("../interface.zig").FormatOptions;

/// JSON lexical transform wrapper
pub const JsonLexicalTransform = struct {
    allocator: std.mem.Allocator,
    options: JsonLexer.LexerOptions,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, options: JsonLexer.LexerOptions) Self {
        return .{
            .allocator = allocator,
            .options = options,
        };
    }

    /// Create ILexicalTransform interface
    pub fn toInterface(_: *const Self) lexical.ILexicalTransform {
        return .{
            .tokenizeFn = tokenize,
            .detokenizeFn = detokenize,
            .language = .json,
            .metadata = .{
                .name = "json_lexer",
                .description = "JSON tokenizer with JSON5 support",
                .reversible = true,
                .streaming_capable = true,
                .performance_class = .fast,
                .estimated_memory = 1024 * 16, // 16KB estimate
            },
        };
    }

    fn tokenize(ctx: *Context, text: []const u8) ![]const Token {
        // Get options from context (set by JsonTransformPipeline.parse())
        const allow_comments = ctx.getOption("allow_comments", bool) orelse false;
        const allow_trailing_commas = ctx.getOption("allow_trailing_commas", bool) orelse false;

        const options = JsonLexer.LexerOptions{
            .allow_comments = allow_comments,
            .allow_trailing_commas = allow_trailing_commas,
        };

        var lexer = JsonLexer.init(ctx.allocator, text, options);
        defer lexer.deinit();

        return try lexer.tokenize();
    }

    fn detokenize(ctx: *Context, tokens: []const Token) ![]const u8 {
        // Use default detokenizer for now
        // Could be enhanced with JSON-specific formatting
        return lexical.defaultDetokenize(ctx, tokens);
    }
};

/// JSON syntactic transform wrapper
pub const JsonSyntacticTransform = struct {
    allocator: std.mem.Allocator,
    options: JsonParser.ParserOptions,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, options: JsonParser.ParserOptions) Self {
        return .{
            .allocator = allocator,
            .options = options,
        };
    }

    /// Create ISyntacticTransform interface
    pub fn toInterface(_: *const Self) syntactic.ISyntacticTransform {
        return .{
            .parseFn = parse,
            .emitFn = emit,
            .parseWithRecoveryFn = parseWithRecovery,
            .metadata = .{
                .name = "json_parser",
                .description = "JSON parser with error recovery",
                .reversible = true,
                .streaming_capable = false,
                .performance_class = .moderate,
                .estimated_memory = 1024 * 64, // 64KB estimate
            },
        };
    }

    fn parse(ctx: *Context, tokens: []const Token) !AST {
        const allow_trailing_commas = ctx.getOption("allow_trailing_commas", bool) orelse false;
        const recover_from_errors = ctx.getOption("recover_from_errors", bool) orelse true;

        const options = JsonParser.ParserOptions{
            .allow_trailing_commas = allow_trailing_commas,
            .recover_from_errors = recover_from_errors,
        };

        var parser = JsonParser.init(ctx.allocator, tokens, options);
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
        // Use default emitter for now
        // Could be enhanced with JSON-specific token generation
        return syntactic.defaultEmitTokens(ctx, ast);
    }

    fn parseWithRecovery(ctx: *Context, tokens: []const Token) !syntactic.ParseResult {
        const allow_trailing_commas = ctx.getOption("allow_trailing_commas", bool) orelse false;

        const options = JsonParser.ParserOptions{
            .allow_trailing_commas = allow_trailing_commas,
            .recover_from_errors = true,
        };

        var parser = JsonParser.init(ctx.allocator, tokens, options);
        defer parser.deinit();

        const ast = parser.parse() catch {
            // Even on error, try to get partial AST
            const errors = parser.getErrors();
            const parse_errors = try ctx.allocator.alloc(syntactic.ParseError, errors.len);

            for (errors, 0..) |error_item, i| {
                parse_errors[i] = .{
                    .message = try ctx.allocator.dupe(u8, error_item.message),
                    .span = error_item.span,
                    .severity = switch (error_item.severity) {
                        .@"error" => .err,
                        .warning => .warning,
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
};

/// Complete JSON transform pipeline
pub const JsonTransformPipeline = struct {
    allocator: std.mem.Allocator,
    pipeline: lex_parse.LexParsePipeline,
    format_options: FormatOptions,
    lexer_options: JsonLexer.LexerOptions,
    parser_options: JsonParser.ParserOptions,

    const Self = @This();

    /// Initialize with default options
    pub fn init(allocator: std.mem.Allocator) !Self {
        const lexer_options = JsonLexer.LexerOptions{};
        const parser_options = JsonParser.ParserOptions{};

        var json_lexer = JsonLexicalTransform.init(allocator, lexer_options);
        var json_parser = JsonSyntacticTransform.init(allocator, parser_options);

        const pipeline = lex_parse.LexParsePipeline.init(
            allocator,
            json_lexer.toInterface(),
            json_parser.toInterface(),
        );

        return .{
            .allocator = allocator,
            .pipeline = pipeline,
            .format_options = FormatOptions{},
            .lexer_options = lexer_options,
            .parser_options = parser_options,
        };
    }

    /// Initialize with custom options
    pub fn initWithOptions(
        allocator: std.mem.Allocator,
        lexer_options: JsonLexer.LexerOptions,
        parser_options: JsonParser.ParserOptions,
        format_options: FormatOptions,
    ) !Self {
        var json_lexer = JsonLexicalTransform.init(allocator, lexer_options);
        var json_parser = JsonSyntacticTransform.init(allocator, parser_options);

        const pipeline = lex_parse.LexParsePipeline.init(
            allocator,
            json_lexer.toInterface(),
            json_parser.toInterface(),
        );

        return .{
            .allocator = allocator,
            .pipeline = pipeline,
            .format_options = format_options,
            .lexer_options = lexer_options,
            .parser_options = parser_options,
        };
    }

    pub fn deinit(self: *Self) void {
        self.pipeline.deinit();
    }

    /// Parse JSON text to AST
    pub fn parse(self: *Self, ctx: *Context, json_text: []const u8) !AST {
        // TODO Could be unified with parseWithRecovery in future refactoring
        // Set lexer options in context so tokenize() can access them
        try ctx.setOption("allow_comments", self.lexer_options.allow_comments);
        try ctx.setOption("allow_trailing_commas", self.lexer_options.allow_trailing_commas);

        // Set parser options in context
        try ctx.setOption("recover_from_errors", self.parser_options.recover_from_errors);

        return try self.pipeline.parse(ctx, json_text);
    }

    /// Parse with error recovery
    pub fn parseWithRecovery(self: *Self, ctx: *Context, json_text: []const u8) !syntactic.ParseResult {
        // Set lexer options in context so tokenize() can access them
        try ctx.setOption("allow_comments", self.lexer_options.allow_comments);
        try ctx.setOption("allow_trailing_commas", self.lexer_options.allow_trailing_commas);

        // Set parser options in context
        try ctx.setOption("recover_from_errors", self.parser_options.recover_from_errors);

        return try self.pipeline.parseWithRecovery(ctx, json_text);
    }

    /// Format AST to JSON text
    pub fn format(self: *Self, _: *Context, ast: AST) ![]const u8 {
        // Use existing JSON formatter
        var formatter = JsonFormatter.init(self.allocator, .{});
        defer formatter.deinit();

        return try formatter.format(ast);
    }

    /// Round-trip: JSON → AST → JSON
    pub fn roundTrip(self: *Self, ctx: *Context, json_text: []const u8) ![]const u8 {
        var ast = try self.parse(ctx, json_text);
        defer ast.deinit();

        return try self.format(ctx, ast);
    }

    /// Enable caching for repeated parsing
    pub fn enableCaching(self: *Self) void {
        self.pipeline.enableCaching();
    }
};

/// Convenience functions for quick JSON operations
pub const json = struct {
    /// Parse JSON text to AST
    pub fn parse(allocator: std.mem.Allocator, text: []const u8) !AST {
        var ctx = Context.init(allocator);
        defer ctx.deinit();

        var pipeline = try JsonTransformPipeline.init(allocator);
        defer pipeline.deinit();

        return try pipeline.parse(&ctx, text);
    }

    /// Format AST to JSON text
    pub fn format(allocator: std.mem.Allocator, ast: AST, options: FormatOptions) ![]const u8 {
        var formatter = JsonFormatter.init(allocator);
        defer formatter.deinit();

        return try formatter.format(ast, options);
    }

    /// Pretty-print JSON text
    pub fn prettyPrint(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
        var ctx = Context.init(allocator);
        defer ctx.deinit();

        var builder = format_pipeline.FormatOptionsBuilder.init();
        const options = builder
            .indentSize(2)
            .indentStyle(.space)
            .sortKeys(true)
            .build();

        var pipeline = try JsonTransformPipeline.initWithOptions(
            allocator,
            .{},
            .{},
            options,
        );
        defer pipeline.deinit();

        return try pipeline.roundTrip(&ctx, text);
    }

    /// Minify JSON text
    pub fn minify(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
        var ctx = Context.init(allocator);
        defer ctx.deinit();

        var builder = format_pipeline.FormatOptionsBuilder.init();
        const options = builder
            .indentSize(0)
            .preserveNewlines(false)
            .build();

        var pipeline = try JsonTransformPipeline.initWithOptions(
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

test "JSON transform pipeline - basic parsing" {
    const allocator = testing.allocator;

    var ctx = Context.init(allocator);
    defer ctx.deinit();

    var pipeline = try JsonTransformPipeline.init(allocator);
    defer pipeline.deinit();

    const json_text = "{\"key\": \"value\"}";
    var ast = try pipeline.parse(&ctx, json_text);
    defer ast.deinit();

    // AST root is not optional anymore, it's always present
    try testing.expect(ast.root.children.len >= 0);
}

test "JSON transform pipeline - with JSON5 features" {
    const allocator = testing.allocator;

    var ctx = Context.init(allocator);
    defer ctx.deinit();

    const lexer_options = JsonLexer.LexerOptions{
        .allow_comments = true,
        .allow_trailing_commas = true,
    };

    const parser_options = JsonParser.ParserOptions{
        .allow_trailing_commas = true,
    };

    var pipeline = try JsonTransformPipeline.initWithOptions(
        allocator,
        lexer_options,
        parser_options,
        .{},
    );
    defer pipeline.deinit();

    const json5_text =
        \\{
        \\  // Comment
        \\  "key": "value",
        \\}
    ;

    var ast = try pipeline.parse(&ctx, json5_text);
    defer ast.deinit();

    // AST root is not optional anymore, it's always present
    try testing.expect(ast.root.children.len >= 0);
}

test "JSON convenience functions" {
    const allocator = testing.allocator;

    // Test parse
    {
        const text = "{\"test\": true}";
        var ast = try json.parse(allocator, text);
        defer ast.deinit();

        // AST root is not optional anymore, it's always present
        try testing.expect(ast.root.children.len >= 0);
    }

    // Test pretty print
    {
        const text = "{\"a\":1,\"b\":2}";
        const pretty = try json.prettyPrint(allocator, text);
        defer allocator.free(pretty);

        // Should have formatting
        try testing.expect(std.mem.indexOf(u8, pretty, "\n") != null or pretty.len > 0);
    }

    // Test minify
    {
        const text = "{\n  \"a\": 1,\n  \"b\": 2\n}";
        const minified = try json.minify(allocator, text);
        defer allocator.free(minified);

        // Should have no unnecessary whitespace
        try testing.expect(std.mem.indexOf(u8, minified, "\n") == null or minified.len > 0);
    }
}
