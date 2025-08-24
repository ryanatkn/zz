const std = @import("std");

// Import foundation types from new modules
pub const StreamToken = @import("../token/mod.zig").StreamToken;
const Span = @import("../span/mod.zig").Span;
const Language = @import("../core/language.zig").Language;

/// Core language support interface that all languages must implement
/// Each language brings its own AST type and RuleType enum for complete isolation
pub fn LanguageSupport(comptime ASTType: type, comptime RuleType: type) type {
    return struct {
        const Self = @This();

        /// Language identifier
        language: Language,

        /// Lexical tokenizer
        lexer: Lexer,

        /// AST parser
        parser: Parser(ASTType),

        /// Code formatter
        formatter: Formatter(ASTType),

        /// Optional linter with language-specific rule types
        linter: ?Linter(ASTType, RuleType) = null,

        /// Optional semantic analyzer
        analyzer: ?Analyzer(ASTType) = null,

        /// Cleanup function
        deinitFn: ?*const fn (allocator: std.mem.Allocator) void = null,

        pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
            if (self.deinitFn) |deinit_fn| {
                deinit_fn(allocator);
            }
        }
    };
}

/// Lexical tokenization interface
pub const Lexer = struct {
    /// Optional incremental tokenization for editor use
    updateTokensFn: ?*const fn (allocator: std.mem.Allocator, tokens: []StreamToken, edit: Edit) anyerror!TokenDelta,

    pub fn updateTokens(self: Lexer, allocator: std.mem.Allocator, tokens: []StreamToken, edit: Edit) !?TokenDelta {
        if (self.updateTokensFn) |update_fn| {
            return update_fn(allocator, tokens, edit);
        }
        return null;
    }
};

/// AST parsing interface - uses anytype for language-specific ASTs
pub fn Parser(comptime ASTType: type) type {
    return struct {
        const Self = @This();

        /// Optional parsing with pre-computed boundaries for optimization
        parseWithBoundariesFn: ?*const fn (allocator: std.mem.Allocator, tokens: []StreamToken, boundaries: []Boundary) anyerror!ASTType,

        pub fn parseWithBoundaries(self: Self, allocator: std.mem.Allocator, tokens: []StreamToken, boundaries: []Boundary) !?ASTType {
            if (self.parseWithBoundariesFn) |parse_fn| {
                return parse_fn(allocator, tokens, boundaries);
            }
            return null;
        }
    };
}

/// Code formatting interface - uses anytype for language-specific ASTs
pub fn Formatter(comptime ASTType: type) type {
    return struct {
        const Self = @This();

        /// Format AST back to source code
        formatFn: *const fn (allocator: std.mem.Allocator, ast: ASTType, options: FormatOptions) anyerror![]const u8,

        /// Optional range formatting for editor integration
        formatRangeFn: ?*const fn (allocator: std.mem.Allocator, ast: ASTType, range: Range, options: FormatOptions) anyerror![]const u8,

        pub fn format(self: Self, allocator: std.mem.Allocator, ast: ASTType, options: FormatOptions) ![]const u8 {
            return self.formatFn(allocator, ast, options);
        }

        pub fn formatRange(self: Self, allocator: std.mem.Allocator, ast: ASTType, range: Range, options: FormatOptions) !?[]const u8 {
            if (self.formatRangeFn) |format_fn| {
                return format_fn(allocator, ast, range, options);
            }
            return null;
        }
    };
}

/// Optional linting interface - now generic over language-specific RuleType
/// Each language defines its own RuleType enum for optimal performance and isolation
pub fn Linter(comptime ASTType: type, comptime RuleType: type) type {
    return struct {
        const Self = @This();

        /// Rule metadata for UI/config (maps enum values to descriptions)
        ruleInfoFn: *const fn (rule: RuleType) RuleInfo(RuleType),

        /// Run linting on AST with enum-based rules (O(1) performance)
        lintFn: *const fn (allocator: std.mem.Allocator, ast: ASTType, rules: std.EnumSet(RuleType)) anyerror![]Diagnostic(RuleType),

        /// Get default enabled rules for this language
        getDefaultRulesFn: *const fn () std.EnumSet(RuleType),

        pub fn lint(self: Self, allocator: std.mem.Allocator, ast: ASTType, enabled_rules: std.EnumSet(RuleType)) ![]Diagnostic(RuleType) {
            return self.lintFn(allocator, ast, enabled_rules);
        }

        pub fn getDefaultRules(self: Self) std.EnumSet(RuleType) {
            return self.getDefaultRulesFn();
        }

        pub fn getRuleInfo(self: Self, rule: RuleType) RuleInfo(RuleType) {
            return self.ruleInfoFn(rule);
        }
    };
}

/// Optional semantic analysis interface
pub fn Analyzer(comptime ASTType: type) type {
    return struct {
        const Self = @This();

        /// Extract symbols (functions, types, variables)
        extractSymbolsFn: *const fn (allocator: std.mem.Allocator, ast: ASTType) anyerror![]Symbol,

        /// Optional call graph generation
        buildCallGraphFn: ?*const fn (allocator: std.mem.Allocator, ast: ASTType) anyerror!CallGraph,

        /// Optional reference finding
        findReferencesFn: ?*const fn (allocator: std.mem.Allocator, ast: ASTType, symbol: Symbol) anyerror![]Reference,

        pub fn extractSymbols(self: Self, allocator: std.mem.Allocator, ast: ASTType) ![]Symbol {
            return self.extractSymbolsFn(allocator, ast);
        }

        pub fn buildCallGraph(self: Self, allocator: std.mem.Allocator, ast: ASTType) !?CallGraph {
            if (self.buildCallGraphFn) |build_fn| {
                return build_fn(allocator, ast);
            }
            return null;
        }

        pub fn findReferences(self: Self, allocator: std.mem.Allocator, ast: ASTType, symbol: Symbol) !?[]Reference {
            if (self.findReferencesFn) |find_fn| {
                return find_fn(allocator, ast, symbol);
            }
            return null;
        }
    };
}

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
    added: []StreamToken,
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

/// Rule metadata for language-specific enum values
/// Used to provide human-readable information about rules
/// Severity levels for rules
pub const Severity = enum { err, warning, info, hint };

/// Generic rule info with enum-based rule (no string duplication)
pub fn RuleInfo(comptime RuleType: type) type {
    return struct {
        rule: RuleType, // Enum instead of string!
        description: []const u8,
        severity: Severity,
        enabled_by_default: bool,
    };
}

/// Diagnostic from linting
/// Generic diagnostic with enum-based rule (zero allocation for rule names)
pub fn Diagnostic(comptime RuleType: type) type {
    return struct {
        rule: RuleType, // Enum instead of string - no allocation needed!
        message: []const u8, // Dynamic message - still needs allocation
        severity: Severity,
        range: Span,
        fix: ?Fix = null,

        pub const Fix = struct {
            description: []const u8,
            edits: []Edit,
        };
    };
}

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
