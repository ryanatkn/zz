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
const Node = @import("../../ast/mod.zig").Node;

// Import formatting utilities
const common_formatting = @import("../../languages/common/formatting.zig");
const indent_mod = @import("../../text/indent.zig");
const FormatOptions = @import("../../languages/interface.zig").FormatOptions;

/// FormatPipeline: Specialized pipeline for AST → Tokens → Text
/// Used for code formatting and pretty-printing
pub const FormatPipeline = struct {
    allocator: std.mem.Allocator,
    emitter: syntactic.ISyntacticTransform,
    detokenizer: lexical.ILexicalTransform,
    options: FormatOptions,
    indent_manager: ?indent_mod.IndentManager = null,
    
    const Self = @This();
    
    /// Initialize pipeline with emitter and detokenizer
    pub fn init(
        allocator: std.mem.Allocator,
        emitter: syntactic.ISyntacticTransform,
        detokenizer: lexical.ILexicalTransform,
        options: FormatOptions,
    ) Self {
        return .{
            .allocator = allocator,
            .emitter = emitter,
            .detokenizer = detokenizer,
            .options = options,
        };
    }
    
    /// Set indent manager for custom indentation
    pub fn setIndentManager(self: *Self, manager: indent_mod.IndentManager) void {
        self.indent_manager = manager;
    }
    
    pub fn deinit(self: *Self) void {
        _ = self;
    }
    
    /// Format AST to text
    pub fn format(self: *Self, ctx: *Context, ast: AST) ![]const u8 {
        // Check if emitter can emit tokens
        if (self.emitter.emitFn == null) {
            return error.EmitterNotReversible;
        }
        
        // Check if detokenizer can detokenize
        if (self.detokenizer.detokenizeFn == null) {
            return error.DetokenizerNotReversible;
        }
        
        // Set format options in context
        try ctx.setOption("indent_size", @as(i64, self.options.indent_size));
        try ctx.setOption("indent_style", @tagName(self.options.indent_style));
        try ctx.setOption("line_width", @as(i64, self.options.line_width));
        try ctx.setOption("preserve_newlines", self.options.preserve_newlines);
        try ctx.setOption("trailing_comma", self.options.trailing_comma);
        try ctx.setOption("sort_keys", self.options.sort_keys);
        try ctx.setOption("quote_style", @tagName(self.options.quote_style));
        
        // Emit tokens from AST
        ctx.startTiming();
        const tokens = try self.emitter.emitFn.?(ctx, ast);
        defer ctx.allocator.free(tokens);
        
        if (ctx.getOption("debug", bool) orelse false) {
            const emit_time = ctx.getElapsedMs() orelse 0;
            std.debug.print("Token emission took {}ms\n", .{emit_time});
        }
        
        // Apply formatting to tokens
        const formatted_tokens = try self.applyFormatting(ctx, tokens);
        defer ctx.allocator.free(formatted_tokens);
        
        // Detokenize to text
        ctx.startTiming();
        const text = try self.detokenizer.detokenizeFn.?(ctx, formatted_tokens);
        
        if (ctx.getOption("debug", bool) orelse false) {
            const detokenize_time = ctx.getElapsedMs() orelse 0;
            std.debug.print("Detokenization took {}ms\n", .{detokenize_time});
        }
        
        // Apply final indentation if needed
        if (self.indent_manager) |manager| {
            // Convert FormatOptions.IndentStyle to IndentManager.IndentStyle
            const indent_style = switch (self.options.indent_style) {
                .space => @import("../../text/indent.zig").IndentManager.IndentStyle.spaces,
                .tab => @import("../../text/indent.zig").IndentManager.IndentStyle.tabs,
            };
            const indented = try manager.convertStyle(text, indent_style, self.options.indent_size);
            ctx.allocator.free(text);
            return indented;
        }
        
        return text;
    }
    
    /// Apply formatting rules to tokens
    fn applyFormatting(self: *Self, ctx: *Context, tokens: []const Token) ![]const Token {
        const formatted = try ctx.allocator.alloc(Token, tokens.len);
        @memcpy(formatted, tokens);
        
        // Sort object keys if requested
        if (self.options.sort_keys) {
            try self.sortObjectKeys(ctx, formatted);
        }
        
        // Handle trailing commas
        if (self.options.trailing_comma) {
            try self.addTrailingCommas(ctx, formatted);
        } else {
            try self.removeTrailingCommas(ctx, formatted);
        }
        
        return formatted;
    }
    
    fn sortObjectKeys(_: *Self, _: *Context, tokens: []Token) !void {
        // TODO: Implement key sorting
        // This would require understanding object boundaries and key-value pairs
        _ = tokens;
    }
    
    fn addTrailingCommas(self: *Self, ctx: *Context, tokens: []Token) !void {
        _ = self;
        _ = ctx;
        // TODO: Add trailing commas where appropriate
        _ = tokens;
    }
    
    fn removeTrailingCommas(self: *Self, ctx: *Context, tokens: []Token) !void {
        _ = self;
        _ = ctx;
        // TODO: Remove trailing commas
        _ = tokens;
    }
    
    /// Reverse operation: Text → Tokens → AST (parsing)
    pub fn parse(_: *Self, ctx: *Context, text: []const u8) !AST {
        // This would require both lexer and parser, not just emitter/detokenizer
        // For now, return error
        _ = ctx;
        _ = text;
        return error.NotImplemented;
    }
    
    /// Create a transform representing this pipeline
    pub fn toTransform(_: *Self) Transform(AST, []const u8) {
        const forward_fn = struct {
            fn forward(ctx: *Context, input: AST) ![]const u8 {
                // This would need proper implementation
                _ = ctx;
                _ = input;
                return error.NotImplemented;
            }
        }.forward;
        
        const reverse_fn = struct {
            fn reverse(ctx: *Context, output: []const u8) !AST {
                // This would need proper implementation
                _ = ctx;
                _ = output;
                return error.NotImplemented;
            }
        }.reverse;
        
        return transform_mod.createTransform(
            AST,
            []const u8,
            forward_fn,
            reverse_fn,
            .{
                .name = "format_pipeline",
                .description = "AST formatting pipeline",
                .reversible = true,
                .streaming_capable = false,
                .performance_class = .medium,
            },
        );
    }
};

/// Format-preserving pipeline that maintains original formatting where possible
pub const PreservingFormatPipeline = struct {
    allocator: std.mem.Allocator,
    base_pipeline: FormatPipeline,
    original_tokens: ?[]const Token = null,
    original_text: ?[]const u8 = null,
    
    const Self = @This();
    
    pub fn init(
        allocator: std.mem.Allocator,
        emitter: syntactic.ISyntacticTransform,
        detokenizer: lexical.ILexicalTransform,
        options: FormatOptions,
    ) Self {
        return .{
            .allocator = allocator,
            .base_pipeline = FormatPipeline.init(allocator, emitter, detokenizer, options),
        };
    }
    
    pub fn deinit(self: *Self) void {
        if (self.original_tokens) |tokens| {
            self.allocator.free(tokens);
        }
        if (self.original_text) |text| {
            self.allocator.free(text);
        }
        self.base_pipeline.deinit();
    }
    
    /// Set original text and tokens for preservation
    pub fn setOriginal(self: *Self, text: []const u8, tokens: []const Token) !void {
        if (self.original_text) |old_text| {
            self.allocator.free(old_text);
        }
        if (self.original_tokens) |old_tokens| {
            self.allocator.free(old_tokens);
        }
        
        self.original_text = try self.allocator.dupe(u8, text);
        self.original_tokens = try self.allocator.dupe(Token, tokens);
    }
    
    /// Format while preserving original trivia
    pub fn formatPreserving(self: *Self, ctx: *Context, ast: AST) ![]const u8 {
        if (self.original_tokens == null or self.original_text == null) {
            // No original to preserve, use regular formatting
            return try self.base_pipeline.format(ctx, ast);
        }
        
        // Emit new tokens from AST
        const new_tokens = try self.base_pipeline.emitter.emitFn.?(ctx, ast);
        defer ctx.allocator.free(new_tokens);
        
        // Merge trivia from original tokens
        const merged_tokens = try self.mergeTrivia(ctx, self.original_tokens.?, new_tokens);
        defer ctx.allocator.free(merged_tokens);
        
        // Detokenize with preserved trivia
        return try self.base_pipeline.detokenizer.detokenizeFn.?(ctx, merged_tokens);
    }
    
    fn mergeTrivia(self: *Self, ctx: *Context, original: []const Token, new: []const Token) ![]const Token {
        _ = self;
        var merged = try ctx.allocator.alloc(Token, new.len);
        
        // Simple merge strategy - copy tokens but try to preserve spacing
        for (new, 0..) |token, i| {
            merged[i] = token;
            
            // Try to find corresponding original token
            if (i < original.len) {
                // Could match by token kind and relative position
                // For now, just copy the new token
            }
        }
        
        return merged;
    }
};

/// Streaming formatter for large files
pub const StreamingFormatter = struct {
    allocator: std.mem.Allocator,
    format_pipeline: FormatPipeline,
    buffer_size: usize = 64 * 1024, // 64KB default
    
    const Self = @This();
    
    pub fn init(
        allocator: std.mem.Allocator,
        emitter: syntactic.ISyntacticTransform,
        detokenizer: lexical.ILexicalTransform,
        options: FormatOptions,
    ) Self {
        return .{
            .allocator = allocator,
            .format_pipeline = FormatPipeline.init(allocator, emitter, detokenizer, options),
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.format_pipeline.deinit();
    }
    
    /// Format AST to writer stream
    pub fn formatToWriter(self: *Self, ctx: *Context, ast: AST, writer: anytype) !void {
        // Format to text
        const formatted = try self.format_pipeline.format(ctx, ast);
        defer ctx.allocator.free(formatted);
        
        // Write in chunks
        var offset: usize = 0;
        while (offset < formatted.len) {
            const chunk_size = @min(self.buffer_size, formatted.len - offset);
            const chunk = formatted[offset .. offset + chunk_size];
            
            try writer.writeAll(chunk);
            offset += chunk_size;
            
            // Update progress if available
            if (ctx.progress) |progress| {
                progress.bytes_processed = offset;
                progress.total_bytes = formatted.len;
            }
        }
    }
};

/// Format options builder for fluent configuration
pub const FormatOptionsBuilder = struct {
    options: FormatOptions,
    
    const Self = @This();
    
    pub fn init() Self {
        return .{ .options = FormatOptions{} };
    }
    
    pub fn indentSize(self: *Self, size: u32) *Self {
        self.options.indent_size = size;
        return self;
    }
    
    pub fn indentStyle(self: *Self, style: FormatOptions.IndentStyle) *Self {
        self.options.indent_style = style;
        return self;
    }
    
    pub fn lineWidth(self: *Self, width: u32) *Self {
        self.options.line_width = width;
        return self;
    }
    
    pub fn preserveNewlines(self: *Self, preserve: bool) *Self {
        self.options.preserve_newlines = preserve;
        return self;
    }
    
    pub fn trailingComma(self: *Self, trailing: bool) *Self {
        self.options.trailing_comma = trailing;
        return self;
    }
    
    pub fn sortKeys(self: *Self, sort: bool) *Self {
        self.options.sort_keys = sort;
        return self;
    }
    
    pub fn quoteStyle(self: *Self, style: FormatOptions.QuoteStyle) *Self {
        self.options.quote_style = style;
        return self;
    }
    
    pub fn build(self: Self) FormatOptions {
        return self.options;
    }
};

// Tests
const testing = std.testing;
const builder = @import("../../ast/builder.zig");
const Span = @import("../../parser/foundation/types/span.zig").Span;

test "FormatPipeline basic usage" {
    const allocator = testing.allocator;
    
    var ctx = Context.init(allocator);
    defer ctx.deinit();
    
    // Create mock emitter
    const mock_emitter = syntactic.ISyntacticTransform{
        .parseFn = struct {
            fn parse(context: *Context, tokens: []const Token) !AST {
                _ = tokens;
                return AST.init(context.allocator);
            }
        }.parse,
        .emitFn = struct {
            fn emit(context: *Context, ast: AST) ![]const Token {
                _ = ast;
                var tokens = try context.allocator.alloc(Token, 1);
                tokens[0] = Token.simple(Span.init(0, 4), .null_literal, "null", 0);
                return tokens;
            }
        }.emit,
        .parseWithRecoveryFn = null,
        .metadata = .{ .name = "mock_emitter", .description = "Test emitter" },
    };
    
    // Create mock detokenizer
    const mock_detokenizer = lexical.ILexicalTransform{
        .tokenizeFn = struct {
            fn tokenize(context: *Context, text: []const u8) ![]const Token {
                _ = text;
                return try context.allocator.alloc(Token, 0);
            }
        }.tokenize,
        .detokenizeFn = struct {
            fn detokenize(context: *Context, tokens: []const Token) ![]const u8 {
                _ = tokens;
                return try context.allocator.dupe(u8, "null");
            }
        }.detokenize,
        .metadata = .{ .name = "mock_detokenizer", .description = "Test detokenizer" },
    };
    
    const options = FormatOptions{
        .indent_size = 2,
        .indent_style = .space,
    };
    
    var pipeline = FormatPipeline.init(allocator, mock_emitter, mock_detokenizer, options);
    defer pipeline.deinit();
    
    var ast = AST.init(allocator);
    defer ast.deinit();
    ast.root = try @import("../../ast/node.zig").createLeafNode(allocator, @intFromEnum(@import("../../ast/rules.zig").CommonRules.null_literal), "null", 0, 4);
    
    const formatted = try pipeline.format(&ctx, ast);
    defer allocator.free(formatted);
    
    try testing.expectEqualStrings("null", formatted);
}

test "FormatOptionsBuilder usage" {
    var builder_inst = FormatOptionsBuilder.init();
    const options = builder_inst
        .indentSize(4)
        .indentStyle(.tab)
        .lineWidth(120)
        .trailingComma(true)
        .sortKeys(true)
        .build();
    
    try testing.expectEqual(@as(u32, 4), options.indent_size);
    try testing.expectEqual(FormatOptions.IndentStyle.tab, options.indent_style);
    try testing.expectEqual(@as(u32, 120), options.line_width);
    try testing.expect(options.trailing_comma);
    try testing.expect(options.sort_keys);
}