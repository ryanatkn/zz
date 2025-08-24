const std = @import("std");
const Language = @import("../../core/language.zig").Language;
// Import ZON-specific AST
const zon_ast = @import("ast.zig");
const AST = zon_ast.AST;

// Import all interface types from single module
const lang_interface = @import("../interface.zig");
const LanguageSupport = lang_interface.LanguageSupport;
const Lexer = lang_interface.Lexer;
const Parser = lang_interface.Parser;
const Formatter = lang_interface.Formatter;
const Linter = lang_interface.Linter;
const Analyzer = lang_interface.Analyzer;
const FormatOptions = lang_interface.FormatOptions;
const Rule = lang_interface.Rule;
const Symbol = lang_interface.Symbol;
const Diagnostic = lang_interface.Diagnostic;
const ZonFormatterType = @import("formatter.zig").ZonFormatter;
const ZonLinterImpl = @import("linter.zig").ZonLinter;
const ZonRuleType = @import("linter.zig").ZonRuleType;
const EnabledRules = @import("linter.zig").EnabledRules;

// Module-specific components
const ZonParserImpl = @import("parser.zig");
const ZonAnalyzer = @import("analyzer.zig").ZonAnalyzer;
const AstConverter = @import("ast_converter.zig");
const ZonSerializer = @import("serializer.zig");
const ZonDiagnostic = @import("linter.zig").Diagnostic;
const ZonSchema = @import("analyzer.zig").ZonAnalyzer.ZonSchema;
const ZigTypeDefinition = @import("analyzer.zig").ZonAnalyzer.ZigTypeDefinition;

// VTable adapter for generic streaming - DISABLED until Phase 3
// const ZonTokenVTableAdapter = @import("vtable_adapter.zig").ZonTokenVTableAdapter;
// Removed old transform imports - using new architecture

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
pub fn getSupport(allocator: std.mem.Allocator) !lang_interface.LanguageSupport(AST, ZonRuleType) {
    _ = allocator; // Not needed for static interface
    return lang_interface.LanguageSupport(AST, ZonRuleType){
        .language = .zon,
        .lexer = Lexer{
            .updateTokensFn = null, // Incremental tokenization not implemented
        },
        .parser = Parser(AST){
            .parseWithBoundariesFn = null, // Boundaries not used for ZON
        },
        .formatter = Formatter(AST){
            .formatFn = format,
            .formatRangeFn = null, // Range formatting not implemented for ZON
        },
        .linter = Linter(AST, ZonRuleType){
            .ruleInfoFn = zonGetRuleInfo,
            .lintFn = zonLintEnum,
            .getDefaultRulesFn = zonGetDefaultRules,
        },
        .analyzer = Analyzer(AST){
            .extractSymbolsFn = extractSymbols,
            .buildCallGraphFn = null, // Not applicable for ZON
            .findReferencesFn = null, // Not applicable for ZON
        },
        .deinitFn = null,
    };
}

// DELETED: Old batch tokenization functions no longer needed with streaming architecture
// The tokenize() and tokenizeChunk() functions that returned []Token arrays
// have been removed. Use streaming parser directly with ZonParser.init()

// TODO: Phase 3 - Re-enable with new streaming architecture
// /// Tokenize ZON chunk to GenericStreamTokens using VTable adapter
// /// This is the new generic interface for streaming tokenization
// pub fn tokenizeChunkGeneric(allocator: std.mem.Allocator, input: []const u8, start_pos: usize) ![]GenericStreamToken {
//     var lexer = StatefulZonLexer.init(allocator, .{
//         .allow_comments = true,
//         .allow_trailing_commas = true,
//         .json5_mode = false, // ZON has its own extensions
//         .error_recovery = true,
//     });
//     defer lexer.deinit();
//
//     // Process chunk and get ZonTokens
//     const zon_tokens = try lexer.processChunkToZon(input, start_pos, allocator);
//     defer allocator.free(zon_tokens);
//
//     // Convert to GenericStreamTokens using VTable adapter
//     return ZonTokenVTableAdapter.convertZonTokensToGeneric(allocator, zon_tokens);
// }

/// Parse ZON source into AST using streaming parser
pub fn parse(allocator: std.mem.Allocator, source: []const u8) !AST {
    var parser = try ZonParserImpl.ZonParser.init(allocator, source, .{});
    defer parser.deinit();
    return parser.parse();
}

// DELETED: Old parseInterface function that used token arrays
// Streaming parser doesn't use pre-tokenized arrays
// Use parse() function directly which calls ZonParser.init() with source

/// Format ZON AST
fn format(allocator: std.mem.Allocator, ast: AST, options: FormatOptions) ![]const u8 {
    // Convert generic FormatOptions to ZON-specific options
    const zon_options = ZonFormatterType.ZonFormatOptions{
        .indent_size = @intCast(options.indent_size), // Convert u32 to u8
        .indent_style = if (options.indent_style == .space)
            ZonFormatterType.ZonFormatOptions.IndentStyle.space
        else
            ZonFormatterType.ZonFormatOptions.IndentStyle.tab,
        .line_width = options.line_width,
        .preserve_comments = options.preserve_newlines, // Map to preserve_comments
        .trailing_comma = options.trailing_comma,
        .compact_small_objects = true, // ZON-specific default
        .compact_small_arrays = true, // ZON-specific default
    };

    var formatter = ZonFormatterType.init(allocator, zon_options);
    defer formatter.deinit();
    // Use the source text stored in the AST
    return formatter.format(ast);
}

/// Extract symbols from ZON AST
pub fn extractSymbols(allocator: std.mem.Allocator, ast: AST) ![]Symbol {
    var analyzer = ZonAnalyzer.init(allocator, .{});
    defer analyzer.deinit();

    const zon_symbols = try analyzer.extractSymbols(ast);
    defer analyzer.freeSymbols(zon_symbols);

    // Convert ZON symbols to generic symbols (allocate new strings)
    var symbols = std.ArrayList(Symbol).init(allocator);
    defer symbols.deinit();

    for (zon_symbols) |zon_symbol| {
        const symbol = Symbol{
            .name = try allocator.dupe(u8, zon_symbol.name),
            .kind = switch (zon_symbol.kind) {
                .field => .variable,
                .value => .constant,
                .type_name => .struct_,
                .dependency => .module,
            },
            .range = zon_symbol.span,
            .documentation = null,
        };
        try symbols.append(symbol);
    }

    return symbols.toOwnedSlice();
}

/// Free symbols returned by extractSymbols
pub fn freeSymbols(allocator: std.mem.Allocator, symbols: []Symbol) void {
    for (symbols) |symbol| {
        allocator.free(symbol.name);
    }
    allocator.free(symbols);
}

// ============================================================================
// Convenience Functions
// ============================================================================

/// Parse ZON string directly
pub fn parseZonString(allocator: std.mem.Allocator, zon_content: []const u8) !AST {
    // Use streaming parser directly (3-arg pattern)
    return parse(allocator, zon_content);
}

/// Format ZON string directly
pub fn formatZonString(allocator: std.mem.Allocator, zon_content: []const u8) ![]u8 {
    // Use formatter directly with source since AST doesn't have source
    const zon_options = ZonFormatterType.ZonFormatOptions{
        .indent_size = 4,
        .indent_style = ZonFormatterType.ZonFormatOptions.IndentStyle.space,
        .line_width = 100,
        .preserve_comments = false,
        .trailing_comma = true,
        .compact_small_objects = false,
        .compact_small_arrays = false,
    };

    var formatter = ZonFormatterType.init(allocator, zon_options);
    defer formatter.deinit();
    const formatted = try formatter.formatSource(zon_content);
    return try allocator.dupe(u8, formatted);
}

/// Validate ZON string and return diagnostics
pub fn validateZonString(allocator: std.mem.Allocator, zon_content: []const u8) ![]ZonDiagnostic {
    var ast = try parseZonString(allocator, zon_content);
    defer ast.deinit();

    var linter = ZonLinterImpl.init(allocator, .{});
    defer linter.deinit();

    // Use all default enabled rules
    const enabled_rules = ZonLinterImpl.getDefaultRules();
    return linter.lint(ast, enabled_rules);
}

/// Extract schema from ZON string
pub fn extractZonSchema(allocator: std.mem.Allocator, zon_content: []const u8) !ZonSchema {
    var ast = try parseZonString(allocator, zon_content);
    defer ast.deinit();

    var analyzer = ZonAnalyzer.init(allocator, .{});
    return analyzer.extractSchema(ast);
}

/// Generate Zig type definition from ZON
pub fn generateZigTypes(allocator: std.mem.Allocator, zon_content: []const u8, type_name: []const u8) !ZigTypeDefinition {
    var schema = try extractZonSchema(allocator, zon_content);
    defer schema.deinit();

    var analyzer = ZonAnalyzer.init(allocator, .{});
    return analyzer.generateZigTypeDefinition(schema, type_name);
}

// ============================================================================
// Public Exports
// ============================================================================

// Re-export core components for external use (using original imports to avoid circular references)
pub const ZonParser = @import("parser.zig").ZonParser;
pub const ParserOptions = @import("parser.zig").ZonParser.ParserOptions;
pub const ZonValidator = @import("validator.zig").ZonValidator;

// Export language-specific types for interface
pub const RuleType = ZonRuleType;
pub const ZonFormatter = ZonFormatterType;

// Transform pipeline components (using module-scope reference)
const transform_mod = @import("transform.zig");
pub const transform = transform_mod;
pub const ZonTransformPipeline = transform_mod.ZonTransformPipeline;
pub const ZonLexicalTransform = transform_mod.ZonLexicalTransform;
pub const ZonSyntacticTransform = transform_mod.ZonSyntacticTransform;

// ============================================================================
// Compatibility Functions (for replacing old ZON parser)
// ============================================================================

/// Parse ZON content to a specific type (compatibility with old parser)
pub fn parseFromSlice(comptime T: type, allocator: std.mem.Allocator, content: []const u8) !T {
    return AstConverter.parseFromSlice(T, allocator, content);
}

/// Free parsed ZON data (compatibility with old parser)
pub fn free(allocator: std.mem.Allocator, parsed_data: anytype) void {
    return AstConverter.free(allocator, parsed_data);
}

/// Serialize a value to ZON format
pub fn stringify(allocator: std.mem.Allocator, value: anytype) ![]const u8 {
    return ZonSerializer.stringify(allocator, value);
}

/// Serialize with custom options
pub fn stringifyWithOptions(allocator: std.mem.Allocator, value: anytype, options: ZonSerializer.SerializeOptions) ![]const u8 {
    return ZonSerializer.stringifyWithOptions(allocator, value, options);
}

// Interface functions for the new generic linter

/// Get rule information for a specific ZON rule
fn zonGetRuleInfo(rule: ZonRuleType) lang_interface.RuleInfo(ZonRuleType) {
    const rule_info = ZonLinterImpl.RULE_INFO.get(rule);
    return lang_interface.RuleInfo(ZonRuleType){
        .rule = rule, // Use enum directly instead of string!
        .description = rule_info.description,
        .severity = rule_info.severity,
        .enabled_by_default = rule_info.enabled_by_default,
    };
}

/// Lint with enum-based rules (new interface)
fn zonLintEnum(allocator: std.mem.Allocator, ast: AST, enabled_rules: EnabledRules) ![]lang_interface.Diagnostic(ZonRuleType) {
    var linter = ZonLinterImpl.init(allocator, .{});
    defer linter.deinit();

    const diagnostics = try linter.lint(ast, enabled_rules);

    // Convert to interface diagnostics (enum-based)
    var result = try allocator.alloc(lang_interface.Diagnostic(ZonRuleType), diagnostics.len);
    for (diagnostics, 0..) |diag, i| {
        result[i] = lang_interface.Diagnostic(ZonRuleType){
            .rule = diag.rule, // Direct enum usage - no conversion needed!
            .message = diag.message,
            .severity = switch (diag.severity) {
                .err => .err,
                .warning => .warning,
                .info => .info,
                .hint => .hint,
            },
            .range = diag.span,
            .fix = null, // TODO: Convert fix if needed
        };
    }
    allocator.free(diagnostics); // Free original diagnostics
    return result;
}

/// Get default rules for ZON
fn zonGetDefaultRules() EnabledRules {
    return ZonLinterImpl.getDefaultRules();
}
