const std = @import("std");
const Language = @import("../../core/language.zig").Language;
const Token = @import("../../parser_old/foundation/types/token.zig").Token;
const AST = @import("../../ast_old/mod.zig").AST;

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

// Module-specific components
const ZonLexer = @import("lexer.zig").ZonLexer;
const ZonParserImpl = @import("parser.zig");
const ZonAnalyzer = @import("analyzer.zig").ZonAnalyzer;
const AstConverter = @import("ast_converter.zig");
const ZonSerializer = @import("serializer.zig");
const ZonDiagnostic = @import("linter.zig").ZonLinter.Diagnostic;
const ZonSchema = @import("analyzer.zig").ZonAnalyzer.ZonSchema;
const ZigTypeDefinition = @import("analyzer.zig").ZonAnalyzer.ZigTypeDefinition;

// VTable adapter for generic streaming - DISABLED until Phase 3
// const ZonTokenVTableAdapter = @import("vtable_adapter.zig").ZonTokenVTableAdapter;
// const GenericStreamToken = @import("../../transform_old/streaming/generic_stream_token.zig").GenericStreamToken;
// const StatefulZonLexer = @import("stateful_lexer.zig").StatefulZonLexer;
// const StatefulLexer = @import("../../transform_old/streaming/stateful_lexer.zig").StatefulLexer;

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
pub fn getSupport(allocator: std.mem.Allocator) !LanguageSupport {
    _ = allocator; // Not needed for static interface
    return LanguageSupport{
        .language = .zon,
        .lexer = Lexer{
            .tokenizeFn = tokenize,
            .tokenizeChunkFn = tokenizeChunk,
            .updateTokensFn = null, // TODO: Implement incremental tokenization
        },
        .parser = Parser{
            .parseFn = parse,
            .parseWithBoundariesFn = null, // Boundaries not used for ZON
        },
        .formatter = Formatter{
            .formatFn = format,
            .formatRangeFn = null, // Range formatting not implemented for ZON
        },
        .linter = Linter{
            .rules = &ZonLinterImpl.RULES,
            .lintFn = lint,
        },
        .analyzer = Analyzer{
            .extractSymbolsFn = extractSymbols,
            .buildCallGraphFn = null, // Not applicable for ZON
            .findReferencesFn = null, // Not applicable for ZON
        },
        .deinitFn = null,
    };
}

/// Tokenize ZON source code
pub fn tokenize(allocator: std.mem.Allocator, input: []const u8) ![]Token {
    var lexer = ZonLexer.init(allocator, input, .{});
    defer lexer.deinit();
    return lexer.tokenize();
}

/// Tokenize ZON source code chunk for streaming
pub fn tokenizeChunk(allocator: std.mem.Allocator, input: []const u8, start_pos: usize) ![]Token {
    var lexer = ZonLexer.init(allocator, input, .{});
    defer lexer.deinit();

    const tokens = try lexer.tokenize();

    // Adjust token positions for the start_pos offset
    for (tokens) |*token| {
        token.span.start += start_pos;
        token.span.end += start_pos;
    }

    return tokens;
}

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

/// Parse ZON tokens into AST
pub fn parse(allocator: std.mem.Allocator, tokens: []Token) !AST {
    // Use the convenience function from parser module which handles cleanup
    return ZonParserImpl.parse(allocator, tokens);
}

/// Format ZON AST
fn format(allocator: std.mem.Allocator, ast: AST, options: FormatOptions) ![]const u8 {
    // Convert generic FormatOptions to ZON-specific options
    const zon_options = ZonFormatterType.ZonFormatOptions{
        .indent_size = @intCast(options.indent_size), // Convert u32 to u8
        .indent_style = if (options.indent_style == .space)
            ZonFormatterType.IndentStyle.space
        else
            ZonFormatterType.IndentStyle.tab,
        .line_width = options.line_width,
        .preserve_comments = options.preserve_newlines, // Map to preserve_comments
        .trailing_comma = options.trailing_comma,
        .compact_small_objects = true, // ZON-specific default
        .compact_small_arrays = true, // ZON-specific default
    };

    var formatter = ZonFormatterType.init(allocator, zon_options);
    defer formatter.deinit();
    return formatter.format(ast);
}

/// Lint ZON AST
fn lint(allocator: std.mem.Allocator, ast: AST, rules: []const Rule) ![]Diagnostic {
    var linter = ZonLinterImpl.init(allocator, .{});
    defer linter.deinit();

    // Convert generic rules to ZON rule names
    var enabled_rules = std.ArrayList([]const u8).init(allocator);
    defer enabled_rules.deinit();

    for (rules) |rule| {
        // Map generic rule names to ZON-specific ones
        const zon_rule = mapRuleToZon(rule.name);
        if (zon_rule) |r| {
            try enabled_rules.append(r);
        }
    }

    // If no rules specified, use all defaults
    const rules_to_use = if (enabled_rules.items.len > 0)
        enabled_rules.items
    else
        &[_][]const u8{};

    const zon_diagnostics = try linter.lint(ast, rules_to_use);

    // Convert ZON diagnostics to generic diagnostics
    var diagnostics = std.ArrayList(Diagnostic).init(allocator);
    defer diagnostics.deinit();

    for (zon_diagnostics) |zon_diag| {
        const diagnostic = Diagnostic{
            .rule = try allocator.dupe(u8, zon_diag.rule_name),
            .message = try allocator.dupe(u8, zon_diag.message),
            .range = zon_diag.span,
            .severity = switch (zon_diag.severity) {
                .@"error" => .@"error",
                .warning => .warning,
                .info => .info,
                .hint => .hint,
            },
        };
        try diagnostics.append(diagnostic);
    }

    return diagnostics.toOwnedSlice();
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
    const tokens = try tokenize(allocator, zon_content);
    defer allocator.free(tokens);
    return parse(allocator, tokens);
}

/// Format ZON string directly
pub fn formatZonString(allocator: std.mem.Allocator, zon_content: []const u8) ![]const u8 {
    var ast = try parseZonString(allocator, zon_content);
    defer ast.deinit();

    const default_options = FormatOptions{
        .indent_size = 4,
        .indent_style = .space,
        .line_width = 100,
        .preserve_newlines = false,
        .trailing_comma = true,
        .sort_keys = false,
        .quote_style = .double,
    };

    return format(allocator, ast, default_options);
}

/// Validate ZON string and return diagnostics
pub fn validateZonString(allocator: std.mem.Allocator, zon_content: []const u8) ![]ZonDiagnostic {
    var ast = try parseZonString(allocator, zon_content);
    defer ast.deinit();

    var linter = ZonLinterImpl.init(allocator, .{});
    defer linter.deinit();

    // Use all available rules
    const enabled_rules: []const []const u8 = &.{};
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
pub const ZonValidator = @import("validator.zig").ZonValidator;

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

/// Map generic rule names to ZON-specific ones
fn mapRuleToZon(rule_name: []const u8) ?[]const u8 {
    // Common mappings
    if (std.mem.eql(u8, rule_name, "no-unused")) return "no-unused-fields";
    if (std.mem.eql(u8, rule_name, "valid-syntax")) return "valid-zon-syntax";
    if (std.mem.eql(u8, rule_name, "no-duplicate")) return "no-duplicate-fields";
    if (std.mem.eql(u8, rule_name, "required-fields")) return "required-fields";

    // If it's already a ZON rule name, use it directly
    const zon_rules = ZonLinterImpl.RULES;
    for (zon_rules) |zon_rule| {
        if (std.mem.eql(u8, rule_name, zon_rule.name)) {
            return zon_rule.name;
        }
    }

    return null;
}
