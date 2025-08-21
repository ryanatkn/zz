# Progressive Parser Architecture Plan

## Executive Summary

A **progressive enrichment** architecture where tokens are the fundamental intermediate representation. Lexing produces tokens (always needed), parsing consumes tokens to produce AST (optional), and facts are optional projections from either tokens or AST.

## Core Architectural Principles

### 1. Module Organization Rules
- **mod.zig files are PURE RE-EXPORTS** - no implementations ever
- **Liberal module creation** - each primitive/concern gets its own file
- **Language implementations stay in `lib/languages/`** - not scattered
- **Infrastructure in lib, implementations in languages**

### 2. Data Flow Hierarchy
```
Source Text
    ↓
[ALWAYS] Lexer → Tokens (fundamental IR)
    ↓               ↓
[OPTIONAL]    [OPTIONAL]
Lexical Facts    Parser → AST
                     ↓
                [OPTIONAL]
              Semantic Facts
```

**Key Insight**: Tokens are the fundamental intermediate representation. Everything else is optional.

## Module Structure - Clean Separation

```
src/lib/
├── lexer/               # Lexer INFRASTRUCTURE (no implementations)
│   ├── mod.zig          # PURE RE-EXPORT: Unified lexer interface
│   ├── interface.zig    # Lexer interface definitions
│   ├── streaming.zig    # Streaming tokenization infrastructure
│   ├── incremental.zig  # Incremental update infrastructure
│   ├── state.zig        # Lexer state management
│   ├── buffer.zig       # Buffer management for streaming
│   └── context.zig      # Lexer context and error handling
│
├── parser/              # Parser INFRASTRUCTURE (optional layer)
│   ├── mod.zig          # PURE RE-EXPORT: Parser interfaces
│   ├── interface.zig    # Parser interface definitions
│   ├── recursive.zig    # Recursive descent infrastructure
│   ├── structural.zig   # Boundary detection algorithms
│   ├── recovery.zig     # Error recovery strategies
│   ├── viewport.zig     # Viewport optimization for editors
│   ├── cache.zig        # Boundary caching system
│   └── context.zig      # Parse context and error tracking
│
├── ast/                 # AST INFRASTRUCTURE (optional representation)
│   ├── mod.zig          # PURE RE-EXPORT: AST types
│   ├── node.zig         # Base node definitions
│   ├── builder.zig      # AST construction helpers
│   ├── visitor.zig      # Visitor pattern implementation
│   ├── walker.zig       # Tree walking utilities
│   ├── transformer.zig  # AST transformation infrastructure
│   └── rules.zig        # Common AST patterns
│
├── fact/                # Fact INFRASTRUCTURE (optional projections)
│   ├── mod.zig          # PURE RE-EXPORT: 24-byte fact primitive
│   ├── fact.zig         # Core fact type definition
│   ├── lexical.zig      # Lexical fact projections from tokens
│   ├── semantic.zig     # Semantic fact projections from AST
│   ├── structural.zig   # Structural fact projections from boundaries
│   ├── store.zig        # Fact storage and indexing
│   ├── query.zig        # SQL-like fact queries
│   ├── builder.zig      # Fact construction DSL
│   └── stream.zig       # Fact streaming interface
│
├── token/               # Token PRIMITIVES (fundamental IR)
│   ├── mod.zig          # PURE RE-EXPORT: Token types
│   ├── token.zig        # Base token definition
│   ├── stream_token.zig # StreamToken tagged union
│   ├── kind.zig         # Unified token kinds
│   ├── flags.zig        # Token flags and metadata
│   ├── iterator.zig     # Token iteration helpers
│   └── buffer.zig       # Token buffering for parsing
│
├── span/                # Span PRIMITIVES (location tracking)
│   ├── mod.zig          # PURE RE-EXPORT: Span types
│   ├── span.zig         # 8-byte span definition
│   ├── packed.zig       # PackedSpan for compression
│   ├── set.zig          # Span collections
│   ├── ops.zig          # Span operations (merge, intersect)
│   └── index.zig        # Spatial indexing for spans
│
├── stream/              # Stream INFRASTRUCTURE (zero-alloc base)
│   ├── mod.zig          # PURE RE-EXPORT: Stream types
│   ├── direct_stream.zig # DirectStream with 1-2 cycle dispatch
│   ├── operators.zig    # Stream operators (map, filter)
│   ├── fusion.zig       # Operator fusion optimizations
│   ├── buffer.zig       # Ring buffers for streaming
│   ├── sink.zig         # Stream sinks and collectors
│   └── source.zig       # Stream sources and generators
│
├── languages/           # LANGUAGE IMPLEMENTATIONS (all here!)
│   ├── mod.zig          # PURE RE-EXPORT: Language registry
│   ├── interface.zig    # Common language interfaces
│   ├── registry.zig     # Language registration system
│   ├── common/          # Shared language utilities
│   │   ├── mod.zig      # PURE RE-EXPORT
│   │   ├── tokens.zig   # Common token patterns
│   │   ├── analysis.zig # Common analysis utilities
│   │   └── formatting.zig # Common format utilities
│   │
│   ├── json/            # JSON implementation
│   │   ├── mod.zig      # PURE RE-EXPORT: JSON support
│   │   ├── lexer.zig    # JSON lexer implementation
│   │   ├── tokens.zig   # JSON-specific tokens
│   │   ├── parser.zig   # JSON parser (optional)
│   │   ├── ast.zig      # JSON AST nodes
│   │   ├── formatter.zig # JSON formatter
│   │   ├── validator.zig # JSON schema validation
│   │   └── patterns.zig  # JSON-specific patterns
│   │
│   └── [other languages follow same pattern]
│
└── transform/           # Transform PIPELINES
    ├── mod.zig          # PURE RE-EXPORT: Transform types
    ├── pipeline.zig     # Pipeline infrastructure
    ├── format.zig       # Formatting transforms
    ├── extract.zig      # Extraction transforms
    └── optimize.zig     # Optimization transforms
```

## Key Interfaces

### 1. Unified Lexer Interface (Infrastructure)

```zig
// src/lib/lexer/interface.zig
pub const LexerInterface = struct {
    // Core capability - all lexers must provide streaming tokens
    streamTokensFn: *const fn (self: *anyopaque, source: []const u8) TokenStream,
    
    // Batch tokenization when you need all tokens at once (for parser)
    batchTokenizeFn: *const fn (self: *anyopaque, allocator: Allocator, source: []const u8) ![]Token,
    
    // Incremental updates for editors (optional)
    updateTokensFn: ?*const fn (self: *anyopaque, edit: Edit) TokenDelta,
    
    // Reset lexer state
    resetFn: *const fn (self: *anyopaque) void,
};

// src/lib/lexer/streaming.zig
pub const TokenStream = struct {
    // Zero-allocation streaming interface
    nextFn: *const fn (self: *anyopaque) ?Token,
    peekFn: *const fn (self: *anyopaque) ?Token,
    resetFn: *const fn (self: *anyopaque) void,
};
```

### 2. Language Implementation Pattern

```zig
// src/lib/languages/json/mod.zig - PURE RE-EXPORT
pub const lexer = @import("lexer.zig");
pub const parser = @import("parser.zig");
pub const formatter = @import("formatter.zig");
pub const tokens = @import("tokens.zig");

// Convenience re-exports
pub const JsonLexer = lexer.JsonLexer;
pub const JsonParser = parser.JsonParser;
pub const JsonFormatter = formatter.JsonFormatter;
pub const JsonToken = tokens.JsonToken;

// src/lib/languages/json/lexer.zig - IMPLEMENTATION
const std = @import("std");
const LexerInterface = @import("../../lexer/interface.zig").LexerInterface;
const TokenStream = @import("../../lexer/streaming.zig").TokenStream;

pub const JsonLexer = struct {
    // Implementation details...
    
    pub fn init(allocator: Allocator) JsonLexer {
        // Initialize lexer
    }
    
    pub fn streamTokens(self: *JsonLexer, source: []const u8) TokenStream {
        // Return streaming interface
    }
    
    pub fn batchTokenize(self: *JsonLexer, allocator: Allocator, source: []const u8) ![]Token {
        // Return all tokens at once
    }
    
    pub fn toInterface(self: *JsonLexer) LexerInterface {
        return .{
            .streamTokensFn = streamTokens,
            .batchTokenizeFn = batchTokenize,
            .updateTokensFn = null,  // TODO: Add incremental support
            .resetFn = reset,
        };
    }
};
```

### 3. Optional Fact Projections

```zig
// src/lib/fact/lexical.zig - Project facts from tokens
pub fn projectLexicalFacts(tokens: []const Token, allocator: Allocator) ![]LexicalFact {
    var facts = ArrayList(LexicalFact).init(allocator);
    for (tokens) |token| {
        if (shouldGenerateFact(token)) {
            try facts.append(LexicalFact{
                .span = token.span,
                .kind = token.kind,
                .depth = token.depth,
            });
        }
    }
    return facts.toOwnedSlice();
}

// src/lib/fact/semantic.zig - Project facts from AST
pub fn projectSemanticFacts(ast: AST, allocator: Allocator) ![]SemanticFact {
    var facts = ArrayList(SemanticFact).init(allocator);
    var visitor = FactVisitor.init(&facts);
    try ast.accept(&visitor);
    return facts.toOwnedSlice();
}
```

### 4. Parser Consuming Tokens

```zig
// src/lib/parser/interface.zig
pub const ParserInterface = struct {
    // Parser CONSUMES tokens from lexer to produce AST
    parseASTFn: *const fn (self: *anyopaque, allocator: Allocator, tokens: []const Token) !AST,
    
    // Incremental parsing for editors
    updateASTFn: ?*const fn (self: *anyopaque, ast: *AST, delta: TokenDelta) !void,
    
    // Structural analysis without full AST
    detectBoundariesFn: *const fn (self: *anyopaque, tokens: []const Token) ![]Boundary,
};

// Usage: Lexer → Tokens → Parser
const tokens = try lexer.batchTokenize(allocator, source);
const ast = try parser.parseAST(allocator, tokens);
```

## Usage Patterns

### Pattern 1: Direct Token Streaming (No Facts, No AST)
```zig
// Fast path for simple formatting
var lexer = JsonLexer.init(allocator);
var token_stream = lexer.streamTokens(source);
var formatter = StreamFormatter.init(writer);
while (token_stream.next()) |token| {
    try formatter.writeToken(token);
}
```

### Pattern 2: Lexical Facts Only (No AST)
```zig
// Syntax highlighting - only need token-level info
const tokens = try lexer.batchTokenize(allocator, source);
const lexical_facts = try projectLexicalFacts(tokens, allocator);
// Use facts for highlighting
```

### Pattern 3: Semantic Facts Only (No Lexical Facts)
```zig
// Type checking - only need semantic info
const tokens = try lexer.batchTokenize(allocator, source);
const ast = try parser.parseAST(allocator, tokens);
const semantic_facts = try projectSemanticFacts(ast, allocator);
// Use facts for type analysis
```

### Pattern 4: Full Analysis (All Facts)
```zig
// IDE support - need everything
const tokens = try lexer.batchTokenize(allocator, source);
const lexical_facts = try projectLexicalFacts(tokens, allocator);
const ast = try parser.parseAST(allocator, tokens);
const semantic_facts = try projectSemanticFacts(ast, allocator);
// Combine all facts for complete analysis
```

## Module Creation Guidelines

### 1. When to Create a New Module
- **Each primitive concept** gets its own file
- **Each distinct concern** gets its own file
- **Each algorithm** gets its own file
- **Prefer many small modules** over few large ones

### 2. mod.zig Rules
```zig
// GOOD: mod.zig as pure re-export
pub const interface = @import("interface.zig");
pub const streaming = @import("streaming.zig");
pub const incremental = @import("incremental.zig");

// Convenience re-exports for common usage
pub const LexerInterface = interface.LexerInterface;
pub const TokenStream = streaming.TokenStream;

// BAD: Implementation in mod.zig
pub const BadLexer = struct {  // NO! Move to separate file
    // Implementation here is wrong
};
```

### 3. File Naming Conventions
- **Primitives**: Simple names (`token.zig`, `span.zig`, `fact.zig`)
- **Algorithms**: Descriptive names (`recursive_descent.zig`, `boundary_detection.zig`)
- **Interfaces**: `interface.zig` or `[concept]_interface.zig`
- **Implementations**: `[language]_[component].zig` or just `[component].zig` in language dir

## Migration Strategy

### Phase 1: Module Restructuring (Week 1)
1. Create clean module structure with pure re-export mod.zig files
2. Move implementations out of mod.zig files
3. Establish infrastructure vs implementation separation
4. Keep language implementations in `lib/languages/`

### Phase 2: Unify Lexer Infrastructure (Week 1-2)
1. Build unified lexer interface in `lib/lexer/`
2. Adapt existing stream lexers to interface
3. Ensure streaming and batch modes
4. Add incremental support

### Phase 3: Optional Fact Projections (Week 2-3)
1. Implement fact projection functions (not generators)
2. Make lexical facts optional
3. Make semantic facts optional
4. Test all four usage patterns

### Phase 4: Parser Integration (Week 3-4)
1. Clarify parser consumes tokens
2. Make AST generation optional
3. Add structural analysis without full parse
4. Update commands to choose appropriate path

## Key Architectural Decisions

### Why Tokens as Fundamental IR?
- **Always needed** - Can't parse without tokens
- **Sufficient for many operations** - Formatting, highlighting
- **Natural boundary** - Lexing is distinct from parsing
- **Performance** - Can stream tokens without building AST

### Why Facts as Optional Projections?
- **Not always needed** - Many operations work on tokens/AST directly
- **Different consumers** - Some need lexical, some need semantic
- **Memory efficiency** - Only generate what's needed
- **Flexibility** - Can add new fact types without changing core

### Why mod.zig as Pure Re-exports?
- **Clear boundaries** - Easy to see what's public API
- **Avoid circular deps** - Implementation files can import each other
- **Better organization** - Can see module structure at a glance
- **Easier refactoring** - Can move implementations without changing imports

### Why Liberal Module Creation?
- **Single responsibility** - Each file has one clear purpose
- **Easier testing** - Can test each module in isolation
- **Better documentation** - Each concept gets focused docs
- **Reduced merge conflicts** - Smaller files change less often

## Success Criteria

1. **Clean separation** - Infrastructure in lib/, implementations in languages/
2. **Pure re-exports** - All mod.zig files have no implementations
3. **Optional projections** - Facts only generated when needed
4. **Streaming first** - Default to streaming, batch when necessary
5. **Progressive enrichment** - Can stop at any level (tokens/AST/facts)

## Next Steps

1. Review and approve this plan
2. Create module structure with pure re-exports
3. Move existing implementations to proper locations
4. Implement unified lexer interface
5. Update language implementations
6. Test all usage patterns
7. Update commands to use appropriate paths
8. Document final architecture

The key insight: **Tokens are the fundamental IR, everything else is optional transformation or projection.**