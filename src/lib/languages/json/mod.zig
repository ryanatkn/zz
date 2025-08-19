const std = @import("std");
const Language = @import("../../core/language.zig").Language;
const LanguageSupport = @import("../interface.zig").LanguageSupport;
const Lexer = @import("../interface.zig").Lexer;
const Parser = @import("../interface.zig").Parser;
const Formatter = @import("../interface.zig").Formatter;
const Linter = @import("../interface.zig").Linter;
const Analyzer = @import("../interface.zig").Analyzer;
const Token = @import("../../parser/foundation/types/token.zig").Token;
const AST = @import("../../ast/mod.zig").AST;
const FormatOptions = @import("../interface.zig").FormatOptions;
const Rule = @import("../interface.zig").Rule;
const Symbol = @import("../interface.zig").Symbol;
const Diagnostic = @import("../interface.zig").Diagnostic;

// Import JSON-specific implementations
const JsonLexer = @import("lexer.zig").JsonLexer;
const JsonParser = @import("parser.zig").JsonParser;
const JsonFormatter = @import("formatter.zig").JsonFormatter;
const JsonLinter = @import("linter.zig").JsonLinter;
const JsonAnalyzer = @import("analyzer.zig").JsonAnalyzer;

// Transform pipeline support
pub const transform = @import("transform.zig");
pub const JsonTransformPipeline = transform.JsonTransformPipeline;
pub const JsonLexicalTransform = transform.JsonLexicalTransform;
pub const JsonSyntacticTransform = transform.JsonSyntacticTransform;

/// Complete JSON language support implementation
///
/// This module provides full JSON parsing, formatting, linting, and analysis
/// capabilities using the unified language architecture. It serves as the
/// reference implementation for how languages should be integrated.
///
/// Features:
/// - High-performance lexing and parsing with error recovery
/// - Configurable formatting with JSON5 support
/// - Comprehensive linting with duplicate key detection
/// - Schema extraction and TypeScript interface generation
/// - Performance optimized for config files and data exchange
/// Get JSON language support instance
pub fn getSupport(_: std.mem.Allocator) !LanguageSupport {
    return LanguageSupport{
        .language = .json,
        .lexer = Lexer{
            .tokenizeFn = tokenize,
            .tokenizeChunkFn = tokenizeChunk,
            .updateTokensFn = null, // TODO: Implement incremental tokenization
        },
        .parser = Parser{
            .parseFn = parse,
            .parseWithBoundariesFn = null, // Boundaries not used for JSON
        },
        .formatter = Formatter{
            .formatFn = format,
            .formatRangeFn = null, // Range formatting not implemented for JSON
        },
        .linter = Linter{
            .rules = &JsonLinter.RULES,
            .lintFn = lint,
        },
        .analyzer = Analyzer{
            .extractSymbolsFn = extractSymbols,
            .buildCallGraphFn = null, // Not applicable for JSON
            .findReferencesFn = null, // Not applicable for JSON
        },
        .deinitFn = null, // No global state to clean up
    };
}

/// Tokenize JSON source code
fn tokenize(allocator: std.mem.Allocator, input: []const u8) ![]Token {
    var lexer = JsonLexer.init(allocator, input, .{
        .allow_comments = false, // Standard JSON
        .allow_trailing_commas = false,
    });
    defer lexer.deinit();

    return lexer.tokenize();
}

/// Tokenize JSON source code chunk for streaming
pub fn tokenizeChunk(allocator: std.mem.Allocator, input: []const u8, start_pos: usize) ![]Token {
    var lexer = JsonLexer.init(allocator, input, .{
        .allow_comments = false, // Standard JSON
        .allow_trailing_commas = false,
    });
    defer lexer.deinit();
    
    const tokens = try lexer.tokenize();
    
    // Adjust token positions for the start_pos offset
    for (tokens) |*token| {
        token.span.start += start_pos;
        token.span.end += start_pos;
    }
    
    return tokens;
}

/// Parse JSON tokens into AST
pub fn parse(allocator: std.mem.Allocator, tokens: []Token) !AST {
    var parser = JsonParser.init(allocator, tokens, .{
        .allow_trailing_commas = false,
        .recover_from_errors = true,
    });
    defer parser.deinit();

    return parser.parse();
}

/// Format JSON AST
fn format(allocator: std.mem.Allocator, ast: AST, options: FormatOptions) ![]const u8 {
    // Convert generic FormatOptions to JSON-specific options
    const json_options = JsonFormatter.JsonFormatOptions{
        .indent_size = options.indent_size,
        .indent_style = if (options.indent_style == .tab) .tab else .space,
        .line_width = options.line_width,
        .preserve_newlines = options.preserve_newlines,
        .compact_objects = false, // Default to pretty printing
        .compact_arrays = false,
        .sort_keys = options.sort_keys,
        .trailing_comma = options.trailing_comma,
        .quote_style = switch (options.quote_style) {
            .single => .single,
            .double => .double,
            .preserve => .preserve,
        },
        .space_after_colon = true,
        .space_after_comma = true,
        .force_compact = false,
        .force_multiline = false,
    };

    var formatter = JsonFormatter.init(allocator, json_options);
    defer formatter.deinit();

    return formatter.format(ast);
}

/// Lint JSON AST
fn lint(allocator: std.mem.Allocator, ast: AST, rules: []const Rule) ![]Diagnostic {
    var linter = JsonLinter.init(allocator, .{
        .max_depth = 100,
        .max_string_length = 65536,
        .max_number_precision = 15,
        .max_object_keys = 10000,
        .max_array_elements = 100000,
        .allow_duplicate_keys = false,
        .allow_leading_zeros = false,
        .allow_trailing_decimals = true,
        .require_quotes_around_keys = true,
        .warn_on_large_numbers = true,
        .warn_on_deep_nesting = 20,
    });
    defer linter.deinit();

    return linter.lint(ast, rules);
}

/// Extract symbols from JSON AST
fn extractSymbols(allocator: std.mem.Allocator, ast: AST) ![]Symbol {
    var analyzer = JsonAnalyzer.init(allocator, .{
        .infer_array_types = true,
        .detect_nullable_fields = true,
        .suggest_optimizations = true,
        .max_schema_depth = 20,
        .min_samples_for_inference = 2,
    });

    return analyzer.extractSymbols(ast);
}

// Convenience functions for direct use

/// Parse and validate JSON from string
pub fn parseJson(allocator: std.mem.Allocator, input: []const u8) !AST {
    const tokens = try tokenize(allocator, input);
    defer allocator.free(tokens);

    return parse(allocator, tokens);
}

/// Format JSON string with default options
pub fn formatJsonString(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var ast = try parseJson(allocator, input);
    defer ast.deinit();

    const default_options = FormatOptions{
        .indent_size = 2,
        .indent_style = .space,
        .line_width = 80,
        .preserve_newlines = false,
        .trailing_comma = false,
        .sort_keys = false,
        .quote_style = .double,
    };

    return format(allocator, ast, default_options);
}

/// Validate JSON and return any errors
pub fn validateJson(allocator: std.mem.Allocator, input: []const u8) ![]Diagnostic {
    var ast = try parseJson(allocator, input);
    defer ast.deinit();

    const all_rules = JsonLinter.RULES;
    var enabled_rules = std.ArrayList(Rule).init(allocator);
    defer enabled_rules.deinit();

    // Enable all rules by default
    for (all_rules) |rule| {
        var enabled_rule = rule;
        enabled_rule.enabled = true;
        try enabled_rules.append(enabled_rule);
    }

    return lint(allocator, ast, enabled_rules.items);
}

/// Extract schema from JSON
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

/// Get statistics about JSON structure
pub fn getJsonStatistics(allocator: std.mem.Allocator, input: []const u8) !JsonAnalyzer.JsonStatistics {
    var ast = try parseJson(allocator, input);
    defer ast.deinit();

    var analyzer = JsonAnalyzer.init(allocator, .{});
    return analyzer.generateStatistics(ast);
}

// Re-export types for convenience
pub const JsonSchema = JsonAnalyzer.JsonSchema;
pub const JsonStatistics = JsonAnalyzer.JsonStatistics;
pub const TypeScriptInterface = JsonAnalyzer.TypeScriptInterface;
pub const LexerOptions = JsonLexer.LexerOptions;
pub const ParserOptions = JsonParser.ParserOptions;
pub const JsonFormatOptions = JsonFormatter.JsonFormatOptions;
pub const LinterOptions = JsonLinter.LinterOptions;
pub const AnalyzerOptions = JsonAnalyzer.AnalyzerOptions;

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

    // AST.root is non-optional now

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

    // Test schema extraction
    var schema = try extractJsonSchema(allocator, input);
    defer schema.deinit(allocator);

    try testing.expectEqual(JsonAnalyzer.JsonSchema.SchemaType.object, schema.schema_type);

    // Test TypeScript interface generation
    var interface = try generateTypeScriptInterface(allocator, input, "User");
    defer interface.deinit(allocator);

    try testing.expectEqualStrings("User", interface.name);
    try testing.expectEqual(@as(usize, 3), interface.fields.items.len);

    // Test statistics
    const stats = try getJsonStatistics(allocator, input);

    try testing.expectEqual(@as(u32, 1), stats.type_counts.strings);
    try testing.expectEqual(@as(u32, 1), stats.type_counts.numbers);
    try testing.expectEqual(@as(u32, 1), stats.type_counts.booleans);
    try testing.expectEqual(@as(u32, 1), stats.type_counts.objects);
}

test "JSON module - language support interface" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const support = try getSupport(allocator);

    // Test that all required components are present
    try testing.expectEqual(Language.json, support.language);
    // Check that function pointers are set (they're not optional)
    _ = support.lexer.tokenizeFn;
    _ = support.parser.parseFn;
    _ = support.formatter.formatFn;
    try testing.expect(support.linter != null);
    try testing.expect(support.analyzer != null);

    // Test lexer interface
    const input = "\"hello\"";
    const tokens = try support.lexer.tokenize(allocator, input);
    defer allocator.free(tokens);

    try testing.expect(tokens.len > 0);

    // Test parser interface
    var ast = try support.parser.parse(allocator, tokens);
    defer ast.deinit();

    // AST.root is non-optional now

    // Test formatter interface
    const default_options = FormatOptions{};
    const formatted = try support.formatter.format(allocator, ast, default_options);
    defer allocator.free(formatted);

    try testing.expect(formatted.len > 0);

    // Test linter interface
    const rules = &[_]Rule{
        Rule{ .name = "test-rule", .description = "", .severity = .warning, .enabled = true },
    };
    const diagnostics = try support.linter.?.lint(allocator, ast, rules);
    defer {
        for (diagnostics) |diag| {
            allocator.free(diag.message);
        }
        allocator.free(diagnostics);
    }

    // Test analyzer interface
    const symbols = try support.analyzer.?.extractSymbols(allocator, ast);
    defer {
        for (symbols) |symbol| {
            allocator.free(symbol.name);
            if (symbol.signature) |sig| {
                allocator.free(sig);
            }
        }
        allocator.free(symbols);
    }

    try testing.expect(symbols.len > 0);
}

test "JSON module - error handling" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test invalid JSON
    const invalid_input = "{\"key\": }";

    // Should parse with errors but not crash
    var ast = parseJson(allocator, invalid_input) catch |err| switch (err) {
        error.ParseError => {
            // Expected for invalid JSON
            return;
        },
        else => return err,
    };
    defer ast.deinit();

    // Should still produce some AST structure for error recovery
    // AST.root is non-optional now
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
        // AST.root is non-optional now
        // AST.root is non-optional now
    }
}
