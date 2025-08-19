const std = @import("std");

// Import foundation types from stratified parser
const Token = @import("../parser/foundation/types/token.zig").Token;
const Span = @import("../parser/foundation/types/span.zig").Span;
const AST = @import("../ast/mod.zig").AST;
const Language = @import("../core/language.zig").Language;

/// Core language support interface that all languages must implement
pub const LanguageSupport = struct {
    /// Language identifier
    language: Language,

    /// Lexical tokenizer
    lexer: Lexer,

    /// AST parser
    parser: Parser,

    /// Code formatter
    formatter: Formatter,

    /// Optional linter
    linter: ?Linter = null,

    /// Optional semantic analyzer
    analyzer: ?Analyzer = null,

    /// Cleanup function
    deinitFn: ?*const fn (allocator: std.mem.Allocator) void = null,

    pub fn deinit(self: LanguageSupport, allocator: std.mem.Allocator) void {
        if (self.deinitFn) |deinit_fn| {
            deinit_fn(allocator);
        }
    }
};

/// Lexical tokenization interface
pub const Lexer = struct {
    /// Tokenize input into stream of tokens
    tokenizeFn: *const fn (allocator: std.mem.Allocator, input: []const u8) anyerror![]Token,

    /// Streaming tokenization for chunk-based processing (required for TokenIterator)
    tokenizeChunkFn: *const fn (allocator: std.mem.Allocator, input: []const u8, start_pos: usize) anyerror![]Token,

    /// Optional incremental tokenization for editor use
    updateTokensFn: ?*const fn (allocator: std.mem.Allocator, tokens: []Token, edit: Edit) anyerror!TokenDelta,

    pub fn tokenize(self: Lexer, allocator: std.mem.Allocator, input: []const u8) ![]Token {
        return self.tokenizeFn(allocator, input);
    }

    pub fn tokenizeChunk(self: Lexer, allocator: std.mem.Allocator, input: []const u8, start_pos: usize) ![]Token {
        return self.tokenizeChunkFn(allocator, input, start_pos);
    }

    pub fn updateTokens(self: Lexer, allocator: std.mem.Allocator, tokens: []Token, edit: Edit) !?TokenDelta {
        if (self.updateTokensFn) |update_fn| {
            return update_fn(allocator, tokens, edit);
        }
        return null;
    }
};

/// AST parsing interface
pub const Parser = struct {
    /// Parse tokens into AST
    parseFn: *const fn (allocator: std.mem.Allocator, tokens: []Token) anyerror!AST,

    /// Optional parsing with pre-computed boundaries for optimization
    parseWithBoundariesFn: ?*const fn (allocator: std.mem.Allocator, tokens: []Token, boundaries: []Boundary) anyerror!AST,

    pub fn parse(self: Parser, allocator: std.mem.Allocator, tokens: []Token) !AST {
        return self.parseFn(allocator, tokens);
    }

    pub fn parseWithBoundaries(self: Parser, allocator: std.mem.Allocator, tokens: []Token, boundaries: []Boundary) !?AST {
        if (self.parseWithBoundariesFn) |parse_fn| {
            return parse_fn(allocator, tokens, boundaries);
        }
        return null;
    }
};

/// Code formatting interface
pub const Formatter = struct {
    /// Format AST back to source code
    formatFn: *const fn (allocator: std.mem.Allocator, ast: AST, options: FormatOptions) anyerror![]const u8,

    /// Optional range formatting for editor integration
    formatRangeFn: ?*const fn (allocator: std.mem.Allocator, ast: AST, range: Range, options: FormatOptions) anyerror![]const u8,

    pub fn format(self: Formatter, allocator: std.mem.Allocator, ast: AST, options: FormatOptions) ![]const u8 {
        return self.formatFn(allocator, ast, options);
    }

    pub fn formatRange(self: Formatter, allocator: std.mem.Allocator, ast: AST, range: Range, options: FormatOptions) !?[]const u8 {
        if (self.formatRangeFn) |format_fn| {
            return format_fn(allocator, ast, range, options);
        }
        return null;
    }
};

/// Optional linting interface
pub const Linter = struct {
    /// Available linting rules
    rules: []const Rule,

    /// Run linting on AST
    lintFn: *const fn (allocator: std.mem.Allocator, ast: AST, rules: []const Rule) anyerror![]Diagnostic,

    pub fn lint(self: Linter, allocator: std.mem.Allocator, ast: AST, enabled_rules: []const Rule) ![]Diagnostic {
        return self.lintFn(allocator, ast, enabled_rules);
    }

    pub fn getAllRules(self: Linter) []const Rule {
        return self.rules;
    }
};

/// Optional semantic analysis interface
pub const Analyzer = struct {
    /// Extract symbols (functions, types, variables)
    extractSymbolsFn: *const fn (allocator: std.mem.Allocator, ast: AST) anyerror![]Symbol,

    /// Optional call graph generation
    buildCallGraphFn: ?*const fn (allocator: std.mem.Allocator, ast: AST) anyerror!CallGraph,

    /// Optional reference finding
    findReferencesFn: ?*const fn (allocator: std.mem.Allocator, ast: AST, symbol: Symbol) anyerror![]Reference,

    pub fn extractSymbols(self: Analyzer, allocator: std.mem.Allocator, ast: AST) ![]Symbol {
        return self.extractSymbolsFn(allocator, ast);
    }

    pub fn buildCallGraph(self: Analyzer, allocator: std.mem.Allocator, ast: AST) !?CallGraph {
        if (self.buildCallGraphFn) |build_fn| {
            return build_fn(allocator, ast);
        }
        return null;
    }

    pub fn findReferences(self: Analyzer, allocator: std.mem.Allocator, ast: AST, symbol: Symbol) !?[]Reference {
        if (self.findReferencesFn) |find_fn| {
            return find_fn(allocator, ast, symbol);
        }
        return null;
    }
};

// Supporting data structures

/// Formatting options
pub const FormatOptions = struct {
    indent_size: u32 = 4,
    indent_style: IndentStyle = .space,
    line_width: u32 = 100,
    preserve_newlines: bool = true,
    trailing_comma: bool = false,
    sort_keys: bool = false,
    quote_style: QuoteStyle = .double,

    pub const IndentStyle = enum { space, tab };
    pub const QuoteStyle = enum { single, double, preserve };
};

/// Text range for editor operations
pub const Range = struct {
    start: Position,
    end: Position,

    pub const Position = struct {
        line: u32,
        column: u32,
    };
};

/// Incremental edit for tokenizer updates
pub const Edit = struct {
    range: Span,
    new_text: []const u8,
    generation: u32,
};

/// Token delta for incremental updates
pub const TokenDelta = struct {
    removed: []u32,
    added: []Token,
    affected_range: Span,
};

/// Structural boundary from parser
pub const Boundary = struct {
    kind: BoundaryKind,
    span: Span,
    confidence: f32,

    pub const BoundaryKind = enum {
        function,
        struct_,
        class,
        enum_,
        block,
        statement,
        expression,
    };
};

/// Linting rule definition
pub const Rule = struct {
    name: []const u8,
    description: []const u8,
    severity: Severity,
    enabled: bool = true,

    pub const Severity = enum { @"error", warning, info, hint };
};

/// Diagnostic from linting
pub const Diagnostic = struct {
    rule: []const u8,
    message: []const u8,
    severity: Rule.Severity,
    range: Span,
    fix: ?Fix = null,

    pub const Fix = struct {
        description: []const u8,
        edits: []Edit,
    };
};

/// Symbol from semantic analysis
pub const Symbol = struct {
    name: []const u8,
    kind: SymbolKind,
    range: Span,
    signature: ?[]const u8 = null,
    documentation: ?[]const u8 = null,

    pub const SymbolKind = enum {
        function,
        method,
        class,
        interface,
        struct_,
        enum_,
        variable,
        constant,
        parameter,
        property,
        module,
    };
};

/// Call graph from analysis
pub const CallGraph = struct {
    nodes: []CallNode,
    edges: []CallEdge,

    pub const CallNode = struct {
        symbol: Symbol,
        id: u32,
    };

    pub const CallEdge = struct {
        from: u32,
        to: u32,
        call_sites: []Span,
    };
};

/// Reference to a symbol
pub const Reference = struct {
    range: Span,
    kind: ReferenceKind,

    pub const ReferenceKind = enum {
        definition,
        declaration,
        reference,
        assignment,
    };
};
