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

// Import ZON-specific implementations (moved to public exports section)

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
            .rules = &@import("linter.zig").ZonLinter.RULES,
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
    var lexer = @import("lexer.zig").ZonLexer.init(allocator, input, .{});
    defer lexer.deinit();
    return lexer.tokenize();
}

/// Parse ZON tokens into AST
pub fn parse(allocator: std.mem.Allocator, tokens: []Token) !AST {
    var parser = @import("parser.zig").ZonParser.init(allocator, tokens, .{});
    // Don't deinit parser here - it would free allocated texts that AST nodes reference
    // The AST now owns these allocations and will free them when it's deinitialized
    const ast = try parser.parse();
    // Transfer ownership of allocated texts to AST
    // For now, we'll leak the parser's allocated_texts array itself (small leak)
    // TODO: Improve AST to track these allocations
    parser.allocated_texts.deinit(); // Just free the array, not the strings
    parser.errors.deinit(); // Free errors array  
    return ast;
}

/// Format ZON AST
fn format(allocator: std.mem.Allocator, ast: AST, options: FormatOptions) ![]const u8 {
    _ = options; // TODO: Convert FormatOptions to ZonFormatOptions
    
    const zon_options = @import("formatter.zig").ZonFormatter.ZonFormatOptions{
        .indent_size = 4,
        .indent_style = .space,
        .line_width = 100,
        .preserve_comments = true,
        .trailing_comma = true,
        .compact_small_objects = true,
        .compact_small_arrays = true,
    };
    
    var formatter = @import("formatter.zig").ZonFormatter.init(allocator, zon_options);
    defer formatter.deinit();
    return formatter.format(ast);
}

/// Lint ZON AST
fn lint(allocator: std.mem.Allocator, ast: AST, rules: []const Rule) ![]Diagnostic {
    _ = rules; // TODO: Convert Rule to ZON rule names
    
    var linter = @import("linter.zig").ZonLinter.init(allocator, .{});
    defer linter.deinit();
    
    // Use all default rules for now
    const enabled_rules: []const []const u8 = &.{};
    const zon_diagnostics = try linter.lint(ast, enabled_rules);
    
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
    var analyzer = @import("analyzer.zig").ZonAnalyzer.init(allocator, .{});
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
pub fn validateZonString(allocator: std.mem.Allocator, zon_content: []const u8) ![]@import("linter.zig").ZonLinter.Diagnostic {
    var ast = try parseZonString(allocator, zon_content);
    defer ast.deinit();
    
    var linter = @import("linter.zig").ZonLinter.init(allocator, .{});
    defer linter.deinit();
    
    // Use all available rules
    const enabled_rules: []const []const u8 = &.{};
    return linter.lint(ast, enabled_rules);
}

/// Extract schema from ZON string
pub fn extractZonSchema(allocator: std.mem.Allocator, zon_content: []const u8) !@import("analyzer.zig").ZonAnalyzer.ZonSchema {
    var ast = try parseZonString(allocator, zon_content);
    defer ast.deinit();
    
    var analyzer = @import("analyzer.zig").ZonAnalyzer.init(allocator, .{});
    return analyzer.extractSchema(ast);
}

/// Generate Zig type definition from ZON
pub fn generateZigTypes(allocator: std.mem.Allocator, zon_content: []const u8, type_name: []const u8) !@import("analyzer.zig").ZonAnalyzer.ZigTypeDefinition {
    var schema = try extractZonSchema(allocator, zon_content);
    defer schema.deinit();
    
    var analyzer = @import("analyzer.zig").ZonAnalyzer.init(allocator, .{});
    return analyzer.generateZigTypeDefinition(schema, type_name);
}

// ============================================================================
// Public Exports
// ============================================================================

// Core modules
pub const ZonLexer = @import("lexer.zig").ZonLexer;
pub const ZonParser = @import("parser.zig").ZonParser;
pub const ZonFormatter = @import("formatter.zig").ZonFormatter;
pub const ZonLinter = @import("linter.zig").ZonLinter;
pub const ZonAnalyzer = @import("analyzer.zig").ZonAnalyzer;

// New modular components
pub const AstConverter = @import("ast_converter.zig").AstConverter;
pub const ZonSerializer = @import("serializer.zig").ZonSerializer;
pub const ZonValidator = @import("validator.zig").ZonValidator;

// ============================================================================
// Compatibility Functions (for replacing old ZON parser)
// ============================================================================

/// Parse ZON content to a specific type (compatibility with old parser)
pub fn parseFromSlice(comptime T: type, allocator: std.mem.Allocator, content: []const u8) !T {
    return @import("ast_converter.zig").parseFromSlice(T, allocator, content);
}

/// Free parsed ZON data (compatibility with old parser)
pub fn free(allocator: std.mem.Allocator, parsed_data: anytype) void {
    return @import("ast_converter.zig").free(allocator, parsed_data);
}

/// Serialize a value to ZON format
pub fn stringify(allocator: std.mem.Allocator, value: anytype) ![]const u8 {
    return @import("serializer.zig").stringify(allocator, value);
}

/// Serialize with custom options
pub fn stringifyWithOptions(allocator: std.mem.Allocator, value: anytype, options: ZonSerializer.SerializeOptions) ![]const u8 {
    return @import("serializer.zig").stringifyWithOptions(allocator, value, options);
}

