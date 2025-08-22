/// JSON Language Module - Self-contained JSON support
///
/// Following the new architecture where each language is completely independent.
/// No shared interfaces, no shared AST types, just direct exports.
const std = @import("std");

// Import JSON-specific implementations - all self-contained
const JsonLexer = @import("lexer.zig").JsonLexer;
const JsonParser = @import("parser.zig").JsonParser;
const JsonFormatter = @import("formatter.zig").JsonFormatter;
const linter_mod = @import("linter.zig");
const JsonLinter = linter_mod.JsonLinter;
const Diagnostic = linter_mod.Diagnostic;
const JsonRuleType = linter_mod.JsonRuleType;
const EnabledRules = linter_mod.EnabledRules;
const JsonAnalyzer = @import("analyzer.zig").JsonAnalyzer;

// Import JSON AST
const json_ast = @import("ast.zig");
pub const AST = json_ast.AST;
pub const Node = json_ast.Node;
pub const NodeKind = json_ast.NodeKind;

// Import token type
const Token = @import("../../token/token.zig").Token;

// Import language interface
const interface = @import("../interface.zig");
const LanguageSupport = interface.LanguageSupport;

// Re-export all JSON components
pub const Lexer = JsonLexer;
pub const Parser = JsonParser;
pub const Formatter = JsonFormatter;
pub const Linter = JsonLinter;

// Export language-specific types for interface
pub const RuleType = JsonRuleType;
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
pub fn validateJson(allocator: std.mem.Allocator, input: []const u8) ![]Diagnostic {
    var ast = try parseJson(allocator, input);
    defer ast.deinit();

    var linter = JsonLinter.init(allocator, .{});
    defer linter.deinit();

    const all_rules = JsonLinter.getDefaultRules();
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

/// Get the language support interface for JSON
pub fn getSupport(allocator: std.mem.Allocator) !interface.LanguageSupport(json_ast.AST, JsonRuleType) {
    _ = allocator; // Not needed for function pointer approach

    return interface.LanguageSupport(json_ast.AST, JsonRuleType){
        .language = .json,
        .lexer = interface.Lexer{
            .tokenizeFn = jsonTokenize,
            .tokenizeChunkFn = jsonTokenizeChunk,
            .updateTokensFn = null,
        },
        .parser = interface.Parser(json_ast.AST){
            .parseFn = jsonParse,
            .parseWithBoundariesFn = null,
        },
        .formatter = interface.Formatter(json_ast.AST){
            .formatFn = jsonFormat,
            .formatRangeFn = null,
        },
        .linter = interface.Linter(json_ast.AST, JsonRuleType){
            .ruleInfoFn = jsonGetRuleInfo,
            .lintFn = jsonLintEnum,
            .getDefaultRulesFn = jsonGetDefaultRules,
        },
        .analyzer = interface.Analyzer(json_ast.AST){
            .extractSymbolsFn = jsonExtractSymbols,
            .buildCallGraphFn = null,
            .findReferencesFn = null,
        },
    };
}

// Implementation functions for interface
fn jsonTokenize(allocator: std.mem.Allocator, input: []const u8) ![]Token {
    var lexer = JsonLexer.init(allocator);
    defer lexer.deinit();
    return lexer.tokenize(input);
}

fn jsonTokenizeChunk(allocator: std.mem.Allocator, input: []const u8, start_pos: usize) ![]Token {
    _ = start_pos; // Simple implementation ignores start_pos for now
    return jsonTokenize(allocator, input);
}

fn jsonParse(allocator: std.mem.Allocator, tokens: []Token) !json_ast.AST {
    var parser = JsonParser.init(allocator, tokens, "", .{});
    defer parser.deinit();
    return try parser.parse();
}

fn jsonFormat(allocator: std.mem.Allocator, ast: json_ast.AST, options: interface.FormatOptions) ![]const u8 {
    var formatter = JsonFormatter.init(allocator, .{
        .indent_size = options.indent_size,
        .line_width = options.line_width,
    });
    defer formatter.deinit();
    return formatter.format(ast);
}

fn jsonExtractSymbols(allocator: std.mem.Allocator, ast: json_ast.AST) ![]interface.Symbol {
    var analyzer = JsonAnalyzer.init(allocator, .{});
    const json_symbols = try analyzer.extractSymbols(ast);
    defer allocator.free(json_symbols);

    // Convert JSON symbols to interface symbols
    var result = try allocator.alloc(interface.Symbol, json_symbols.len);
    for (json_symbols, 0..) |json_symbol, i| {
        result[i] = interface.Symbol{
            .name = json_symbol.name,
            .kind = convertSymbolKind(json_symbol.kind),
            .range = json_symbol.range,
            .signature = json_symbol.signature,
            .documentation = json_symbol.documentation,
        };
    }
    return result;
}

fn convertSymbolKind(json_kind: anytype) interface.Symbol.SymbolKind {
    return switch (json_kind) {
        .property => .property,
        .object => .struct_, // JSON objects map to struct-like
        .array => .variable, // JSON arrays map to variables
        .array_element => .variable,
        .string => .constant,
        .number => .constant,
        .boolean => .constant,
        .null_value => .constant,
    };
}

/// Extract JSON schema from input
pub fn extractJsonSchema(allocator: std.mem.Allocator, input: []const u8) !JsonAnalyzer.JsonSchema {
    var ast = try parseJson(allocator, input);
    defer ast.deinit();

    var analyzer = JsonAnalyzer.init(allocator, .{});

    return analyzer.extractSchema(ast);
}

/// Generate TypeScript interface from JSON
pub fn generateTypeScriptInterface(allocator: std.mem.Allocator, input: []const u8, interface_name: []const u8) !JsonAnalyzer.TypeScriptInterface {
    var ast = try parseJson(allocator, input);
    defer ast.deinit();

    var analyzer = JsonAnalyzer.init(allocator, .{});

    return analyzer.generateTypeScriptInterface(ast, interface_name);
}

// Interface functions for the new generic linter

/// Get rule information for a specific JSON rule
fn jsonGetRuleInfo(rule: JsonRuleType) interface.RuleInfo {
    const rule_info = JsonLinter.RULE_INFO.get(rule);
    return interface.RuleInfo{
        .name = rule_info.name,
        .description = rule_info.description,
        .severity = rule_info.severity,
        .enabled_by_default = rule_info.enabled_by_default,
    };
}

/// Lint with enum-based rules (new interface)
fn jsonLintEnum(allocator: std.mem.Allocator, ast: json_ast.AST, enabled_rules: EnabledRules) ![]interface.Diagnostic {
    var linter = JsonLinter.init(allocator, .{});
    defer linter.deinit();

    const diagnostics = try linter.lint(ast, enabled_rules);

    // Convert to interface diagnostics
    var result = try allocator.alloc(interface.Diagnostic, diagnostics.len);
    for (diagnostics, 0..) |diag, i| {
        result[i] = interface.Diagnostic{
            .rule = diag.rule,
            .message = diag.message,
            .severity = diag.severity,
            .range = diag.range,
            .fix = null, // TODO: Convert fix if needed
        };
    }
    allocator.free(diagnostics); // Free original diagnostics
    return result;
}

/// Get default rules for JSON
fn jsonGetDefaultRules() EnabledRules {
    return JsonLinter.getDefaultRules();
}

/// Get JSON statistics
pub fn getJsonStatistics(allocator: std.mem.Allocator, input: []const u8) !JsonAnalyzer.JsonStatistics {
    var ast = try parseJson(allocator, input);
    defer ast.deinit();

    var analyzer = JsonAnalyzer.init(allocator, .{});

    return analyzer.generateStatistics(ast);
}
