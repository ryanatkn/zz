# Architecture Synthesis: Unifying Stream-First and Stratified Parser

## Executive Summary

This document synthesizes the two parallel parsing architectures in zz - the **Stream-First** system (for streaming/CLI) and the **Stratified Parser** (for editing/analysis) - into a unified design that achieves optimal performance for both batch processing and incremental editing scenarios.

**Key Decision**: Facts should be generated **both** directly from tokens (for speed) and from AST (for semantic richness), depending on the use case. The unified architecture uses a **progressive enrichment** model where basic facts stream immediately while semantic facts follow as needed.

## Current State Analysis

### What We Have: Two Parallel Systems

```
1. Stream-First Architecture (Phase 6)
   ├── DirectStream (1-2 cycle dispatch)
   ├── StreamToken (tagged union, 16 bytes)
   ├── Fact (24 bytes universal unit)
   └── Zero-allocation design

2. Stratified Parser (Partial)
   ├── Layer 0: Lexical (70% complete)
   ├── Layer 1: Structural (50% complete)
   ├── Layer 2: Detailed (40% complete)
   └── AST → Facts conversion
```

### Shared Components (Actually Used)

| Component | Location | Used By | Status |
|-----------|----------|---------|---------|
| Fact (24 bytes) | `lib/fact/` | Both systems | ✅ Active |
| Span (8 bytes) | `lib/span/` | Both systems | ✅ Active |
| StreamToken | `lib/token/` | Stream lexers | ✅ Active |
| DirectStream | `lib/stream/` | CLI commands | ✅ Active |
| FactStore | `lib/fact/store.zig` | Query system | ✅ Active |
| AST (old) | `lib/ast_old/` | Format/prompt | ⚠️ Legacy |

### Components That May Be Unused

Based on the codebase analysis, these components exist but may not be actively used:
- **Speculative parsing** (0% implemented)
- **Incremental updates** (30% implemented)
- **ViewportManager** (basic skeleton only)
- **FactIndex multi-indexing** (exists but not integrated)
- **parser_old/** (being replaced by stream architecture)

## Architecture Comparison

### Data Flow Paths

```
Current Stream-First (CLI):
Source → StreamLexer → DirectTokenStream → Formatter/Extractor
         (Zero copy)    (1-2 cycles)       (Direct output)

Current Stratified (Analysis):
Source → Lexer → Tokens → Parser → AST → FactGenerator → Facts
         (Copy)           (Allocate) (Walk)              (Index)

Optimal Unified:
Source → StreamLexer → DirectTokenStream → BasicFacts ─┐
         (Zero copy)    (1-2 cycles)       (Immediate)  │
                              ↓                          │
                        [If semantic needed]             │
                              ↓                          ↓
                          Parser → AST → SemanticFacts → UnifiedFactStream
                                         (Progressive)
```

### Performance Characteristics

| Operation | Stream-First | Stratified | Unified Target |
|-----------|--------------|------------|----------------|
| Token dispatch | 1-2 cycles | 3-5 cycles | 1-2 cycles |
| Simple format | <1ms/KB | N/A | <1ms/KB |
| Semantic analysis | N/A | 15ms viewport | <10ms viewport |
| Memory per MB | <100KB | ~2MB with AST | <200KB base |
| Incremental update | N/A | Partial | <1ms |

## Unified Architecture Design

### Core Principle: Progressive Enrichment

Facts are generated in **stages**, with each stage adding more semantic information:

```zig
// Stage 1: Lexical Facts (immediate, from tokens)
const LexicalFact = struct {
    span: Span,
    token_kind: TokenKind,
    text: ?[]const u8,  // For identifiers/literals
};

// Stage 2: Structural Facts (fast, from boundaries)  
const StructuralFact = struct {
    span: Span,
    boundary: BoundaryKind,  // function/class/block
    depth: u16,
    confidence: f16,
};

// Stage 3: Semantic Facts (slower, from AST)
const SemanticFact = struct {
    span: Span,
    node_kind: NodeKind,
    symbol: ?SymbolId,
    type_info: ?TypeId,
    relationships: []FactId,
};
```

### Unified Lexer Design

All lexers implement both streaming and stateful interfaces:

```zig
pub const UnifiedLexer = struct {
    // Streaming interface (zero-allocation)
    pub fn streamTokens(self: *Self) DirectStream(StreamToken) {
        return DirectStream(StreamToken){
            .generator = GeneratorStream(StreamToken){
                .context = self,
                .nextFn = generateNextToken,
            },
        };
    }
    
    // Stateful interface (for incremental)
    pub fn processEdit(self: *Self, edit: Edit) TokenDelta {
        // Update internal state
        // Return changed tokens
    }
    
    // Direct fact generation (no AST)
    pub fn generateLexicalFacts(token: StreamToken) LexicalFact {
        return .{
            .span = token.span(),
            .token_kind = token.kind(),
            .text = token.text(),
        };
    }
};
```

### Parser Integration Strategy

The parser becomes **optional** - invoked only when semantic information is needed:

```zig
pub const UnifiedParser = struct {
    lexer: UnifiedLexer,
    structural: StructuralAnalyzer,
    semantic: ?SemanticAnalyzer,  // Lazy initialization
    
    // Fast path: Direct token → fact streaming
    pub fn streamBasicFacts(self: *Self, source: []const u8) DirectStream(Fact) {
        var token_stream = self.lexer.streamTokens();
        return token_stream.map(Fact, tokenToBasicFact);
    }
    
    // Full path: With semantic analysis
    pub fn streamAllFacts(self: *Self, source: []const u8) DirectStream(Fact) {
        // Stream lexical facts immediately
        // Queue structural analysis
        // Progressively add semantic facts
        return DirectStream(Fact){
            .generator = ProgressiveFactGenerator{
                .lexer = &self.lexer,
                .parser = &self.semantic,
            },
        };
    }
    
    // Incremental path: For editors
    pub fn updateFacts(self: *Self, edit: Edit) FactDelta {
        const token_delta = self.lexer.processEdit(edit);
        if (token_delta.affectsStructure()) {
            // Reparse affected boundaries only
        }
        return self.computeFactDelta(token_delta);
    }
};
```

### Memory Management Strategy

Use **arena pools** with generation-based cleanup:

```zig
pub const FactArenaPool = struct {
    arenas: [4]Arena,  // Rotating arenas
    current: u2,       // Current arena index
    generation: u32,   // Current generation
    
    // Allocate in current arena
    pub fn alloc(self: *Self, comptime T: type) *T {
        return self.arenas[self.current].create(T);
    }
    
    // Rotate arenas on generation boundary
    pub fn nextGeneration(self: *Self) void {
        self.current = (self.current + 1) & 0x3;
        self.arenas[self.current].reset();
        self.generation += 1;
    }
};
```

## Implementation Roadmap

### Phase 1: Unify Token Infrastructure (1 week)

1. **Merge StreamToken with parser Token**
   - Keep 16-byte size for cache efficiency
   - Add fields needed by parser (depth, flags)
   - Maintain zero-copy design

2. **Create UnifiedLexer interface**
   - Implement for JSON/ZON first
   - Add incremental support
   - Generate basic facts directly

### Phase 2: Progressive Fact Generation (2 weeks)

1. **Implement staged fact generation**
   - LexicalFacts from tokens (immediate)
   - StructuralFacts from boundaries (fast)
   - SemanticFacts from AST (on-demand)

2. **Create ProgressiveFactStream**
   - Stream lexical facts immediately
   - Background thread for semantic analysis
   - Merge facts as they become available

### Phase 3: Optimize Critical Paths (1 week)

1. **Format command optimization**
   - Use direct token stream (no facts needed)
   - Skip AST entirely for simple formatting
   - Target: <1ms/KB

2. **Prompt command optimization**
   - Stream lexical facts for extraction
   - Add semantic facts only for --structure flag
   - Target: <5ms for typical file

### Phase 4: Editor Integration (2 weeks)

1. **Implement incremental updates**
   - Token-level incrementality
   - Boundary invalidation
   - Fact delta computation

2. **Add viewport optimization**
   - Prioritize visible region
   - Background parsing for rest
   - Predictive parsing for likely edits

## Performance Targets

### Immediate Goals (Phase 1-2)
- **Token streaming**: 1-2 cycle dispatch ✅ (already achieved)
- **Basic formatting**: <1ms/KB
- **Lexical facts**: <2ms for 1000 lines
- **Memory usage**: <200KB per MB source

### Medium-term Goals (Phase 3-4)
- **Full semantic analysis**: <10ms viewport
- **Incremental update**: <1ms typical edit
- **Memory with semantics**: <500KB per MB source
- **Cache hit rate**: >90% for viewport queries

### Long-term Goals
- **Speculative parsing**: 0ms perceived latency
- **Multi-file analysis**: <100ms for project
- **Type checking**: <50ms incremental

## Migration Strategy

### What to Keep
- DirectStream for optimal dispatch
- 24-byte Fact as universal unit
- StreamToken union design
- Arena-based memory management

### What to Refactor
- Merge duplicate lexer implementations
- Unify Token types (stream vs parser)
- Consolidate fact generation paths
- Simplify parser interfaces

### What to Remove
- AST-only code paths (make optional)
- Duplicate token conversion
- Old vtable Stream (after migration)
- Unused parser_old components

## Key Decisions

### 1. Facts After AST vs Direct from Tokens
**Decision**: **Both**, using progressive enrichment
- Lexical facts directly from tokens (fast)
- Semantic facts from AST when needed (rich)
- User chooses depth via flags

### 2. Streaming vs Incremental
**Decision**: **Unified interface** with both capabilities
- Same lexer provides both streaming and incremental
- Parser optional for pure streaming scenarios
- Full incrementality for editor integration

### 3. Performance vs Semantic Richness
**Decision**: **Progressive loading** based on use case
- CLI tools get immediate basic analysis
- Editors get full semantic analysis on demand
- Background processing fills in details

## Conclusion

The unified architecture achieves:
- **1-2 cycle dispatch** for streaming operations
- **<10ms viewport updates** for editing
- **Progressive enrichment** for semantic analysis
- **Zero-allocation core** with optional semantic layers
- **Unified codebase** without duplication

By merging the best aspects of both architectures and using progressive fact generation, we can support both high-performance streaming for CLI tools and rich semantic analysis for editors without compromise.

## Next Steps

1. Review and approve this synthesis
2. Begin Phase 1 implementation (token unification)
3. Update existing commands to use unified architecture
4. Measure performance at each phase
5. Iterate based on real-world usage

The key insight is that we don't need to choose between performance and features - we can have both by generating facts progressively and making expensive operations optional.