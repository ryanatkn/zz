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
const ParserImpl = @import("parser/mod.zig").Parser;
const FormatterImpl = @import("format/mod.zig").Formatter;
const linter_mod = @import("linter/mod.zig");
const LinterImpl = linter_mod.Linter;
const Diagnostic = linter_mod.Diagnostic;
const RuleTypeImpl = linter_mod.RuleType;
const EnabledRules = linter_mod.EnabledRules;
const analyzer_module = @import("analyzer/mod.zig");
const AnalyzerImpl = analyzer_module.Analyzer;
const SchemaImpl = analyzer_module.Schema;

// Import JSON AST
const json_ast = @import("ast/mod.zig");
pub const AST = json_ast.AST;
pub const Node = json_ast.Node;
pub const NodeKind = json_ast.NodeKind;

// Direct exports
pub const Parser = ParserImpl;
pub const Formatter = FormatterImpl;
pub const Linter = LinterImpl;
pub const RuleType = RuleTypeImpl;
pub const Analyzer = AnalyzerImpl;
pub const AnalyzerOptions = AnalyzerImpl.AnalyzerOptions;
pub const ParserOptions = ParserImpl.ParserOptions;
pub const Schema = SchemaImpl;

// Streaming lexer exports (the new way)
pub const Lexer = @import("lexer/mod.zig").Lexer;
pub const StreamToken = @import("token/mod.zig").Token;
pub const StreamTokenKind = @import("token/mod.zig").TokenKind;

/// Parse JSON source into AST using streaming parser (convenience function)
pub fn parse(allocator: std.mem.Allocator, source: []const u8) !AST {
    var parser = try ParserImpl.init(allocator, source, .{});
    defer parser.deinit();
    return parser.parse();
}

/// Validate JSON string and return diagnostics (convenience function)
pub fn validate(allocator: std.mem.Allocator, content: []const u8) ![]Diagnostic {
    var linter = LinterImpl.init(allocator, .{});
    defer linter.deinit();
    const rules = LinterImpl.getDefaultRules();
    return linter.lintSource(content, rules);
}

/// Format JSON string directly (convenience function)
/// This is a convenience function for cases where you have raw JSON text
/// and need to format it without first parsing to AST (e.g., CLI tools).
/// For better performance, prefer parse() → format(ast) when you need both parsing and formatting.
pub fn formatString(allocator: std.mem.Allocator, content: []const u8) ![]u8 {
    // Use formatter directly with source for this convenience case
    const options = FormatterImpl.FormatOptions{
        .indent_size = 4,
        .indent_style = .space,
        .line_width = 100,
        .preserve_newlines = false,
        .force_compact = false,
        .trailing_comma = false,
    };

    var formatter = FormatterImpl.init(allocator, options);
    defer formatter.deinit();
    const formatted = try formatter.formatSource(content);
    return try allocator.dupe(u8, formatted);
}

/// Extract JSON schema from source (convenience function)
pub fn extractSchema(allocator: std.mem.Allocator, content: []const u8) !SchemaImpl {
    var ast = try parse(allocator, content);
    defer ast.deinit();

    var analyzer = AnalyzerImpl.init(allocator, .{});
    return analyzer.extractSchema(ast);
}

/// Get JSON statistics from source (convenience function)
pub fn getStatistics(allocator: std.mem.Allocator, content: []const u8) !AnalyzerImpl.Statistics {
    var ast = try parse(allocator, content);
    defer ast.deinit();

    var analyzer = AnalyzerImpl.init(allocator, .{});
    return analyzer.generateStatistics(ast);
}

/// Get JSON language support instance
pub fn getSupport(allocator: std.mem.Allocator) !lang_interface.LanguageSupport(AST, RuleTypeImpl) {
    _ = allocator; // Not needed for static interface
    return lang_interface.LanguageSupport(AST, RuleTypeImpl){
        .language = .json,
        .lexer = InterfaceLexer{
            .updateTokensFn = null, // Incremental tokenization not implemented
        },
        .parser = InterfaceParser(AST){
            .parseWithBoundariesFn = null, // Boundaries not used for JSON
        },
        .formatter = InterfaceFormatter(AST){
            .formatFn = format,
            .formatRangeFn = null, // Range formatting not implemented for JSON
        },
        .linter = InterfaceLinter(AST, RuleTypeImpl){
            .ruleInfoFn = getRuleInfo,
            .lintFn = lintEnum,
            .getDefaultRulesFn = getDefaultRules,
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
    const format_options = FormatterImpl.FormatOptions{
        .indent_size = @intCast(options.indent_size), // Convert u32 to u8
        .indent_style = if (options.indent_style == .space)
            FormatterImpl.FormatOptions.IndentStyle.space
        else
            FormatterImpl.FormatOptions.IndentStyle.tab,
        .line_width = options.line_width,
        .preserve_newlines = options.preserve_newlines,
        .force_compact = false, // JSON-specific default
        .trailing_comma = options.trailing_comma,
    };

    var formatter = FormatterImpl.init(allocator, format_options);
    defer formatter.deinit();
    return formatter.format(ast);
}

/// Extract symbols from JSON AST
pub fn extractSymbols(allocator: std.mem.Allocator, ast: AST) ![]Symbol {
    var analyzer = AnalyzerImpl.init(allocator, .{});

    const extracted_symbols = try analyzer.extractSymbols(ast);
    defer allocator.free(extracted_symbols);

    // Convert JSON symbols to generic symbols (allocate new strings)
    var symbols = std.ArrayList(Symbol).init(allocator);
    defer symbols.deinit();

    for (extracted_symbols) |symbol| {
        try symbols.append(Symbol{
            .name = try allocator.dupe(u8, symbol.name),
            .kind = switch (symbol.kind) {
                .string => .constant,
                .number => .constant,
                .boolean => .constant,
                .null_value => .constant,
                .property => .property,
                .array_element => .constant,
                .object => .struct_,
                .array => .constant,
                .unknown => .constant,
            },
            .range = symbol.range,
            .signature = if (symbol.signature) |sig| try allocator.dupe(u8, sig) else null,
            .documentation = if (symbol.documentation) |doc| try allocator.dupe(u8, doc) else null,
        });
    }

    return symbols.toOwnedSlice();
}

pub fn getRuleInfo(rule: RuleTypeImpl) lang_interface.RuleInfo(RuleTypeImpl) {
    const rule_info = LinterImpl.RULE_INFO.get(rule);
    return lang_interface.RuleInfo(RuleTypeImpl){
        .rule = rule, // Use enum directly instead of string!
        .description = rule_info.description,
        .severity = rule_info.severity,
        .enabled_by_default = rule_info.enabled_by_default,
    };
}

fn lintEnum(allocator: std.mem.Allocator, ast: AST, enabled_rules: EnabledRules) ![]lang_interface.Diagnostic(RuleTypeImpl) {
    var linter = LinterImpl.init(allocator, .{});
    defer linter.deinit();

    const diagnostics = try linter.lint(ast, enabled_rules);
    defer {
        for (diagnostics) |diag| {
            allocator.free(diag.message);
        }
        allocator.free(diagnostics);
    }

    // JSON diagnostics are already the correct type (enum-based)!
    // No conversion needed - just transfer ownership
    const owned_diagnostics = try allocator.alloc(lang_interface.Diagnostic(RuleTypeImpl), diagnostics.len);
    for (diagnostics, 0..) |diag, i| {
        owned_diagnostics[i] = diag; // Direct copy - no rule conversion needed!
    }

    return owned_diagnostics;
}

fn getDefaultRules() EnabledRules {
    return LinterImpl.getDefaultRules();
}

// Test support
test "JSON module tests" {
    _ = @import("test/mod.zig");
}
