# Stratified Parser Architecture: Current Implementation

## Overview

The zz Stratified Parser is a three-layer parsing architecture designed for exceptional editor support, implementing key concepts from the original design document while adapting them for pure Zig implementation. This document describes the current state of the implementation.

## Architecture Principles

### Core Design Goals (From Original)
1. **Stratified Latency**: Different editor operations have different latency requirements
2. **Fact-Based IR**: Parse trees are views over immutable fact streams
3. **Zero-Copy Incrementalism**: Edits produce fact deltas, not tree rebuilds
4. **Speculative Parallelism**: Multiple parse hypotheses run concurrently (planned)

### Implementation Decisions
1. **Pure Zig**: No FFI overhead, complete control over memory and performance
2. **Rule ID System**: 16-bit rule IDs replace string comparisons (10-100x performance gain)
3. **AST Integration**: Hybrid approach using traditional AST with fact conversion
4. **Unified Language Support**: Shared infrastructure across 7+ languages

## Three-Layer Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Application Layer                      │
│              (Format, Prompt, Tree Commands)              │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│                  Fact Storage System                      │
│         (FactIndex, QueryCache, Memory Pools)            │
└──┬──────────────┬───────────────┬──────────────────────┘
   │              │               │                  
┌──▼───┐   ┌─────▼──────┐ ┌─────▼──────┐   
│Layer │   │   Layer    │ │   Layer    │   
│  0   │   │     1      │ │     2      │   
│Lexer │   │ Structural │ │  Detailed  │   
└──────┘   └────────────┘ └────────────┘   
```

### Layer 0: Lexical (StreamingLexer)

**Purpose**: Tokenization and basic classification  
**Status**: ✅ Framework implemented, needs optimization  
**Location**: `src/lib/parser/lexical/`

```zig
pub const StreamingLexer = struct {
    scanner: Scanner,           // Character-level scanning
    bracket_tracker: BracketTracker,  // Real-time bracket depth
    buffer: Buffer,             // Zero-copy token generation
    generation: Generation,     // For incremental updates
};
```

**Key Components**:
- `Scanner`: UTF-8 aware character scanning with lookahead
- `BracketTracker`: O(1) bracket depth tracking and pair matching
- `Buffer`: Zero-copy buffer management for token text
- `TokenDelta`: Incremental update representation

**Performance Targets vs Current**:
- Target: <0.1ms for viewport (50 lines)
- Current: ~0.2ms (needs SIMD optimization)

### Layer 1: Structural (StructuralParser)

**Purpose**: Identify major boundaries (functions, classes, blocks)  
**Status**: ⚠️ Basic implementation, error recovery incomplete  
**Location**: `src/lib/parser/structural/`

```zig
pub const StructuralParser = struct {
    state_machine: StateMachine,     // O(1) state transitions
    boundary_detector: BoundaryDetector,  // Block detection
    error_recovery: ErrorRecovery,   // Bracket synchronization
    matchers: LanguageMatchers,      // Language-specific patterns
};
```

**Key Components**:
- `StateMachine`: Efficient parsing state with stack management
- `BoundaryDetector`: Identifies parse boundaries for Layer 2
- `ErrorRecovery`: Recovery points and error regions
- `LanguageMatchers`: Per-language boundary patterns

**Boundary Types Detected**:
```zig
pub const BoundaryKind = enum {
    function,
    class,
    block,
    module,
    error_recovery_region,
};
```

**Performance Targets vs Current**:
- Target: <1ms for full file (1000 lines)
- Current: ~2ms (needs parallel boundary detection)

### Layer 2: Detailed (DetailedParser)

**Purpose**: Full syntax tree within boundaries  
**Status**: ⚠️ Hybrid implementation using traditional parser  
**Location**: `src/lib/parser/detailed/`

```zig
pub const DetailedParser = struct {
    parser: Parser,                  // Traditional recursive descent
    boundary_parser: BoundaryParser, // Boundary-aware parsing
    viewport_manager: ViewportManager, // Parsing prioritization
    fact_generator: FactGenerator,   // AST to facts conversion
    cache: BoundaryCache,            // LRU boundary cache
    disambiguator: Disambiguator,    // Ambiguity resolution
};
```

**Key Innovation - Viewport-Aware Parsing**:
```zig
pub fn parseViewport(self: *DetailedParser, 
                     viewport: Span, 
                     boundaries: []const ParseBoundary,
                     tokens: []const Token) !FactStream {
    // 1. Prioritize visible boundaries
    const visible = self.viewport_manager.getVisibleBoundaries();
    
    // 2. Check cache for already-parsed boundaries
    for (visible) |boundary| {
        if (self.cache.get(boundary.span)) |cached_facts| {
            // Use cached results
            continue;
        }
        // Parse and cache new boundary
    }
    
    // 3. Start predictive parsing for nearby boundaries
    self.startPredictiveParsing(); // Background work
}
```

**Performance Targets vs Current**:
- Target: <10ms for viewport
- Current: ~15ms (cache helps, needs speculative execution)

## Fact-Based Intermediate Representation

### Core Fact Type

```zig
pub const Fact = struct {
    id: FactId,              // Unique identifier (u32)
    subject: Span,           // Text span this describes
    predicate: Predicate,    // What information it conveys
    object: ?Value,          // Optional associated value
    confidence: f32,         // 0.0 to 1.0 confidence
    generation: Generation,  // For incremental updates
};
```

### Predicate Categories

The predicate system organizes facts into categories for efficient querying:

```zig
pub const Predicate = union(enum) {
    // Lexical (Layer 0)
    is_token: TokenKind,
    has_text: []const u8,
    bracket_depth: u16,
    
    // Structural (Layer 1)
    is_boundary: BoundaryKind,
    is_error_region,
    is_foldable,
    indent_level: u16,
    
    // Syntactic (Layer 2)
    is_node: NodeKind,
    has_child: FactId,
    has_parent: FactId,
    
    // Semantic (Analysis)
    binds_symbol: SymbolId,
    references_symbol: SymbolId,
    has_type: TypeId,
};
```

### Fact Indexing System

The `FactIndex` provides multiple access patterns for efficient querying:

```zig
pub const FactIndex = struct {
    by_id: HashMap(FactId, Fact),           // O(1) lookup
    by_span: SpanIndex,                     // O(log n) spatial queries
    by_predicate: HashMap(Category, List),   // O(1) category lookup
    by_generation: HashMap(Generation, List), // O(1) generation lookup
    parent_child: HashMap(FactId, List),     // O(1) hierarchy
};
```

## Incremental Updates (Partial Implementation)

### Current Delta System

```zig
pub const FactDelta = struct {
    added: []const Fact,
    removed: []const Fact,
    modified: []const Fact,
    
    pub fn isEmpty(self: FactDelta) bool {
        return self.added.len == 0 and 
               self.removed.len == 0 and 
               self.modified.len == 0;
    }
};
```

### Update Flow (Current)

1. **Edit arrives** → TokenDelta generated (Layer 0)
2. **Token changes** → StructuralDelta if boundaries affected (Layer 1)  
3. **Boundary changes** → Detailed reparse within boundary (Layer 2)
4. **Facts generated** → FactDelta produced
5. **Cache invalidated** → Affected queries recomputed

### Missing: True Incremental Parsing

The original design's differential update system isn't fully implemented:
- ❌ No fact retraction/assertion tracking
- ❌ No incremental query updates
- ❌ No generation-based cache invalidation
- ✅ Basic cache invalidation by span

## Query System

### Query Types

```zig
pub const Query = union(enum) {
    overlapping_span: Span,
    by_category: PredicateCategory,
    by_generation: Generation,
    containing_position: usize,
    by_predicate: Predicate,
    complex: ComplexQuery,
};
```

### Query Cache

```zig
pub const QueryCache = struct {
    entries: HashMap(QueryId, CacheEntry),
    generation: Generation,
    max_entries: usize,
    ttl_seconds: i64,
    
    // Invalidation by span or generation
    pub fn invalidateSpan(self: *QueryCache, span: Span) void;
    pub fn invalidateGeneration(self: *QueryCache, gen: Generation) void;
};
```

## Memory Management

### Pool System

```zig
pub const FactPoolManager = struct {
    fact_pool: FactPool,         // Fixed-size fact allocation
    array_pool: FactIdArrayPool, // Reusable arrays
    arena: FactArena,           // Bulk allocation
    
    // Generation-based cleanup
    pub fn nextGeneration(self: *FactPoolManager) Generation;
};
```

### Performance Characteristics

Current memory usage per 1000-line file:
- Token stream: ~100KB (1000 tokens × 100 bytes)
- Structural facts: ~50KB (100 boundaries × 500 bytes)
- Detailed facts: ~500KB (10,000 facts × 50 bytes)
- Indices: ~1MB (2× fact storage)
- **Total: ~1.7MB** (Target was 2MB ✅)

## Integration with Language Support

### Unified Language Interface

All languages implement the same fact generation pattern:

```zig
pub const LanguageSupport = struct {
    // Layer 0: Tokenization
    lexer: *const fn(source: []const u8) []Token,
    
    // Layer 1: Boundaries
    detectBoundaries: *const fn(tokens: []Token) []ParseBoundary,
    
    // Layer 2: Detailed parsing
    parseDetailed: *const fn(boundary: ParseBoundary, 
                           tokens: []Token) !AST,
    
    // Fact generation
    generateFacts: *const fn(ast: AST, 
                           gen: Generation) []Fact,
};
```

### Supported Languages

| Language | Lexer | Boundaries | Detailed | Facts |
|----------|-------|------------|----------|-------|
| JSON     | ✅    | ✅         | ✅       | ⚠️    |
| ZON      | ✅    | ✅         | ✅       | ⚠️    |
| TypeScript| ✅   | ⚠️         | ⚠️       | ❌    |
| Zig      | ✅    | ⚠️         | ⚠️       | ❌    |
| CSS      | ✅    | ⚠️         | ⚠️       | ❌    |
| HTML     | ✅    | ⚠️         | ⚠️       | ❌    |
| Svelte   | ⚠️    | ❌         | ❌       | ❌    |

## Performance Analysis

### Current vs Target Latencies

| Operation | Target | Current | Status |
|-----------|--------|---------|--------|
| Bracket matching | <1ms | 0.1ms | ✅ Exceeds |
| Viewport tokenize | <0.1ms | 0.2ms | ⚠️ Close |
| Boundary detection | <1ms | 2ms | ⚠️ Needs work |
| Viewport parse | <10ms | 15ms | ⚠️ Needs cache |
| Full file parse | <50ms | 80ms | ❌ Too slow |
| Incremental update | <5ms | 10ms | ⚠️ Needs optimization |

### Bottlenecks Identified

1. **No SIMD optimizations** in lexer
2. **Sequential boundary parsing** (should be parallel)
3. **No speculative execution** for predictive parsing
4. **AST conversion overhead** instead of direct fact generation
5. **Cache misses** on viewport changes

## What's Working Well

1. **Rule ID System**: Massive performance win over string comparisons
2. **Fact Indexing**: Multi-index structure enables fast queries
3. **Memory Pools**: Efficient allocation and cleanup
4. **Span Operations**: Comprehensive and fast (<10ns per op)
5. **Unified Architecture**: Clean separation of concerns

## What Needs Work

1. **Speculative Execution**: Core innovation not implemented
2. **True Incremental Parsing**: Delta system incomplete
3. **Parallel Processing**: No concurrent boundary parsing
4. **SIMD Optimizations**: Lexer could be much faster
5. **Direct Fact Generation**: AST intermediate step adds overhead

## Next Steps

See [stratified-parser-roadmap.md](stratified-parser-roadmap.md) for detailed implementation plan.

## Code Examples

### Basic Usage

```zig
const parser = @import("lib/parser/mod.zig");

// Initialize three-layer parser
var lexer = try parser.StreamingLexer.init(allocator, config);
var structural = try parser.StructuralParser.init(allocator, config);
var detailed = try parser.DetailedParser.init(allocator);

// Parse with stratified approach
const tokens = try lexer.tokenize(source);
const boundaries = try structural.parse(tokens);
const facts = try detailed.parseViewport(viewport, boundaries, tokens);

// Query facts
const query = parser.queryOverlappingSpan(viewport);
const results = try fact_system.queryFacts(query, allocator);
```

### Incremental Update

```zig
// Process an edit
const edit = Edit.init(span, new_text, generation);
const token_delta = try lexer.processEdit(edit);

// Only reparse affected boundaries
if (token_delta.affectsStructure()) {
    const structural_delta = try structural.processDelta(token_delta);
    const fact_delta = try detailed.processEdit(edit, 
                                               affected_boundaries, 
                                               tokens);
    
    // Update fact storage
    try fact_system.applyDelta(fact_delta);
}
```

## Conclusion

The Stratified Parser implementation successfully demonstrates the core architectural concepts while adapting them for pure Zig. The three-layer architecture provides good separation of concerns, and the fact-based IR enables flexible querying. However, key performance features like speculative execution and true incremental parsing remain to be implemented to achieve the original vision's full potential.