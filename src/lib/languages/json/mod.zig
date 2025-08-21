/// JSON Language Module - Self-contained JSON support
///
/// Following the new architecture where each language is completely independent.
/// No shared interfaces, no shared AST types, just direct exports.
const std = @import("std");

// Import JSON-specific implementations - all self-contained
const JsonLexer = @import("lexer.zig").JsonLexer;
const JsonParser = @import("parser.zig").JsonParser;
const JsonFormatter = @import("formatter.zig").JsonFormatter;
const JsonLinter = @import("linter.zig").JsonLinter;
const JsonAnalyzer = @import("analyzer.zig").JsonAnalyzer;

// Import JSON AST
const json_ast = @import("ast.zig");
pub const AST = json_ast.AST;
pub const Node = json_ast.Node;
pub const NodeKind = json_ast.NodeKind;

// Import token type
const Token = @import("../../token/token.zig").Token;

// Re-export all JSON components
pub const Lexer = JsonLexer;
pub const Parser = JsonParser;
pub const Formatter = JsonFormatter;
pub const Linter = JsonLinter;
pub const Analyzer = JsonAnalyzer;

// Re-export types for convenience
pub const LexerOptions = JsonLexer.LexerOptions;
pub const ParserOptions = JsonParser.ParserOptions;
pub const JsonFormatOptions = JsonFormatter.JsonFormatOptions;
pub const LinterOptions = JsonLinter.LinterOptions;
pub const AnalyzerOptions = JsonAnalyzer.AnalyzerOptions;

// Simple direct functions - no interface abstraction
/// Tokenize JSON source code
pub fn tokenize(allocator: std.mem.Allocator, input: []const u8) ![]Token {
    var lexer = JsonLexer.init(allocator);
    defer lexer.deinit();
    return lexer.batchTokenize(allocator, input);
}

/// Parse JSON tokens into AST
pub fn parse(allocator: std.mem.Allocator, tokens: []Token, source: []const u8) !AST {
    var parser = JsonParser.init(allocator, tokens, source, .{});
    defer parser.deinit();
    return parser.parse();
}

/// Format JSON AST back to source
pub fn format(allocator: std.mem.Allocator, ast: AST, options: JsonFormatter.JsonFormatOptions) ![]const u8 {
    var formatter = JsonFormatter.init(allocator, options);
    defer formatter.deinit();
    return formatter.format(ast);
}

/// Convenience functions for end-to-end operations

/// Parse JSON from string
pub fn parseJson(allocator: std.mem.Allocator, input: []const u8) !AST {
    const tokens = try tokenize(allocator, input);
    defer allocator.free(tokens);
    return parse(allocator, tokens, input);
}

/// Format JSON string with default options
pub fn formatJsonString(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var ast = try parseJson(allocator, input);
    defer ast.deinit();

    const default_options = JsonFormatter.JsonFormatOptions{
        .indent_size = 2,
        .indent_style = .space,
        .line_width = 80,
        .preserve_newlines = false,
        .compact_objects = false,
        .compact_arrays = false,
        .sort_keys = false,
        .trailing_comma = false,
        .quote_style = .double,
        .space_after_colon = true,
        .space_after_comma = true,
        .force_compact = false,
        .force_multiline = false,
    };

    return format(allocator, ast, default_options);
}

/// Validate JSON and return any errors  
pub fn validateJson(allocator: std.mem.Allocator, input: []const u8) ![]JsonLinter.Diagnostic {
    var ast = try parseJson(allocator, input);
    defer ast.deinit();

    var linter = JsonLinter.init(allocator, .{});
    defer linter.deinit();
    
    const all_rules = JsonLinter.RULES;
    return linter.lint(ast, all_rules);
}

// Tests
const testing = std.testing;

test "JSON module - complete pipeline" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = "{\"name\": \"Alice\", \"age\": 30, \"active\": true}";

    // Test parsing
    var ast = try parseJson(allocator, input);
    defer ast.deinit();

    // Test formatting
    const formatted = try formatJsonString(allocator, input);
    defer allocator.free(formatted);

    try testing.expect(formatted.len > 0);

    // Test validation
    const diagnostics = try validateJson(allocator, input);
    defer {
        for (diagnostics) |diag| {
            allocator.free(diag.message);
        }
        allocator.free(diagnostics);
    }

    // Should have no errors for valid JSON
    try testing.expectEqual(@as(usize, 0), diagnostics.len);
}

test "JSON module - round-trip formatting" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const inputs = [_][]const u8{
        "\"string\"",
        "42",
        "true",
        "false",
        "null",
        "[]",
        "{}",
        "{\"key\": \"value\"}",
        "[1, 2, 3]",
    };

    for (inputs) |input| {
        var ast = try parseJson(allocator, input);
        defer ast.deinit();

        const formatted = try formatJsonString(allocator, input);
        defer allocator.free(formatted);

        // Parse the formatted output
        var ast2 = try parseJson(allocator, formatted);
        defer ast2.deinit();

        // Both ASTs should be valid (basic round-trip test)
    }
}