/// ZON Language Module - Self-contained ZON support
///
/// REORGANIZED: Following JSON module structure with subdirectories
/// Each language owns its implementation completely
const std = @import("std");
const Language = @import("../../core/language.zig").Language;

// Import all interface types from single module
const lang_interface = @import("../interface.zig");
const LanguageSupport = lang_interface.LanguageSupport;
const InterfaceLexer = lang_interface.Lexer;
const InterfaceParser = lang_interface.Parser;
const InterfaceFormatter = lang_interface.Formatter;
const InterfaceLinter = lang_interface.Linter;
const InterfaceAnalyzer = lang_interface.Analyzer;
const FormatOptions = lang_interface.FormatOptions;
const Symbol = lang_interface.Symbol;
const InterfaceDiagnostic = lang_interface.Diagnostic;

// Import ZON-specific implementations - all self-contained in subdirectories
const ParserImpl = @import("parser/mod.zig").Parser;
const FormatterImpl = @import("format/mod.zig").Formatter;
const linter_mod = @import("linter/mod.zig");
const LinterImpl = linter_mod.Linter;
const LinterDiagnostic = linter_mod.Diagnostic;
const LinterRuleType = linter_mod.RuleType;
const EnabledRules = linter_mod.EnabledRules;
const analyzer_module = @import("analyzer/mod.zig");
const AnalyzerImpl = analyzer_module.Analyzer;
const AnalyzerSchema = analyzer_module.Schema;
const ZigTypeDefinition = analyzer_module.ZigTypeDefinition;

// Import ZON AST
const ast_mod = @import("ast/mod.zig");
pub const AST = ast_mod.AST;
pub const Node = ast_mod.Node;
pub const NodeKind = ast_mod.NodeKind;

// Direct exports
pub const Parser = ParserImpl;
pub const Formatter = FormatterImpl;
pub const Linter = LinterImpl;
pub const RuleType = LinterRuleType;
pub const Analyzer = AnalyzerImpl;
pub const AnalyzerOptions = AnalyzerImpl.AnalysisOptions;
pub const ParserOptions = ParserImpl.ParserOptions;
pub const Schema = AnalyzerSchema;
pub const Diagnostic = LinterDiagnostic;

// Streaming lexer exports (the new way)
pub const Lexer = @import("lexer/mod.zig").Lexer;
pub const Token = @import("../../token/mod.zig").Token;
pub const TokenKind = @import("token/mod.zig").TokenKind;

// Transform exports
pub const Transform = @import("transform/mod.zig").Pipeline;
pub const Serializer = @import("transform/mod.zig").Serializer;

/// Complete ZON (Zig Object Notation) language support implementation
///
/// This module provides full ZON parsing, formatting, linting, and analysis
/// capabilities using the unified language architecture. ZON is Zig's
/// configuration language, used for build.zig.zon and other config files.
///
/// Features:
/// - High-performance lexing and parsing with error recovery
/// - Configurable formatting with comment preservation
/// - Comprehensive linting with schema validation
/// - Schema extraction and Zig type generation
/// - Performance optimized for config files
/// Get ZON language support instance
pub fn getSupport(allocator: std.mem.Allocator) !lang_interface.LanguageSupport(AST, LinterRuleType) {
    _ = allocator; // Not needed for static interface
    return lang_interface.LanguageSupport(AST, LinterRuleType){
        .language = .zon,
        .lexer = InterfaceLexer{
            .updateTokensFn = null, // Incremental tokenization not implemented
        },
        .parser = InterfaceParser(AST){
            .parseWithBoundariesFn = null, // Boundaries not used for ZON
        },
        .formatter = InterfaceFormatter(AST){
            .formatFn = formatAST,
            .formatRangeFn = null, // Range formatting not implemented for ZON
        },
        .linter = InterfaceLinter(AST, LinterRuleType){
            .ruleInfoFn = zonGetRuleInfo,
            .lintFn = zonLintEnum,
            .getDefaultRulesFn = zonGetDefaultRules,
        },
        .analyzer = InterfaceAnalyzer(AST){
            .extractSymbolsFn = extractSymbols,
            .buildCallGraphFn = null, // Not applicable for ZON
            .findReferencesFn = null, // Not applicable for ZON
        },
        .deinitFn = null,
    };
}

/// Parse ZON source into AST using streaming parser (convenience function)
pub fn parse(allocator: std.mem.Allocator, source: []const u8) !AST {
    var parser = try ParserImpl.init(allocator, source, .{});
    defer parser.deinit();
    return parser.parse();
}

/// Parse ZON source into specific type using AST converter (convenience function)
pub fn parseFromSlice(comptime T: type, allocator: std.mem.Allocator, content: []const u8) !T {
    const converter = @import("ast/converter.zig");
    return converter.parseFromSlice(T, allocator, content);
}

/// Free parsed ZON data (convenience function for compatibility)
pub fn free(allocator: std.mem.Allocator, data: anytype) void {
    // AST converter handles its own memory management
    // For now, this is a no-op for compatibility
    _ = allocator;
    _ = data;
}

/// Validate ZON string and return diagnostics (convenience function)
pub fn lint(allocator: std.mem.Allocator, source: []const u8, rules: EnabledRules) ![]LinterDiagnostic {
    var linter = LinterImpl.init(allocator, .{});
    defer linter.deinit();
    return linter.lintSource(source, rules);
}

/// Validate ZON string with default rules (convenience function for benchmarks)
pub fn validateString(allocator: std.mem.Allocator, content: []const u8) ![]LinterDiagnostic {
    var linter = LinterImpl.init(allocator, .{});
    defer linter.deinit();
    const rules = LinterImpl.getDefaultRules();
    return linter.lintSource(content, rules);
}

/// Extract ZON schema from content (convenience function for benchmarks)
pub fn extractSchema(allocator: std.mem.Allocator, content: []const u8) !AnalyzerSchema {
    var ast = try parse(allocator, content);
    defer ast.deinit();

    var analyzer = AnalyzerImpl.init(allocator, .{});
    return analyzer.extractSchema(ast);
}

/// Format ZON AST (interface function)
pub fn formatAST(allocator: std.mem.Allocator, ast: AST, options: FormatOptions) ![]const u8 {
    // Convert interface options to ZON-specific options
    const zon_options = FormatterImpl.FormatOptions{
        .indent_size = @intCast(options.indent_size),
        .indent_style = switch (options.indent_style) {
            .space => .space,
            .tab => .tab,
        },
        .line_width = options.line_width,
        .preserve_comments = options.preserve_newlines,
        .trailing_comma = options.trailing_comma,
    };

    // Initialize formatter with ZON-specific options
    var formatter = FormatterImpl.init(allocator, zon_options);
    defer formatter.deinit();

    // Format using the AST
    const formatted = try formatter.format(ast);
    return try allocator.dupe(u8, formatted);
}

/// Format ZON source string (convenience function)
pub fn format(allocator: std.mem.Allocator, source: []const u8, options: FormatOptions) ![]const u8 {
    // Convert interface options to ZON-specific options
    const zon_options = FormatterImpl.FormatOptions{
        .indent_size = @intCast(options.indent_size),
        .indent_style = switch (options.indent_style) {
            .space => .space,
            .tab => .tab,
        },
        .line_width = options.line_width,
        .preserve_comments = options.preserve_newlines,
        .trailing_comma = options.trailing_comma,
    };
    var formatter = FormatterImpl.init(allocator, zon_options);
    defer formatter.deinit();
    return formatter.formatSource(source);
}

/// Format ZON string with default options (convenience function for CLI)
pub fn formatString(allocator: std.mem.Allocator, content: []const u8) ![]u8 {
    // Use formatter directly with default ZON options for CLI use
    const options = FormatterImpl.FormatOptions{
        .indent_size = 4,
        .indent_style = .space,
        .line_width = 80,
        .preserve_comments = false,
        .trailing_comma = false,
    };

    var formatter = FormatterImpl.init(allocator, options);
    defer formatter.deinit();
    const formatted = try formatter.formatSource(content);
    return try allocator.dupe(u8, formatted);
}

fn zonGetRuleInfo(rule: LinterRuleType) lang_interface.RuleInfo(LinterRuleType) {
    // Convert ZON RuleInfo to interface RuleInfo
    const zon_info = LinterImpl.RULE_INFO.get(rule);
    return lang_interface.RuleInfo(LinterRuleType){
        .rule = rule,
        .description = zon_info.description,
        .severity = zon_info.severity,
        .enabled_by_default = zon_info.enabled_by_default,
    };
}

fn zonLintEnum(allocator: std.mem.Allocator, ast: AST, rules: EnabledRules) ![]InterfaceDiagnostic(LinterRuleType) {
    var linter = LinterImpl.init(allocator, .{});
    defer linter.deinit();
    const zon_diagnostics = try linter.lint(ast, rules);

    // Convert ZON diagnostics to interface diagnostics
    const interface_diagnostics = try allocator.alloc(InterfaceDiagnostic(LinterRuleType), zon_diagnostics.len);
    for (zon_diagnostics, 0..) |zon_diag, i| {
        interface_diagnostics[i] = InterfaceDiagnostic(LinterRuleType){
            .rule = zon_diag.rule,
            .message = zon_diag.message,
            .severity = switch (zon_diag.severity) {
                .err => .err,
                .warning => .warning,
                .info => .info,
                .hint => .hint,
            },
            .range = zon_diag.span,
        };
    }

    return interface_diagnostics;
}

fn zonGetDefaultRules() EnabledRules {
    return LinterImpl.getDefaultRules();
}

fn extractSymbols(allocator: std.mem.Allocator, ast: AST) ![]Symbol {
    var analyzer = AnalyzerImpl.init(allocator, .{});
    const zon_symbols = try analyzer.extractSymbols(ast);

    // Convert ZON symbols to interface symbols
    const interface_symbols = try allocator.alloc(Symbol, zon_symbols.len);
    for (zon_symbols, 0..) |zon_symbol, i| {
        interface_symbols[i] = Symbol{
            .name = zon_symbol.name,
            .kind = switch (zon_symbol.kind) {
                .field => .property,
                .value => .constant,
                .type_name => .struct_,
                .dependency => .module,
            },
            .range = zon_symbol.span,
        };
    }

    return interface_symbols;
}

// DELETED: Old batch tokenization functions no longer needed with streaming architecture
// The tokenize() and tokenizeChunk() functions that returned []Token arrays
// have been removed. Use streaming parser directly with Parser.init()

// TODO: Phase 3 - Re-enable with new streaming architecture
// /// Tokenize ZON chunk to GenericTokens using VTable adapter
// /// This is the new generic interface for streaming tokenization
// pub fn tokenizeChunkGeneric(allocator: std.mem.Allocator, input: []const u8, start_pos: usize) ![]GenericToken {
//     var lexer = StatefulLexer.init(allocator, .{
//         .allow_comments = true,
//         .allow_trailing_commas = true,
//         .json5_mode = false, // ZON has its own extensions
//         .error_recovery = true,
//     });
//     defer lexer.deinit();
//
//     // Process chunk and get tokens
//     const zon_tokens = try lexer.processChunkToZon(input, start_pos, allocator);
//     defer allocator.free(zon_tokens);
//
//     // Convert to GenericTokens using VTable adapter
//     return TokenVTableAdapter.convertTokensToGeneric(allocator, tokens);
// }
