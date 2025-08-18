# TODO_SERIALIZATION_PHASE_1 - Foundation Implementation

**Created**: 2025-08-18  
**Status**: Ready for Implementation  
**Duration**: 2 weeks estimated  
**Goal**: Establish core transform pipeline infrastructure and extract encoding primitives

## 📋 Phase 1 Overview

This phase establishes the fundamental infrastructure for bidirectional transformations without migrating existing code. We'll build the pipeline system, define interfaces, and extract reusable encoding primitives from existing implementations.

## 🎯 Success Criteria for Phase 1

- [ ] Core transform types compile and have comprehensive tests
- [ ] Pipeline composition works with simple test transforms
- [ ] Encoding primitives extracted from JSON/ZON with no behavior changes
- [ ] All existing tests still pass (no regressions)
- [ ] Memory safety verified (no leaks in new code)
- [ ] Documentation complete for all new modules

## 📦 Module Implementation Plan

### 1. Transform Core (`lib/transform/`)

#### 1.1 `lib/transform/types.zig` - Core Type Definitions

**Purpose**: Define the fundamental types used throughout the transform system.

```zig
/// Result type for transforms that can partially succeed
pub const TransformResult = union(enum) {
    success: struct {
        output: []const u8,
        warnings: []Diagnostic,
    },
    partial: struct {
        output: []const u8,
        errors: []Diagnostic,
        recovered_count: usize,
    },
    failure: struct {
        errors: []Diagnostic,
    },
};

/// Diagnostic information for errors and warnings
pub const Diagnostic = struct {
    level: enum { error, warning, info },
    message: []const u8,
    span: ?Span,
    suggestion: ?[]const u8,
};

/// IO mode for parameterized execution
pub const IOMode = enum {
    sync,
    async,
    streaming,
};

/// Transform metadata for introspection
pub const TransformMetadata = struct {
    name: []const u8,
    description: []const u8,
    reversible: bool,
    streaming_capable: bool,
    estimated_memory: usize,
    performance_class: enum { fast, moderate, slow },
};
```

**Implementation Notes**:
- These types form the contract between all transform stages
- `TransformResult` allows graceful degradation with partial results
- `Diagnostic` provides rich error information for debugging
- Keep types simple and focused on data, not behavior

#### 1.2 `lib/transform/transform.zig` - Base Transform Interface

**Purpose**: Define the bidirectional transform abstraction that all stages implement.

```zig
/// Generic bidirectional transform between types In and Out
pub fn Transform(comptime In: type, comptime Out: type) type {
    return struct {
        const Self = @This();
        
        // Function pointers for transform operations
        forward_fn: *const fn (ctx: *Context, input: In) Error!Out,
        reverse_fn: ?*const fn (ctx: *Context, output: Out) Error!In,
        
        // Async variants (optional)
        forward_async_fn: ?*const fn (ctx: *Context, input: In) Error!Out,
        reverse_async_fn: ?*const fn (ctx: *Context, output: Out) Error!In,
        
        // Metadata for introspection
        metadata: TransformMetadata,
        
        /// Execute forward transform
        pub fn forward(self: Self, ctx: *Context, input: In) Error!Out {
            if (ctx.io_mode == .async and self.forward_async_fn != null) {
                return self.forward_async_fn.?(ctx, input);
            }
            return self.forward_fn(ctx, input);
        }
        
        /// Execute reverse transform (if available)
        pub fn reverse(self: Self, ctx: *Context, output: Out) Error!In {
            if (self.reverse_fn == null) {
                return error.NotReversible;
            }
            if (ctx.io_mode == .async and self.reverse_async_fn != null) {
                return self.reverse_async_fn.?(ctx, output);
            }
            return self.reverse_fn.?(ctx, output);
        }
        
        /// Check if transform is reversible
        pub fn isReversible(self: Self) bool {
            return self.reverse_fn != null;
        }
    };
}
```

**Design Decisions**:
- Function pointers allow runtime composition while maintaining type safety
- Async variants are optional to avoid forcing async complexity everywhere
- Metadata enables pipeline optimization and debugging
- Reverse operation is optional since not all transforms are reversible

#### 1.3 `lib/transform/context.zig` - Transform Context

**Purpose**: Carry state, options, and resources through transform pipelines.

```zig
/// Context passed through all transforms
pub const Context = struct {
    // Memory management
    allocator: std.mem.Allocator,
    arena: ?*std.heap.ArenaAllocator,  // For temporary allocations
    
    // IO configuration
    io_mode: IOMode,
    reader: ?std.io.AnyReader,
    writer: ?std.io.AnyWriter,
    
    // Options (format-specific)
    options: OptionsMap,
    
    // Error accumulation
    diagnostics: std.ArrayList(Diagnostic),
    error_limit: usize = 100,
    
    // Progress tracking (optional)
    progress: ?*Progress,
    cancel_token: ?*std.Thread.ResetEvent,
    
    // Performance monitoring
    start_time: ?i64,
    memory_start: ?usize,
    
    /// Create a new context
    pub fn init(allocator: std.mem.Allocator) Context {
        return .{
            .allocator = allocator,
            .arena = null,
            .io_mode = .sync,
            .reader = null,
            .writer = null,
            .options = OptionsMap.init(allocator),
            .diagnostics = std.ArrayList(Diagnostic).init(allocator),
            .progress = null,
            .cancel_token = null,
            .start_time = null,
            .memory_start = null,
        };
    }
    
    /// Create a child context with arena
    pub fn createChild(self: *Context) !Context {
        var arena = try self.allocator.create(std.heap.ArenaAllocator);
        arena.* = std.heap.ArenaAllocator.init(self.allocator);
        
        return .{
            .allocator = arena.allocator(),
            .arena = arena,
            .io_mode = self.io_mode,
            .reader = self.reader,
            .writer = self.writer,
            .options = self.options,  // Shared reference
            .diagnostics = std.ArrayList(Diagnostic).init(arena.allocator()),
            .error_limit = self.error_limit,
            .progress = self.progress,
            .cancel_token = self.cancel_token,
            .start_time = self.start_time,
            .memory_start = self.memory_start,
        };
    }
    
    pub fn deinit(self: *Context) void {
        self.diagnostics.deinit();
        self.options.deinit();
        if (self.arena) |arena| {
            arena.deinit();
            // Note: arena was allocated by parent, so parent must free
        }
    }
    
    /// Add a diagnostic message
    pub fn addDiagnostic(self: *Context, diag: Diagnostic) !void {
        if (self.diagnostics.items.len >= self.error_limit) {
            return error.TooManyErrors;
        }
        try self.diagnostics.append(diag);
    }
    
    /// Check if operation should be cancelled
    pub fn shouldCancel(self: *Context) bool {
        if (self.cancel_token) |token| {
            return token.isSet();
        }
        return false;
    }
};

/// Options storage with type-safe access
pub const OptionsMap = struct {
    map: std.StringHashMap(std.json.Value),
    
    pub fn init(allocator: std.mem.Allocator) OptionsMap {
        return .{ .map = std.StringHashMap(std.json.Value).init(allocator) };
    }
    
    pub fn deinit(self: *OptionsMap) void {
        self.map.deinit();
    }
    
    pub fn set(self: *OptionsMap, key: []const u8, value: anytype) !void {
        const json_value = try std.json.Value.jsonParse(value);
        try self.map.put(key, json_value);
    }
    
    pub fn get(self: OptionsMap, key: []const u8, comptime T: type) ?T {
        if (self.map.get(key)) |value| {
            return std.json.parse(T, value) catch null;
        }
        return null;
    }
};
```

**Key Features**:
- Arena allocator support for temporary allocations within transforms
- Diagnostic accumulation for error reporting
- Cancellation support for long-running operations
- Options map for format-specific configuration
- Child contexts for isolated transform stages

#### 1.4 `lib/transform/pipeline.zig` - Pipeline Composition

**Purpose**: Compose transforms into complex pipelines with branching and error handling.

```zig
/// Pipeline of composed transforms
pub fn Pipeline(comptime In: type, comptime Out: type) type {
    return struct {
        const Self = @This();
        
        transforms: std.ArrayList(ErasedTransform),
        allocator: std.mem.Allocator,
        metadata: TransformMetadata,
        
        /// Type-erased transform for storage
        const ErasedTransform = struct {
            forward: *const fn (*Context, *anyopaque) anyerror!*anyopaque,
            reverse: ?*const fn (*Context, *anyopaque) anyerror!*anyopaque,
            input_type: type,
            output_type: type,
            metadata: TransformMetadata,
        };
        
        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .transforms = std.ArrayList(ErasedTransform).init(allocator),
                .allocator = allocator,
                .metadata = .{
                    .name = "pipeline",
                    .description = "Composed transform pipeline",
                    .reversible = true,  // Updated based on stages
                    .streaming_capable = false,
                    .estimated_memory = 0,
                    .performance_class = .fast,
                },
            };
        }
        
        pub fn deinit(self: *Self) void {
            self.transforms.deinit();
        }
        
        /// Add a transform to the pipeline
        pub fn addTransform(self: *Self, transform: anytype) !void {
            // Type checking happens here
            // Implementation would verify type chain is valid
            try self.transforms.append(self.eraseType(transform));
            self.updateMetadata();
        }
        
        /// Chain this pipeline with another transform
        pub fn chain(self: Self, next: anytype) !Pipeline(@TypeOf(In), @TypeOf(next).Out) {
            // Creates new pipeline with combined transforms
        }
        
        /// Create parallel branches
        pub fn parallel(self: Self, other: Pipeline(In, Out)) !ParallelPipeline(In, Out) {
            // Returns pipeline that runs both in parallel
        }
        
        /// Conditional branching
        pub fn branch(
            self: Self,
            condition: fn (In) bool,
            if_true: Pipeline(In, Out),
            if_false: Pipeline(In, Out),
        ) ConditionalPipeline(In, Out) {
            // Returns pipeline with conditional logic
        }
        
        /// Execute the pipeline forward
        pub fn forward(self: Self, ctx: *Context, input: In) !Out {
            var current: *anyopaque = @ptrCast(@constCast(&input));
            
            for (self.transforms.items) |transform| {
                if (ctx.shouldCancel()) {
                    return error.Cancelled;
                }
                
                current = try transform.forward(ctx, current);
            }
            
            return @as(Out, @ptrCast(@alignCast(current)).*);
        }
        
        /// Execute the pipeline in reverse
        pub fn reverse(self: Self, ctx: *Context, output: Out) !In {
            if (!self.metadata.reversible) {
                return error.NotReversible;
            }
            
            var current: *anyopaque = @ptrCast(@constCast(&output));
            
            // Run transforms in reverse order
            var i = self.transforms.items.len;
            while (i > 0) : (i -= 1) {
                const transform = self.transforms.items[i - 1];
                if (transform.reverse == null) {
                    return error.StageNotReversible;
                }
                current = try transform.reverse.?(ctx, current);
            }
            
            return @as(In, @ptrCast(@alignCast(current)).*);
        }
        
        /// Execute with progress tracking
        pub fn runWithProgress(
            self: Self,
            ctx: *Context,
            input: In,
            progress: *Progress,
        ) !Out {
            ctx.progress = progress;
            defer ctx.progress = null;
            
            const total_steps = self.transforms.items.len;
            try progress.setTotal(total_steps);
            
            var current: *anyopaque = @ptrCast(@constCast(&input));
            
            for (self.transforms.items, 0..) |transform, i| {
                try progress.setStep(i, transform.metadata.name);
                current = try transform.forward(ctx, current);
                try progress.completeStep(i);
            }
            
            return @as(Out, @ptrCast(@alignCast(current)).*);
        }
        
        fn updateMetadata(self: *Self) void {
            // Update pipeline metadata based on stages
            self.metadata.reversible = true;
            self.metadata.streaming_capable = true;
            self.metadata.estimated_memory = 0;
            
            for (self.transforms.items) |transform| {
                if (transform.reverse == null) {
                    self.metadata.reversible = false;
                }
                if (!transform.metadata.streaming_capable) {
                    self.metadata.streaming_capable = false;
                }
                self.metadata.estimated_memory += transform.metadata.estimated_memory;
            }
        }
    };
}
```

**Design Philosophy**:
- Type erasure allows storing heterogeneous transforms while maintaining type safety at boundaries
- Metadata aggregation enables pipeline optimization
- Progress tracking for long-running operations
- Cancellation support throughout execution
- Branching and parallel execution for complex workflows

### 2. Stage Interfaces (`lib/transform/stages/`)

#### 2.1 `lib/transform/stages/lexical.zig` - Lexical Stage Interface

**Purpose**: Define the contract for tokenization/detokenization transforms.

```zig
const Transform = @import("../transform.zig").Transform;
const Context = @import("../context.zig").Context;

/// Token representation (language-agnostic)
pub const Token = struct {
    kind: TokenKind,
    text: []const u8,
    span: Span,
    trivia_before: []const u8,  // Whitespace/comments before token
    trivia_after: []const u8,   // Whitespace/comments after token
    
    /// Common token kinds (extended by languages)
    pub const TokenKind = enum {
        // Literals
        string,
        number,
        boolean,
        null,
        
        // Structure
        left_brace,    // {
        right_brace,   // }
        left_bracket,  // [
        right_bracket, // ]
        left_paren,    // (
        right_paren,   // )
        
        // Separators
        comma,
        colon,
        semicolon,
        
        // Operators
        equals,
        plus,
        minus,
        star,
        slash,
        
        // Keywords (language-specific)
        keyword,
        
        // Identifiers
        identifier,
        
        // Special
        comment,
        whitespace,
        eof,
        unknown,
        
        // Language extensions
        custom,
    };
};

/// Span in source text
pub const Span = struct {
    start: usize,
    end: usize,
    line: u32,
    column: u32,
};

/// Lexical stage: Text ↔ Tokens
pub const LexicalStage = Transform([]const u8, []Token);

/// Interface that language-specific lexers must implement
pub const ILexer = struct {
    /// Tokenize text into tokens
    tokenize: *const fn (ctx: *Context, text: []const u8) Error![]Token,
    
    /// Reconstruct text from tokens (including trivia)
    detokenize: *const fn (ctx: *Context, tokens: []Token) Error![]const u8,
    
    /// Stream tokenization support
    createTokenIterator: ?*const fn (ctx: *Context, reader: std.io.AnyReader) TokenIterator,
    
    /// Metadata about the lexer
    metadata: LexerMetadata,
};

pub const LexerMetadata = struct {
    language: []const u8,
    supports_comments: bool,
    supports_multiline_strings: bool,
    case_sensitive: bool,
    max_lookahead: usize,  // For streaming
};

/// Token iterator for streaming tokenization
pub const TokenIterator = struct {
    lexer: *ILexer,
    reader: std.io.AnyReader,
    buffer: std.ArrayList(u8),
    position: usize,
    line: u32,
    column: u32,
    
    pub fn next(self: *TokenIterator) !?Token {
        // Implementation provided by specific lexer
    }
    
    pub fn deinit(self: *TokenIterator) void {
        self.buffer.deinit();
    }
};

/// Create a lexical transform from a lexer implementation
pub fn createLexicalTransform(lexer: ILexer) LexicalStage {
    return .{
        .forward_fn = lexer.tokenize,
        .reverse_fn = lexer.detokenize,
        .forward_async_fn = null,  // TODO: Add async support
        .reverse_async_fn = null,
        .metadata = .{
            .name = lexer.metadata.language ++ "_lexer",
            .description = "Lexical analysis for " ++ lexer.metadata.language,
            .reversible = true,
            .streaming_capable = lexer.createTokenIterator != null,
            .estimated_memory = 1024 * 10,  // ~10KB for token buffer
            .performance_class = .fast,
        },
    };
}
```

**Key Concepts**:
- Language-agnostic token representation with common kinds
- Trivia preservation for format-preserving transforms
- Streaming support through iterator interface
- Metadata for lexer capabilities

#### 2.2 `lib/transform/stages/syntactic.zig` - Syntactic Stage Interface

**Purpose**: Define the contract for parsing/emitting transforms.

```zig
const AST = @import("../../ast/mod.zig").AST;
const Node = @import("../../ast/mod.zig").Node;

/// Syntactic stage: Tokens ↔ AST
pub const SyntacticStage = Transform([]Token, AST);

/// Interface that language-specific parsers must implement
pub const IParser = struct {
    /// Parse tokens into AST
    parse: *const fn (ctx: *Context, tokens: []Token) Error!AST,
    
    /// Emit AST back to tokens
    emit: *const fn (ctx: *Context, ast: AST) Error![]Token,
    
    /// Parse with error recovery
    parseWithRecovery: ?*const fn (ctx: *Context, tokens: []Token) ParseResult,
    
    /// Incremental parsing support
    parseIncremental: ?*const fn (ctx: *Context, old_ast: AST, edits: []Edit) Error!AST,
    
    /// Metadata
    metadata: ParserMetadata,
};

pub const ParserMetadata = struct {
    language: []const u8,
    supports_error_recovery: bool,
    supports_incremental: bool,
    max_nesting_depth: usize,
    average_node_size: usize,  // For memory estimation
};

/// Result of parsing with error recovery
pub const ParseResult = struct {
    ast: ?AST,                    // Partial AST if recovery succeeded
    errors: []ParseError,          // All parse errors encountered
    recovered_count: usize,        // Number of errors recovered from
    incomplete_nodes: []Node,      // Nodes that couldn't be completed
};

pub const ParseError = struct {
    message: []const u8,
    token_index: usize,
    expected: []const Token.TokenKind,
    actual: Token.TokenKind,
    recovery_action: enum {
        skipped,
        inserted,
        replaced,
        failed,
    },
};

/// Edit for incremental parsing
pub const Edit = struct {
    span: Span,
    old_text: []const u8,
    new_text: []const u8,
};

/// Create a syntactic transform from a parser implementation
pub fn createSyntacticTransform(parser: IParser) SyntacticStage {
    return .{
        .forward_fn = parser.parse,
        .reverse_fn = parser.emit,
        .forward_async_fn = null,
        .reverse_async_fn = null,
        .metadata = .{
            .name = parser.metadata.language ++ "_parser",
            .description = "Syntactic analysis for " ++ parser.metadata.language,
            .reversible = parser.emit != null,
            .streaming_capable = false,  // ASTs are not streamable
            .estimated_memory = parser.metadata.average_node_size * 100,
            .performance_class = .moderate,
        },
    };
}
```

**Design Notes**:
- Error recovery support for robust parsing
- Incremental parsing for editor integration
- Emit operation reconstructs tokens from AST
- ParseResult allows partial success with diagnostics

#### 2.3 `lib/transform/stages/semantic.zig` - Semantic Stage Interface

**Purpose**: Define the contract for semantic analysis transforms.

```zig
/// Schema representation
pub const Schema = struct {
    root_type: TypeInfo,
    symbols: []Symbol,
    dependencies: []Dependency,
    constraints: []Constraint,
    metadata: std.StringHashMap(std.json.Value),
};

pub const TypeInfo = struct {
    kind: TypeKind,
    name: ?[]const u8,
    fields: ?[]FieldInfo,
    element_type: ?*TypeInfo,
    nullable: bool,
    
    pub const TypeKind = enum {
        primitive,
        object,
        array,
        union_type,
        enum_type,
        any,
    };
};

pub const Symbol = struct {
    name: []const u8,
    kind: enum { variable, function, type, constant },
    type_info: TypeInfo,
    scope: []const u8,
    references: []Span,
};

/// Semantic stage: AST ↔ Schema
pub const SemanticStage = Transform(AST, Schema);

/// Interface for semantic analyzers
pub const IAnalyzer = struct {
    /// Extract semantic information from AST
    analyze: *const fn (ctx: *Context, ast: AST) Error!Schema,
    
    /// Generate AST from schema (reverse operation)
    synthesize: ?*const fn (ctx: *Context, schema: Schema) Error!AST,
    
    /// Type checking
    typeCheck: ?*const fn (ctx: *Context, ast: AST, schema: Schema) []TypeError,
    
    /// Symbol resolution
    resolveSymbols: ?*const fn (ctx: *Context, ast: AST) SymbolTable,
    
    /// Metadata
    metadata: AnalyzerMetadata,
};

pub const AnalyzerMetadata = struct {
    language: []const u8,
    supports_type_inference: bool,
    supports_schema_generation: bool,
    supports_validation: bool,
};
```

**Semantic Concepts**:
- Schema extraction for type information
- Symbol resolution and scoping
- Type checking and validation
- Bidirectional with synthesis operation

### 3. Encoding Primitives (`lib/encoding/`)

#### 3.1 `lib/encoding/text/indent.zig` - Smart Indentation

**Purpose**: Extract and unify indentation logic from formatters.

```zig
/// Indentation style detection and management
pub const IndentManager = struct {
    allocator: std.mem.Allocator,
    default_style: IndentStyle,
    default_size: u32,
    
    pub const IndentStyle = enum {
        spaces,
        tabs,
        mixed,  // Tabs for indentation, spaces for alignment
    };
    
    pub const IndentInfo = struct {
        style: IndentStyle,
        size: u32,  // Number of spaces per indent level
        inconsistent: bool,
        mixed_lines: []usize,  // Line numbers with mixed indentation
    };
    
    /// Detect indentation style from text
    pub fn detectStyle(self: IndentManager, text: []const u8) IndentInfo {
        // Analyze leading whitespace of each line
        // Count spaces vs tabs
        // Detect common indent sizes (2, 4, 8)
        // Flag inconsistencies
    }
    
    /// Indent text by specified levels
    pub fn indent(
        self: IndentManager,
        text: []const u8,
        levels: u32,
        style: ?IndentStyle,
    ) ![]const u8 {
        // Add indentation to each line
        // Preserve empty lines
        // Handle existing indentation
    }
    
    /// Remove one level of indentation
    pub fn dedent(self: IndentManager, text: []const u8) ![]const u8 {
        // Detect current indentation
        // Remove one level from each line
        // Preserve relative indentation
    }
    
    /// Convert between indentation styles
    pub fn convertStyle(
        self: IndentManager,
        text: []const u8,
        from: IndentStyle,
        to: IndentStyle,
        size: u32,
    ) ![]const u8 {
        // Parse existing indentation
        // Convert to target style
        // Maintain alignment in mixed mode
    }
    
    /// Get indentation string for level
    pub fn getIndent(
        self: IndentManager,
        level: u32,
        style: ?IndentStyle,
        size: ?u32,
    ) []const u8 {
        const use_style = style orelse self.default_style;
        const use_size = size orelse self.default_size;
        
        return switch (use_style) {
            .tabs => "\t" ** level,
            .spaces => " " ** (level * use_size),
            .mixed => "\t" ** level,  // Tabs for indentation
        };
    }
    
    /// Calculate indentation level of a line
    pub fn getLevel(self: IndentManager, line: []const u8) u32 {
        // Count leading whitespace
        // Convert to indent levels based on style
    }
};
```

**Extraction Sources**:
- `json/formatter.zig` - Lines 54-56, 89-91 (indent handling)
- `zon/formatter.zig` - Similar indentation logic
- Will unify and extend with smart detection

#### 3.2 `lib/encoding/text/escape.zig` - Language-Specific Escaping

**Purpose**: Unify escape sequence handling across formats.

```zig
/// Escape sequence handling for different languages
pub const Escaper = struct {
    allocator: std.mem.Allocator,
    
    pub const Language = enum {
        json,
        zon,
        javascript,
        typescript,
        html,
        xml,
        regex,
        custom,
    };
    
    pub const EscapeRules = struct {
        // Characters that must be escaped
        must_escape: []const u8,
        
        // Escape sequences map
        sequences: std.AutoHashMap(u8, []const u8),
        
        // Unicode escape format
        unicode_format: enum {
            none,
            hex_4,      // \uXXXX (JSON, JavaScript)
            hex_2,      // \xXX (ZON)
            hex_6,      // \UXXXXXX (extended)
            html_dec,   // &#123;
            html_hex,   // &#x7B;
        },
        
        // Options
        escape_non_ascii: bool,
        escape_control: bool,
        preserve_newlines: bool,
    };
    
    /// Get built-in rules for a language
    pub fn getRules(language: Language) EscapeRules {
        return switch (language) {
            .json => .{
                .must_escape = "\"\\",
                .sequences = jsonEscapeMap(),
                .unicode_format = .hex_4,
                .escape_non_ascii = false,
                .escape_control = true,
                .preserve_newlines = false,
            },
            .zon => .{
                .must_escape = "\"\\",
                .sequences = zonEscapeMap(),
                .unicode_format = .hex_2,
                .escape_non_ascii = false,
                .escape_control = true,
                .preserve_newlines = true,  // ZON supports multiline
            },
            // ... other languages
        };
    }
    
    /// Escape a string according to language rules
    pub fn escape(
        self: Escaper,
        text: []const u8,
        language: Language,
    ) ![]const u8 {
        const rules = getRules(language);
        var result = std.ArrayList(u8).init(self.allocator);
        
        for (text) |char| {
            if (rules.sequences.get(char)) |seq| {
                try result.appendSlice(seq);
            } else if (char < 0x20 and rules.escape_control) {
                try self.appendUnicodeEscape(&result, char, rules.unicode_format);
            } else if (char > 0x7F and rules.escape_non_ascii) {
                try self.appendUnicodeEscape(&result, char, rules.unicode_format);
            } else {
                try result.append(char);
            }
        }
        
        return result.toOwnedSlice();
    }
    
    /// Unescape a string
    pub fn unescape(
        self: Escaper,
        text: []const u8,
        language: Language,
    ) ![]const u8 {
        const rules = getRules(language);
        var result = std.ArrayList(u8).init(self.allocator);
        var i: usize = 0;
        
        while (i < text.len) {
            if (text[i] == '\\' and i + 1 < text.len) {
                // Handle escape sequence
                const unescaped = try self.parseEscapeSequence(text[i + 1..], rules);
                try result.append(unescaped.char);
                i += unescaped.consumed + 1;  // +1 for backslash
            } else {
                try result.append(text[i]);
                i += 1;
            }
        }
        
        return result.toOwnedSlice();
    }
    
    /// Custom escape rules for special cases
    pub fn escapeCustom(
        self: Escaper,
        text: []const u8,
        rules: EscapeRules,
    ) ![]const u8 {
        // Apply custom rules
    }
    
    fn jsonEscapeMap() std.AutoHashMap(u8, []const u8) {
        var map = std.AutoHashMap(u8, []const u8).init(allocator);
        map.put('"', "\\\"");
        map.put('\\', "\\\\");
        map.put('/', "\\/");  // Optional but common
        map.put('\b', "\\b");
        map.put('\f', "\\f");
        map.put('\n', "\\n");
        map.put('\r', "\\r");
        map.put('\t', "\\t");
        return map;
    }
};
```

**Extraction Notes**:
- Currently duplicated in JSON and ZON formatters
- Each language has different escape rules
- Unicode handling varies by format
- Will provide unified interface with language-specific rules

#### 3.3 `lib/encoding/text/quote.zig` - Quote Style Management

**Purpose**: Handle different quoting styles across languages.

```zig
/// Quote style management for strings
pub const QuoteManager = struct {
    allocator: std.mem.Allocator,
    
    pub const QuoteStyle = enum {
        single,         // 'text'
        double,         // "text"
        backtick,       // `text`
        triple_single,  // '''text'''
        triple_double,  // """text"""
        none,          // No quotes
    };
    
    pub const QuoteOptions = struct {
        style: QuoteStyle,
        escape_inner: bool,
        multiline: bool,
        raw: bool,  // Raw strings (no escaping)
    };
    
    /// Add quotes to a string
    pub fn addQuotes(
        self: QuoteManager,
        text: []const u8,
        options: QuoteOptions,
    ) ![]const u8 {
        const quote_str = getQuoteString(options.style);
        var result = std.ArrayList(u8).init(self.allocator);
        
        try result.appendSlice(quote_str);
        
        if (options.escape_inner and !options.raw) {
            // Escape any inner quotes
            for (text) |char| {
                if (isQuoteChar(char, options.style)) {
                    try result.append('\\');
                }
                try result.append(char);
            }
        } else {
            try result.appendSlice(text);
        }
        
        try result.appendSlice(quote_str);
        return result.toOwnedSlice();
    }
    
    /// Remove quotes from a string
    pub fn stripQuotes(
        self: QuoteManager,
        text: []const u8,
    ) ![]const u8 {
        const style = detectQuoteStyle(text);
        if (style == .none) return text;
        
        const quote_len = getQuoteString(style).len;
        if (text.len < quote_len * 2) return text;
        
        return self.allocator.dupe(u8, text[quote_len..text.len - quote_len]);
    }
    
    /// Detect quote style used
    pub fn detectQuoteStyle(text: []const u8) QuoteStyle {
        if (text.len >= 6) {
            if (std.mem.startsWith(u8, text, "'''") and 
                std.mem.endsWith(u8, text, "'''")) {
                return .triple_single;
            }
            if (std.mem.startsWith(u8, text, "\"\"\"") and 
                std.mem.endsWith(u8, text, "\"\"\"")) {
                return .triple_double;
            }
        }
        if (text.len >= 2) {
            if (text[0] == '\'' and text[text.len - 1] == '\'') return .single;
            if (text[0] == '"' and text[text.len - 1] == '"') return .double;
            if (text[0] == '`' and text[text.len - 1] == '`') return .backtick;
        }
        return .none;
    }
    
    /// Convert between quote styles
    pub fn convertQuotes(
        self: QuoteManager,
        text: []const u8,
        to_style: QuoteStyle,
    ) ![]const u8 {
        const stripped = try self.stripQuotes(text);
        return self.addQuotes(stripped, .{ .style = to_style, .escape_inner = true });
    }
    
    fn getQuoteString(style: QuoteStyle) []const u8 {
        return switch (style) {
            .single => "'",
            .double => "\"",
            .backtick => "`",
            .triple_single => "'''",
            .triple_double => "\"\"\"",
            .none => "",
        };
    }
};
```

**Use Cases**:
- JSON requires double quotes
- JavaScript supports single, double, and backticks
- Python supports triple quotes for multiline
- Unified handling reduces duplication

### 4. Pipeline Combinators (`lib/transform/combinators/`)

#### 4.1 `lib/transform/combinators/branch.zig` - Conditional Pipelines

**Purpose**: Enable conditional transform execution based on input.

```zig
/// Conditional pipeline that chooses path based on predicate
pub fn ConditionalPipeline(comptime In: type, comptime Out: type) type {
    return struct {
        condition: *const fn (In) bool,
        true_branch: Pipeline(In, Out),
        false_branch: Pipeline(In, Out),
        
        pub fn execute(self: @This(), ctx: *Context, input: In) !Out {
            if (self.condition(input)) {
                return self.true_branch.forward(ctx, input);
            } else {
                return self.false_branch.forward(ctx, input);
            }
        }
    };
}

/// Pattern matching pipeline
pub fn MatchPipeline(comptime In: type, comptime Out: type) type {
    return struct {
        cases: []const Case,
        default: Pipeline(In, Out),
        
        const Case = struct {
            pattern: *const fn (In) bool,
            pipeline: Pipeline(In, Out),
        };
        
        pub fn execute(self: @This(), ctx: *Context, input: In) !Out {
            for (self.cases) |case| {
                if (case.pattern(input)) {
                    return case.pipeline.forward(ctx, input);
                }
            }
            return self.default.forward(ctx, input);
        }
    };
}
```

#### 4.2 `lib/transform/combinators/parallel.zig` - Parallel Execution

**Purpose**: Run multiple pipelines concurrently.

```zig
/// Parallel pipeline execution
pub fn ParallelPipeline(comptime In: type, comptime Out: type) type {
    return struct {
        pipelines: []Pipeline(In, Out),
        merge_strategy: MergeStrategy,
        
        pub const MergeStrategy = enum {
            first,      // Return first result
            all,        // Return all results
            fastest,    // Return fastest result
            consensus,  // Majority vote
        };
        
        pub fn execute(self: @This(), ctx: *Context, input: In) !Out {
            // Launch parallel execution
            // Wait based on strategy
            // Merge results
        }
    };
}
```

## 📊 Testing Strategy

### Unit Tests for Each Module

```zig
// transform/transform_test.zig
test "bidirectional transform" {
    const TestTransform = Transform(i32, []const u8);
    
    const transform = TestTransform{
        .forward_fn = testForward,
        .reverse_fn = testReverse,
        // ...
    };
    
    var ctx = Context.init(testing.allocator);
    defer ctx.deinit();
    
    const result = try transform.forward(&ctx, 42);
    try testing.expectEqualStrings("42", result);
    
    const original = try transform.reverse(&ctx, result);
    try testing.expectEqual(@as(i32, 42), original);
}

// encoding/text/indent_test.zig
test "detect indentation style" {
    const manager = IndentManager.init(testing.allocator);
    
    const spaces_text = "  hello\n    world";
    const info = manager.detectStyle(spaces_text);
    try testing.expectEqual(IndentStyle.spaces, info.style);
    try testing.expectEqual(@as(u32, 2), info.size);
}

// Pipeline composition test
test "pipeline composition" {
    var pipeline = Pipeline([]const u8, AST).init(testing.allocator);
    defer pipeline.deinit();
    
    try pipeline.addTransform(JsonLexer.init());
    try pipeline.addTransform(JsonParser.init());
    
    const ast = try pipeline.forward(&ctx, json_text);
    const reconstructed = try pipeline.reverse(&ctx, ast);
    
    try testing.expectEqualStrings(json_text, reconstructed);
}
```

### Integration Tests

```zig
test "JSON round-trip with formatting" {
    // Test that JSON → AST → formatted JSON preserves semantics
    const original = "{\"a\":1,\"b\":2}";
    
    var pipeline = createJsonPipeline(.{ .indent = 2 });
    const ast = try pipeline.forward(&ctx, original);
    const formatted = try pipeline.reverse(&ctx, ast);
    
    try testing.expectEqualStrings(
        \\{
        \\  "a": 1,
        \\  "b": 2
        \\}
    , formatted);
}
```

## 🔄 Migration Strategy

### Phase 1 does NOT migrate existing code

Instead, we:
1. Build new infrastructure alongside existing code
2. Extract common patterns into encoding modules
3. Test thoroughly with synthetic examples
4. Document all interfaces

### Future phases will:
- Migrate JSON to use new pipeline
- Migrate ZON to use new pipeline
- Deprecate old implementations

## 📈 Performance Considerations

### Memory Management
- Use arena allocators for transform-local allocations
- Pool token arrays for reuse
- Minimize string duplication

### Optimization Opportunities
- Pipeline fusion (combine adjacent transforms)
- Parallel execution where possible
- Lazy evaluation for large inputs
- Caching of repeated transforms

### Benchmarking Plan
```zig
// benchmark/transform_bench.zig
fn benchmarkPipeline() !void {
    var timer = Timer.start();
    
    // Measure pipeline overhead
    const pipeline_time = timer.lap();
    
    // Measure direct implementation
    const direct_time = timer.lap();
    
    // Assert overhead < 5%
    try testing.expect(pipeline_time < direct_time * 1.05);
}
```

## 🎯 Deliverables for Phase 1

### Core Infrastructure
- [ ] `transform/types.zig` - Type definitions
- [ ] `transform/transform.zig` - Transform interface
- [ ] `transform/context.zig` - Context implementation
- [ ] `transform/pipeline.zig` - Pipeline composition

### Stage Interfaces
- [ ] `stages/lexical.zig` - Tokenization interface
- [ ] `stages/syntactic.zig` - Parsing interface
- [ ] `stages/semantic.zig` - Analysis interface

### Encoding Primitives
- [ ] `encoding/text/indent.zig` - Indentation management
- [ ] `encoding/text/escape.zig` - Escape sequences
- [ ] `encoding/text/quote.zig` - Quote styles

### Testing
- [ ] Unit tests for all modules
- [ ] Integration tests for pipeline composition
- [ ] Performance benchmarks
- [ ] Memory leak tests

### Documentation
- [ ] API documentation for all public interfaces
- [ ] Usage examples
- [ ] Migration guide for Phase 2

## 🚀 Getting Started

After Phase 1 is complete, developers will be able to:

```zig
const transform = @import("lib/transform/mod.zig");
const encoding = @import("lib/encoding/mod.zig");

// Create a simple transform
const MyTransform = transform.Transform([]const u8, []const u8);

const my_transform = MyTransform{
    .forward_fn = myForward,
    .reverse_fn = myReverse,
    .metadata = .{ ... },
};

// Use encoding primitives
const indent = encoding.text.IndentManager.init(allocator);
const indented = try indent.indent(text, 2, .spaces);

// Compose into pipeline
var pipeline = transform.Pipeline([]const u8, []const u8).init(allocator);
try pipeline.addTransform(my_transform);
```

## 📝 Success Metrics

Phase 1 is successful when:
- All modules compile without errors
- All tests pass (100% of new tests)
- No memory leaks in new code
- Existing tests still pass (no regressions)
- Documentation is complete
- Performance benchmarks establish baselines

---

*This document provides the complete blueprint for Phase 1 implementation. No existing code is modified, only new infrastructure is added.*