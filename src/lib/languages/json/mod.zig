/// JSON Language Module - Self-contained JSON support
///
/// SIMPLIFIED: Direct streaming architecture, no old Token infrastructure
/// Each language owns its implementation completely
const std = @import("std");

// Import all interface types from single module
const lang_interface = @import("../interface.zig");
const LanguageSupport = lang_interface.LanguageSupport;
const InterfaceLexer = lang_interface.Lexer;
const InterfaceParser = lang_interface.Parser;
const InterfaceFormatter = lang_interface.Formatter;
const InterfaceLinter = lang_interface.Linter;
const InterfaceAnalyzer = lang_interface.Analyzer;
const FormatOptions = lang_interface.FormatOptions;
const Rule = lang_interface.Rule;
const Symbol = lang_interface.Symbol;

// Import JSON-specific implementations - all self-contained
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

// Direct exports
pub const Parser = JsonParser;
pub const Formatter = JsonFormatter;
pub const Linter = JsonLinter;
pub const RuleType = JsonRuleType;
pub const Analyzer = JsonAnalyzer;
pub const AnalyzerOptions = JsonAnalyzer.AnalyzerOptions;
pub const ParserOptions = JsonParser.ParserOptions;

// Streaming lexer exports (the new way)
pub const StreamLexer = @import("stream_lexer.zig").JsonStreamLexer;
pub const StreamToken = @import("stream_token.zig").JsonToken;
pub const StreamTokenKind = @import("stream_token.zig").JsonTokenKind;

/// Parse JSON source into AST using streaming parser (convenience function)
pub fn parse(allocator: std.mem.Allocator, source: []const u8) !AST {
    var parser = try JsonParser.init(allocator, source, .{});
    defer parser.deinit();
    return parser.parse();
}

/// Parse JSON source into AST (alias for backward compatibility)
pub const parseJson = parse;

/// Validate JSON string and return diagnostics (convenience function)
pub fn validateJson(allocator: std.mem.Allocator, json_content: []const u8) ![]Diagnostic {
    var linter = JsonLinter.init(allocator, .{});
    defer linter.deinit();
    const rules = JsonLinter.getDefaultRules();
    return linter.lintSource(json_content, rules);
}

/// Format JSON string directly (convenience function)
/// This is a convenience function for cases where you have raw JSON text
/// and need to format it without first parsing to AST (e.g., CLI tools).
/// For better performance, prefer parse() → format(ast) when you need both parsing and formatting.
pub fn formatJsonString(allocator: std.mem.Allocator, json_content: []const u8) ![]u8 {
    // Use formatter directly with source for this convenience case
    const json_options = JsonFormatter.JsonFormatOptions{
        .indent_size = 4,
        .indent_style = .space,
        .line_width = 100,
        .preserve_newlines = false,
        .force_compact = false,
        .trailing_comma = false,
    };

    var formatter = JsonFormatter.init(allocator, json_options);
    defer formatter.deinit();
    const formatted = try formatter.formatSource(json_content);
    return try allocator.dupe(u8, formatted);
}

/// Extract JSON schema from source (convenience function)
pub fn extractJsonSchema(allocator: std.mem.Allocator, json_content: []const u8) !JsonAnalyzer.JsonSchema {
    var ast = try parse(allocator, json_content);
    defer ast.deinit();

    var analyzer = JsonAnalyzer.init(allocator, .{});
    return analyzer.extractSchema(ast);
}

/// Generate TypeScript interface from JSON source (convenience function)
pub fn generateTypeScriptInterface(allocator: std.mem.Allocator, json_content: []const u8, interface_name: []const u8) !JsonAnalyzer.TypeScriptInterface {
    var ast = try parse(allocator, json_content);
    defer ast.deinit();

    var analyzer = JsonAnalyzer.init(allocator, .{});
    return analyzer.generateTypeScriptInterface(ast, interface_name);
}

/// Get JSON statistics from source (convenience function)
pub fn getJsonStatistics(allocator: std.mem.Allocator, json_content: []const u8) !JsonAnalyzer.JsonStatistics {
    var ast = try parse(allocator, json_content);
    defer ast.deinit();

    var analyzer = JsonAnalyzer.init(allocator, .{});
    return analyzer.generateStatistics(ast);
}

/// Get JSON language support instance
pub fn getSupport(allocator: std.mem.Allocator) !lang_interface.LanguageSupport(AST, JsonRuleType) {
    _ = allocator; // Not needed for static interface
    return lang_interface.LanguageSupport(AST, JsonRuleType){
        .language = .json,
        .lexer = InterfaceLexer{
            .tokenizeFn = tokenizeStub, // Streaming lexer - not using old batch interface
            .tokenizeChunkFn = tokenizeChunkStub, // Streaming lexer - not using old batch interface
            .updateTokensFn = null, // Incremental tokenization not implemented
        },
        .parser = InterfaceParser(AST){
            .parseFn = parseStub, // Streaming parser - not using old interface
            .parseWithBoundariesFn = null, // Boundaries not used for JSON
        },
        .formatter = InterfaceFormatter(AST){
            .formatFn = format,
            .formatRangeFn = null, // Range formatting not implemented for JSON
        },
        .linter = InterfaceLinter(AST, JsonRuleType){
            .ruleInfoFn = jsonGetRuleInfo,
            .lintFn = jsonLintEnum,
            .getDefaultRulesFn = jsonGetDefaultRules,
        },
        .analyzer = InterfaceAnalyzer(AST){
            .extractSymbolsFn = extractSymbols,
            .buildCallGraphFn = null, // Not applicable for JSON
            .findReferencesFn = null, // Not applicable for JSON
        },
        .deinitFn = null,
    };
}

/// Format JSON AST
fn format(allocator: std.mem.Allocator, ast: AST, options: FormatOptions) ![]const u8 {
    // Convert generic FormatOptions to JSON-specific options
    const json_options = JsonFormatter.JsonFormatOptions{
        .indent_size = @intCast(options.indent_size), // Convert u32 to u8
        .indent_style = if (options.indent_style == .space)
            JsonFormatter.JsonFormatOptions.IndentStyle.space
        else
            JsonFormatter.JsonFormatOptions.IndentStyle.tab,
        .line_width = options.line_width,
        .preserve_newlines = options.preserve_newlines,
        .force_compact = false, // JSON-specific default
        .trailing_comma = options.trailing_comma,
    };

    var formatter = JsonFormatter.init(allocator, json_options);
    defer formatter.deinit();
    return formatter.format(ast);
}

/// Extract symbols from JSON AST
pub fn extractSymbols(allocator: std.mem.Allocator, ast: AST) ![]Symbol {
    var analyzer = JsonAnalyzer.init(allocator, .{});

    const json_symbols = try analyzer.extractSymbols(ast);
    defer allocator.free(json_symbols);

    // Convert JSON symbols to generic symbols (allocate new strings)
    var symbols = std.ArrayList(Symbol).init(allocator);
    defer symbols.deinit();

    for (json_symbols) |json_symbol| {
        try symbols.append(Symbol{
            .name = try allocator.dupe(u8, json_symbol.name),
            .kind = switch (json_symbol.kind) {
                .string => .constant,
                .number => .constant,
                .boolean => .constant,
                .null_value => .constant,
                .property => .property,
                .array_element => .constant,
                .object => .struct_,
                .array => .constant,
            },
            .range = json_symbol.range,
            .signature = if (json_symbol.signature) |sig| try allocator.dupe(u8, sig) else null,
            .documentation = if (json_symbol.documentation) |doc| try allocator.dupe(u8, doc) else null,
        });
    }

    return symbols.toOwnedSlice();
}

fn jsonGetRuleInfo(rule: JsonRuleType) lang_interface.RuleInfo {
    return switch (rule) {
        .no_duplicate_keys => .{
            .name = "no-duplicate-keys",
            .description = "Disallow duplicate keys in objects",
            .severity = .err,
            .enabled_by_default = true,
        },
        .no_leading_zeros => .{
            .name = "no-leading-zeros",
            .description = "Disallow leading zeros in numbers",
            .severity = .warning,
            .enabled_by_default = true,
        },
        .valid_string_encoding => .{
            .name = "valid-string-encoding",
            .description = "Ensure valid string encoding",
            .severity = .err,
            .enabled_by_default = true,
        },
        .max_depth_exceeded => .{
            .name = "max-depth-exceeded",
            .description = "Maximum nesting depth exceeded",
            .severity = .warning,
            .enabled_by_default = true,
        },
        .large_number_precision => .{
            .name = "large-number-precision",
            .description = "Large number may lose precision",
            .severity = .info,
            .enabled_by_default = false,
        },
        .large_structure => .{
            .name = "large-structure",
            .description = "Structure is unusually large",
            .severity = .info,
            .enabled_by_default = false,
        },
        .deep_nesting => .{
            .name = "deep-nesting",
            .description = "Structure has deep nesting",
            .severity = .info,
            .enabled_by_default = false,
        },
    };
}

fn jsonLintEnum(allocator: std.mem.Allocator, ast: AST, enabled_rules: EnabledRules) ![]lang_interface.Diagnostic {
    var linter = JsonLinter.init(allocator, .{});
    defer linter.deinit();

    const json_diagnostics = try linter.lint(ast, enabled_rules);
    defer {
        for (json_diagnostics) |diag| {
            allocator.free(diag.message);
        }
        allocator.free(json_diagnostics);
    }

    // Convert JSON diagnostics to generic diagnostics
    var diagnostics = std.ArrayList(lang_interface.Diagnostic).init(allocator);
    defer diagnostics.deinit();

    for (json_diagnostics) |json_diag| {
        try diagnostics.append(lang_interface.Diagnostic{
            .rule = try allocator.dupe(u8, json_diag.rule),
            .message = try allocator.dupe(u8, json_diag.message),
            .severity = json_diag.severity, // Already compatible
            .range = json_diag.range,
            .fix = null, // TODO: Convert fix if needed
        });
    }

    return diagnostics.toOwnedSlice();
}

fn jsonGetDefaultRules() EnabledRules {
    return JsonLinter.getDefaultRules();
}

// Interface stub functions for compatibility
// TODO: Delete these stubs once interface is updated to remove batch tokenization support
fn tokenizeStub(allocator: std.mem.Allocator, input: []const u8) ![]lang_interface.StreamToken {
    _ = allocator;
    _ = input;
    return error.NotImplemented; // Use streaming lexer directly instead
}

fn tokenizeChunkStub(allocator: std.mem.Allocator, input: []const u8, start_pos: usize) ![]lang_interface.StreamToken {
    _ = allocator;
    _ = input;
    _ = start_pos;
    return error.NotImplemented; // Use streaming lexer directly instead
}

fn parseStub(allocator: std.mem.Allocator, tokens: []lang_interface.StreamToken) !AST {
    _ = allocator;
    _ = tokens;
    return error.NotImplemented; // Use streaming parser directly instead
}

// Test support
test "JSON module tests" {
    _ = @import("test.zig");
}
