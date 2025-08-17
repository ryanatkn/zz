# Stratified Parser Implementation Plan

## Executive Summary

This document outlines the implementation roadmap for transitioning zz from a traditional recursive descent parser to a **Stratified Parser Architecture** - a next-generation parsing system designed for <1ms editor responsiveness. The architecture combines layered parsing, differential fact streams, and speculative execution to achieve unprecedented performance in real-time code editing scenarios.

**Timeline**: 24 weeks (6 months)  
**Goal**: <1ms latency for critical editor operations  
**Approach**: Incremental phases building on existing Pure Zig foundation

## Current State Assessment

### What We Have (Phase 0 Complete)
- ✅ **Grammar System**: Fluent API with rule references, validation
- ✅ **Parser Module**: Recursive descent with backtracking
- ✅ **AST Infrastructure**: Generic nodes with visitor pattern
- ✅ **Test Framework**: Comprehensive testing infrastructure
- ✅ **60+ Tests Passing**: Solid foundation to build upon

### What We Need
- ❌ **Layered Architecture**: Separate lexical/structural/detailed parsing
- ❌ **Fact Streams**: Immutable fact-based representation
- ❌ **Differential Updates**: Zero-copy incremental parsing
- ❌ **Speculative Execution**: Predictive parsing for instant response
- ❌ **Sub-millisecond Latency**: Current parser too slow for real-time

### Architecture Gap Analysis

| Component | Current | Target | Gap |
|-----------|---------|--------|-----|
| Parser Algorithm | Recursive Descent | Stratified Layers | Complete redesign |
| Data Structure | AST Tree | Fact Stream | New IR needed |
| Update Model | Full Reparse | Differential | Incremental system |
| Latency | 10-50ms | <1ms | 10-50x improvement |
| Memory Model | Tree Allocation | Arena + Pools | Memory optimization |
| Parallelism | None | Full | Thread pool needed |

## Phase 1: Foundation Types & Infrastructure (Weeks 1-2)

### Goals
- Establish core type system for stratified parser
- Create specialized data structures
- Set up module hierarchy

### Deliverables

#### 1.1 Core Types (`src/lib/parser/foundation/types/`)
```zig
// span.zig - Text position and range management
pub const Span = struct {
    start: usize,
    end: usize,
    
    pub fn overlaps(self: Span, other: Span) bool;
    pub fn contains(self: Span, pos: usize) bool;
    pub fn merge(self: Span, other: Span) Span;
};

// fact.zig - Immutable facts about parse
pub const FactId = u32;
pub const Generation = u32;
pub const Confidence = f32;

pub const Fact = struct {
    id: FactId,
    subject: Span,
    predicate: Predicate,
    object: Value,
    confidence: Confidence,
};

// token.zig - Token representation
pub const Token = struct {
    span: Span,
    kind: TokenKind,
    text: []const u8,
    bracket_depth: u16,  // Pre-computed for speed
};
```

#### 1.2 Math Utilities (`src/lib/parser/foundation/math/`)
- Span arithmetic operations
- Line/column calculations
- UTF-8 coordinate handling
- SIMD preparation for future optimization

#### 1.3 Specialized Collections (`src/lib/parser/foundation/collections/`)
```zig
// Optimized for fact storage and querying
pub const FactIndex = struct {
    by_span: BTreeMap(Span, []FactId),
    by_predicate: HashMap(Predicate, []FactId),
    by_subject: HashMap(Span, []FactId),
    parent_child: HashMap(FactId, []FactId),
};

// Cache for query results
pub const QueryCache = struct {
    entries: HashMap(QueryId, CacheEntry),
    generation: Generation,
    
    pub fn invalidate(self: *QueryCache, affected: Span);
};
```

### Performance Targets
- Span operations: <10ns
- Fact lookup by ID: O(1), <50ns
- Fact query by span: O(log n), <500ns
- Collection iteration: Linear with prefetching

### Migration Strategy
- Move existing `ParseContext` → `foundation/types/context.zig`
- Extract span logic from AST → `foundation/math/span.zig`
- Generalize memory pools → `foundation/collections/pools.zig`

## Phase 2: Module Reorganization (Weeks 3-4)

### Goals
- Restructure existing code into stratified architecture
- Preserve working functionality while moving files
- Establish clear module boundaries

### New Module Structure
```
src/lib/parser/
├── foundation/          # Phase 1 deliverables
│   ├── types/
│   ├── math/
│   └── collections/
├── lexical/            # Layer 0 (Phase 3)
│   ├── tokenizer.zig
│   ├── scanner.zig
│   └── brackets.zig
├── structural/         # Layer 1 (Phase 7)
│   ├── parser.zig
│   ├── boundaries.zig
│   └── recovery.zig
├── detailed/           # Layer 2 (Phase 8)
│   ├── parser.zig      # Current parser moves here
│   ├── disambiguation.zig
│   └── ast.zig
├── facts/              # Fact system (Phase 5)
│   ├── stream.zig
│   ├── delta.zig
│   ├── indexing.zig
│   └── querying.zig
├── speculation/        # Speculative execution (Phase 9)
│   ├── engine.zig
│   └── predictors/
├── incremental/        # Cross-cutting (Phase 6)
│   ├── diff.zig
│   ├── cache.zig
│   └── coordinator.zig
├── languages/          # Language definitions
│   ├── specs/          # Grammar specs (current grammar/)
│   └── generated/      # Future: generated parsers
└── mod.zig            # Public API
```

### Migration Steps
1. Create new directory structure
2. Move existing parser → `detailed/parser.zig`
3. Move existing grammar → `languages/specs/`
4. Update imports and tests
5. Verify all tests still pass

## Phase 3: Lexical Layer Implementation (Weeks 5-6)

### Goals
- Streaming tokenizer with <0.1ms viewport latency
- Character-level incremental updates
- Bracket depth pre-computation

### Deliverables

#### 3.1 Streaming Tokenizer (`lexical/tokenizer.zig`)
```zig
pub const StreamingLexer = struct {
    buffer: []const u8,
    position: usize,
    tokens: TokenStream,
    bracket_tracker: BracketTracker,
    
    pub fn processEdit(self: *StreamingLexer, edit: Edit) TokenDelta {
        // Returns only changed tokens
        // Target: <0.1ms for viewport (50 lines)
    }
    
    pub fn tokenizeRange(self: *StreamingLexer, range: Span) []Token {
        // Stateless within line boundaries
        // Enables parallel tokenization
    }
};
```

#### 3.2 Bracket Tracking (`lexical/brackets.zig`)
- Real-time bracket matching
- Depth calculation during tokenization
- Instant pair finding (<1ms)

### Performance Benchmarks
```zig
test "viewport tokenization under 100 microseconds" {
    const viewport_size = 50 * 80; // 50 lines, 80 chars
    const start = std.time.nanoTimestamp();
    const tokens = lexer.tokenizeRange(viewport);
    const elapsed = std.time.nanoTimestamp() - start;
    try testing.expect(elapsed < 100_000); // 100μs
}
```

### Integration Points
- Use existing TokenKind from grammar
- Feed tokens to structural parser
- Provide tokens for syntax highlighting

## Phase 4: Lexical Layer Optimization (Weeks 7-8)

### Goals
- SIMD acceleration for tokenization
- Memory-mapped file support
- Zero-copy token generation

### Optimizations
1. **SIMD Scanning**: Use vector instructions for delimiter detection
2. **Lookup Tables**: Pre-computed character classification
3. **Memory Mapping**: Direct file access without copying
4. **Thread-Local Buffers**: Avoid allocations in hot path

### Performance Targets
- Single-threaded: 100MB/s tokenization
- Multi-threaded: Linear scaling to core count
- Memory usage: <2x file size

## Phase 5: Fact Stream Engine (Weeks 9-10)

### Goals
- Immutable fact-based representation
- Differential update system
- Efficient querying infrastructure

### Deliverables

#### 5.1 Fact Stream (`facts/stream.zig`)
```zig
pub const FactStream = struct {
    facts: []Fact,
    indices: FactIndex,
    generation: Generation,
    allocator: std.mem.Allocator,
    
    pub fn applyDelta(self: *FactStream, delta: FactDelta) void {
        // 1. Retract old facts
        // 2. Assert new facts
        // 3. Update indices
        // 4. Increment generation
    }
    
    pub fn query(self: FactStream, q: Query) QueryResult {
        // Use indices for efficient lookup
    }
};
```

#### 5.2 Differential Updates (`facts/delta.zig`)
```zig
pub const FactDelta = struct {
    generation: Generation,
    retractions: []FactId,
    assertions: []Fact,
    affected_range: Span,
    
    pub fn merge(deltas: []FactDelta) FactDelta {
        // Combine multiple deltas efficiently
    }
};
```

#### 5.3 Query System (`facts/querying.zig`)
- Predicate-based queries
- Span-based queries
- Cached query results
- Incremental query updates

### Performance Benchmarks
- Fact assertion: <100ns per fact
- Fact retraction: <50ns per fact
- Index update: <200ns per fact
- Query by span: <1μs for viewport

## Phase 6: Incremental Infrastructure (Weeks 11-12)

### Goals
- Coordinate updates across layers
- Cache management for queries
- Diff generation from edits

### Deliverables

#### 6.1 Edit Coordinator (`incremental/coordinator.zig`)
```zig
pub const Coordinator = struct {
    lexical: *StreamingLexer,
    structural: *StructuralParser,
    detailed: *DetailedParser,
    fact_stream: *FactStream,
    
    pub fn processEdit(self: *Coordinator, edit: Edit) EditResult {
        // 1. Update lexical layer
        // 2. Check structural impact
        // 3. Update affected boundaries
        // 4. Generate fact delta
        // 5. Update caches
    }
};
```

#### 6.2 Cache Management (`incremental/cache.zig`)
- Generation-based invalidation
- Partial cache updates
- Memory pressure handling

### Integration Tests
- Edit → Delta → Query update pipeline
- Cache hit rate > 90% for repeated queries
- Memory stability under continuous edits

## Phase 7: Structural Parser (Weeks 13-14)

### Goals
- Identify major code boundaries
- Error recovery regions
- <1ms full file parsing

### Deliverables

#### 7.1 Structural Parser (`structural/parser.zig`)
```zig
pub const StructuralParser = struct {
    pub fn parse(tokens: []Token) []StructuralNode {
        // Single pass with aggressive recovery
        // Target: <1ms for 1000 lines
    }
    
    pub fn incrementalParse(delta: TokenDelta) StructuralDelta {
        // Update only affected structures
    }
};
```

#### 7.2 Boundary Detection (`structural/boundaries.zig`)
- Function boundaries
- Class/struct boundaries
- Block boundaries
- Error recovery regions

#### 7.3 Error Recovery (`structural/recovery.zig`)
- Unmatched delimiter handling
- Malformed construct isolation
- Parse continuation strategies

### Performance Requirements
- 1000 lines: <1ms
- 10,000 lines: <10ms
- Incremental update: <0.1ms

## Phase 8: Detailed Parser Integration (Weeks 15-16)

### Goals
- Integrate existing parser as Layer 2
- Parse within boundaries only
- Viewport-focused parsing

### Integration Strategy
1. Adapt current recursive descent parser
2. Parse only visible boundaries
3. Lazy parsing for off-screen content
4. Cache parsed boundaries

### Modifications Required
```zig
// Current parser becomes boundary-aware
pub const DetailedParser = struct {
    boundary_parsers: HashMap(ParseBoundary, BoundaryParser),
    
    pub fn parseBoundary(
        self: *DetailedParser,
        boundary: ParseBoundary,
        tokens: []Token
    ) FactStream {
        // Parse single boundary
        // Convert AST to facts
    }
};
```

### Performance Targets
- Viewport parsing: <10ms
- Boundary caching: 95% hit rate
- Memory per boundary: <10KB

## Phase 9: Basic Speculation (Weeks 17-18)

### Goals
- Bracket/delimiter prediction
- Simple pattern matching
- Zero-latency for predicted edits

### Deliverables

#### 9.1 Speculation Engine (`speculation/engine.zig`)
```zig
pub const SpeculativeEngine = struct {
    predictors: []Predictor,
    active: []Speculation,
    
    pub fn onEdit(self: *SpeculativeEngine, edit: Edit) ?FactStream {
        // Check speculation match
        // Return instant results if matched
    }
    
    pub fn generatePredictions(self: *SpeculativeEngine, context: Context) void {
        // Spawn background predictions
    }
};
```

#### 9.2 Basic Predictors (`speculation/predictors/`)
- Bracket completion predictor
- Quote completion predictor
- Indent prediction
- Simple pattern matching

### Success Metrics
- Bracket prediction accuracy: >90%
- Response time when matched: 0ms
- Background parsing overhead: <10%

## Phase 10: Advanced Features & Optimization (Weeks 19-24)

### Goals
- Production-ready performance
- Advanced speculation
- Memory optimization

### Advanced Features

#### 10.1 Learning Predictors
- User pattern learning
- Grammar-based prediction
- Context-aware suggestions

#### 10.2 Ambiguity Handling
- Multiple parse hypotheses
- Confidence scoring
- Disambiguation strategies

#### 10.3 Performance Optimizations
- Lock-free data structures
- NUMA-aware allocation
- CPU cache optimization
- Memory pool tuning

### Final Benchmarks

| Operation | Target | Stretch Goal |
|-----------|--------|--------------|
| Bracket match | <1ms | <0.1ms |
| Viewport highlight | <10ms | <5ms |
| Full file symbols | <50ms | <20ms |
| Goto definition | <20ms | <10ms |
| Autocomplete | <1ms | 0ms (predicted) |

## First Production Use Case: CLI Argument Parser

### Why CLI Parser First?
1. **Dogfooding**: We use it ourselves immediately
2. **Bounded Scope**: Arguments are simple to parse
3. **Real Usage**: Validates architecture with real needs
4. **Performance Critical**: CLI startup time matters

### Implementation Plan
```zig
// Define grammar for CLI arguments
const cli_grammar = Grammar.builder()
    .define("flag", choice(&.{"-", "--"}) + identifier)
    .define("value", quoted_string | word)
    .define("argument", flag + optional(value))
    .define("command", word + repeat(argument))
    .build();

// Use stratified parser
const parser = StratifiedParser.init(cli_grammar);
const facts = parser.parse(args);

// Query for specific arguments
const help_flag = facts.query(.{
    .predicate = .IsFlag,
    .value = "help",
});
```

### Success Criteria
- Parse args in <0.1ms
- Zero allocations for common cases
- Better error messages than current

## Risk Assessment & Mitigation

### Technical Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Performance targets not met | Medium | High | Keep current parser as fallback |
| Fact model too complex | Medium | Medium | Simplify to essential facts |
| Memory usage too high | Low | High | Implement streaming mode |
| Speculation overhead | Medium | Low | Disable in batch mode |

### Schedule Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Phases take longer | High | Medium | Prioritize core features |
| Integration issues | Medium | High | Continuous integration testing |
| Performance regression | Low | High | Benchmark every commit |

## Decision Log

### Architectural Decisions

1. **Fact-First vs AST-First**
   - Decision: Fact-first
   - Rationale: Better incremental updates, lower memory
   - Trade-off: More complex initial implementation

2. **Layer Count**
   - Decision: 3 layers (lexical, structural, detailed)
   - Rationale: Balance between latency and accuracy
   - Trade-off: More coordination overhead

3. **Grammar Reuse**
   - Decision: Reuse existing grammar initially
   - Rationale: Faster development, proven correctness
   - Trade-off: May need optimization later

4. **Threading Model**
   - Decision: Start single-threaded, add parallelism later
   - Rationale: Simpler debugging, cleaner architecture
   - Trade-off: Initial performance limitations

5. **Memory Strategy**
   - Decision: Arena + pools hybrid
   - Rationale: Fast allocation, controlled lifetime
   - Trade-off: More complex memory management

## Integration with Existing zz

### Module Dependencies
```
parser/stratified/ depends on:
- lib/grammar (grammar definitions)
- lib/ast (visitor pattern for conversion)
- lib/core (allocators, pools)
- lib/filesystem (file access)
```

### Migration Path
1. Keep current parser working
2. Build stratified parser in parallel
3. Add feature flag for parser selection
4. Migrate commands one by one
5. Remove old parser when stable

### Testing Strategy
- Unit tests for each layer
- Integration tests for full pipeline
- Performance benchmarks mandatory
- Fuzz testing for robustness
- A/B testing against current parser

## Success Metrics Summary

### Phase Checkpoints

| Phase | Success Criteria | Deadline |
|-------|-----------------|----------|
| 1-2 | Foundation types compile and test | Week 4 |
| 3-4 | Lexer <0.1ms for viewport | Week 8 |
| 5-6 | Fact stream with deltas working | Week 12 |
| 7 | Structural parser <1ms | Week 14 |
| 8 | Detailed parser integrated | Week 16 |
| 9 | Basic speculation working | Week 18 |
| 10 | Production benchmarks met | Week 24 |

### Final Deliverables
1. Stratified parser meeting all latency targets
2. CLI argument parser in production
3. Performance 10x better than current
4. Memory usage <2x current
5. Documentation and examples

## Next Steps

1. **Immediate**: Create foundation types module
2. **Week 1**: Implement Span and Fact types
3. **Week 2**: Build specialized collections
4. **Week 3**: Begin lexical layer
5. **Week 4**: Integrate with existing grammar

## Conclusion

The Stratified Parser Architecture represents a fundamental advancement in parsing technology, specifically optimized for real-time editor interactions. By implementing this plan over 24 weeks, zz will have:

- **Industry-leading performance**: <1ms for critical operations
- **Modern architecture**: Fact streams and differential updates
- **Predictive capabilities**: Zero-latency through speculation
- **Production validation**: CLI parser and JSON formatter
- **Future readiness**: Foundation for LSP and editor plugins

This plan provides a realistic, incremental path from our current recursive descent parser to a state-of-the-art system that will set new standards for parsing performance and responsiveness.

---

*Document Version: 1.0*  
*Last Updated: 2025-08-17*  
*Next Review: Week 2 Checkpoint*