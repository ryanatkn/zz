const std = @import("std");
const Language = @import("../../core/language.zig").Language;
const Token = @import("../../parser/foundation/types/token.zig").Token;
const AST = @import("../../ast/mod.zig").AST;

// Import all interface types from single module
const lang_interface = @import("../interface.zig");
const LanguageSupport = lang_interface.LanguageSupport;
const Lexer = lang_interface.Lexer;
const Parser = lang_interface.Parser;
const Formatter = lang_interface.Formatter;
const FormatOptions = lang_interface.FormatOptions;

/// Zig language support
///
/// This module provides Zig parsing, formatting, and analysis.
/// For formatting, we delegate to the external `zig fmt` command
/// when available for best compatibility.
/// Get Zig language support instance
pub fn getSupport(allocator: std.mem.Allocator) !LanguageSupport {
    _ = allocator;

    return LanguageSupport{
        .language = .zig,
        .lexer = Lexer{
            .tokenizeFn = tokenize,
            .tokenizeChunkFn = tokenizeChunk,
            .updateTokensFn = null, // TODO: Implement incremental tokenization
        },
        .parser = Parser{
            .parseFn = parse,
            .parseWithBoundariesFn = null, // TODO: Implement boundary-aware parsing
        },
        .formatter = Formatter{
            .formatFn = format,
            .formatRangeFn = null, // TODO: Implement range formatting
        },
        .linter = null, // TODO: Implement Zig linter
        .analyzer = null, // TODO: Implement Zig analyzer
        .deinitFn = null,
    };
}

/// Tokenize Zig source code
fn tokenize(allocator: std.mem.Allocator, input: []const u8) ![]Token {
    // TODO: Implement Zig tokenization using stratified parser
    // For now, return empty token list
    _ = input;
    var tokens = std.ArrayList(Token).init(allocator);
    return tokens.toOwnedSlice();
}

/// Tokenize Zig source code chunk for streaming
fn tokenizeChunk(allocator: std.mem.Allocator, input: []const u8, start_pos: usize) ![]Token {
    // Stub implementation - delegate to main tokenize and adjust positions
    const tokens = try tokenize(allocator, input);
    for (tokens) |*token| {
        token.span.start += start_pos;
        token.span.end += start_pos;
    }
    return tokens;
}

/// Parse Zig tokens into AST
fn parse(allocator: std.mem.Allocator, tokens: []Token) !AST {
    // TODO: Implement Zig parsing
    // Consider using std.zig.Ast for compatibility with official parser
    _ = tokens;
    return AST.init(allocator);
}

/// Format Zig AST
fn format(allocator: std.mem.Allocator, ast: AST, options: FormatOptions) ![]const u8 {
    // TODO: Delegate to external `zig fmt` command when available
    // Fallback to internal formatting if zig not available
    _ = ast;
    _ = options;
    return allocator.dupe(u8, "// Zig formatting not yet implemented\n");
}

// TODO: Phase 2 Implementation Tasks for Zig:
// 1. Implement Zig tokenization
//    - Zig keywords (pub, fn, const, var, struct, enum, union, etc.)
//    - Zig operators and literals
//    - String literals and character literals
//    - Comptime expressions and builtins
//    - Comments (both // and //!)
//
// 2. Implement Zig parsing
//    - Consider integration with std.zig.Ast for compatibility
//    - Function declarations with Zig-specific features
//    - Struct, enum, union declarations
//    - Comptime constructs
//    - Error handling syntax (try, catch, defer, errdefer)
//    - Generic types and functions
//
// 3. Implement Zig formatter
//    - Primary strategy: delegate to external `zig fmt` command
//    - Fallback: internal formatter using stratified parser
//    - Handle temporary file creation for external command
//    - Preserve original on formatting errors
//    - Performance target: <50ms for typical files
//
// 4. Implement Zig linter (optional)
//    - Zig best practices (naming conventions, etc.)
//    - Performance-related suggestions
//    - Memory safety checks beyond compiler
//    - Code quality metrics
//
// 5. Implement Zig analyzer (optional)
//    - Extract function signatures and documentation
//    - Analyze comptime evaluation potential
//    - Dependency analysis for build systems
//    - Generate documentation from code structure
