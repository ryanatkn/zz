const std = @import("std");
const Language = @import("../../language/detection.zig").Language;
const LanguageSupport = @import("../interface.zig").LanguageSupport;
const Lexer = @import("../interface.zig").Lexer;
const Parser = @import("../interface.zig").Parser;
const Formatter = @import("../interface.zig").Formatter;
const Linter = @import("../interface.zig").Linter;
const Analyzer = @import("../interface.zig").Analyzer;
const Token = @import("../../parser/foundation/types/token.zig").Token;
const AST = @import("../../parser/ast/mod.zig").AST;
const FormatOptions = @import("../interface.zig").FormatOptions;
const Rule = @import("../interface.zig").Rule;
const Symbol = @import("../interface.zig").Symbol;
const Diagnostic = @import("../interface.zig").Diagnostic;

// Import ZON-specific implementations
const ZonLexer = @import("lexer.zig").ZonLexer;
const ZonParser = @import("parser.zig").ZonParser;
const ZonFormatter = @import("formatter.zig").ZonFormatter;
const ZonLinter = @import("linter.zig").ZonLinter;
const ZonAnalyzer = @import("analyzer.zig").ZonAnalyzer;

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
    return LanguageSupport{
        .language = .zon,
        .lexer = Lexer{
            .tokenizeFn = tokenize,
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
            .rules = &ZonLinter.RULES,
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
fn tokenize(allocator: std.mem.Allocator, input: []const u8) ![]Token {
    var lexer = ZonLexer.init(allocator, input, .{});
    defer lexer.deinit();
    return lexer.tokenize();
}

/// Parse ZON tokens into AST
fn parse(allocator: std.mem.Allocator, tokens: []Token) !AST {
    var parser = ZonParser.init(allocator, tokens, .{});
    defer parser.deinit();
    return parser.parse();
}

/// Format ZON AST
fn format(allocator: std.mem.Allocator, ast: AST, options: FormatOptions) ![]const u8 {
    _ = options; // TODO: Convert FormatOptions to ZonFormatOptions
    
    const zon_options = ZonFormatter.ZonFormatOptions{
        .indent_size = 4,
        .indent_style = .space,
        .line_width = 100,
        .preserve_comments = true,
        .trailing_comma = true,
        .compact_small_objects = true,
        .compact_small_arrays = true,
    };
    
    var formatter = ZonFormatter.init(allocator, zon_options);
    defer formatter.deinit();
    return formatter.format(ast);
}

/// Lint ZON AST
fn lint(allocator: std.mem.Allocator, ast: AST, rules: []Rule) ![]Diagnostic {
    _ = rules; // TODO: Convert Rule to ZON rule names
    
    var linter = ZonLinter.init(allocator, .{});
    defer linter.deinit();
    
    // Use all default rules for now
    const enabled_rules: []const []const u8 = &.{};
    const zon_diagnostics = try linter.lint(ast, enabled_rules);
    
    // Convert ZON diagnostics to generic diagnostics
    var diagnostics = std.ArrayList(Diagnostic).init(allocator);
    defer diagnostics.deinit();
    
    for (zon_diagnostics) |zon_diag| {
        const diagnostic = Diagnostic{
            .message = try allocator.dupe(u8, zon_diag.message),
            .span = zon_diag.span,
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
fn extractSymbols(allocator: std.mem.Allocator, ast: AST) ![]Symbol {
    var analyzer = ZonAnalyzer.init(allocator, .{});
    const zon_symbols = try analyzer.extractSymbols(ast);
    
    // Convert ZON symbols to generic symbols
    var symbols = std.ArrayList(Symbol).init(allocator);
    defer symbols.deinit();
    
    for (zon_symbols) |zon_symbol| {
        const symbol = Symbol{
            .name = try allocator.dupe(u8, zon_symbol.name),
            .kind = switch (zon_symbol.kind) {
                .field => .variable,
                .value => .constant,
                .type_name => .type,
                .dependency => .module,
            },
            .span = zon_symbol.span,
            .documentation = null,
        };
        try symbols.append(symbol);
    }
    
    return symbols.toOwnedSlice();
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
    return ZonFormatter.formatZonString(allocator, zon_content, .{});
}

/// Validate ZON string and return diagnostics
pub fn validateZonString(allocator: std.mem.Allocator, zon_content: []const u8) ![]ZonLinter.Diagnostic {
    return ZonLinter.lintZonString(allocator, zon_content, &.{});
}

/// Extract schema from ZON string
pub fn extractZonSchema(allocator: std.mem.Allocator, zon_content: []const u8) !ZonAnalyzer.ZonSchema {
    return ZonAnalyzer.extractSchemaFromString(allocator, zon_content);
}

/// Generate Zig type definition from ZON
pub fn generateZigTypes(allocator: std.mem.Allocator, zon_content: []const u8, type_name: []const u8) !ZonAnalyzer.ZigTypeDefinition {
    var schema = try extractZonSchema(allocator, zon_content);
    defer schema.deinit();
    
    var analyzer = ZonAnalyzer.init(allocator, .{});
    return analyzer.generateZigTypeDefinition(schema, type_name);
}

// ============================================================================
// Compatibility Functions (for replacing old ZON parser)
// ============================================================================

/// Parse ZON content to a specific type (compatibility with old parser)
pub fn parseFromSlice(comptime T: type, allocator: std.mem.Allocator, content: []const u8) !T {
    return ZonParser.parseFromSlice(T, allocator, content);
}

/// Free parsed ZON data (compatibility with old parser)
pub fn free(allocator: std.mem.Allocator, parsed_data: anytype) void {
    return ZonParser.free(allocator, parsed_data);
}

