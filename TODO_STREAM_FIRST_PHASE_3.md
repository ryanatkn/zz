# TODO_STREAM_FIRST_PHASE_3.md - Query Engine & Direct Lexers

## Phase 3 Overview
Build the query engine with SQL-like DSL and implement direct stream lexers, eliminating the temporary bridge layer.

## Timeline: Weeks 7-10

## Core Goals
1. **Query Engine**: SQL-like DSL for fact queries
2. **Direct Stream Lexers**: Zero-allocation streaming for JSON/ZON
3. **Performance Benchmarks**: Validate 1-2 cycle dispatch claim
4. **Language Migration**: TypeScript, Zig, CSS, HTML, Svelte

## Module Specifications

### 1. Query Module (`src/lib/query/`)

**Purpose**: Powerful query engine over fact streams

**Core Interface**:
```zig
// Query builder with SQL-like DSL
pub const QueryBuilder = struct {
    pub fn select(predicates: []const Predicate) QueryBuilder;
    pub fn from(store: *FactStore) QueryBuilder;
    pub fn where(field: Field, op: Op, value: Value) QueryBuilder;
    pub fn groupBy(field: Field) QueryBuilder;
    pub fn orderBy(field: Field, dir: Direction) QueryBuilder;
    pub fn limit(n: usize) QueryBuilder;
    pub fn execute(self: QueryBuilder) QueryResult;
};

// Query optimization
pub const QueryOptimizer = struct {
    pub fn optimize(query: Query) Query;
    pub fn selectIndex(query: Query, indices: []Index) ?Index;
    pub fn estimateCost(query: Query) f64;
};

// Streaming query execution
pub const QueryExecutor = struct {
    pub fn executeStream(query: Query) Stream(Fact);
    pub fn executeParallel(query: Query, workers: usize) Stream(Fact);
};
```

**Example Usage**:
```zig
// Find all functions with high confidence
const functions = QueryBuilder.init()
    .select(&.{.is_function})
    .from(&fact_store)
    .where(.confidence, .gte, 0.9)
    .orderBy(.span, .ascending)
    .limit(100)
    .execute();

// Complex aggregation query
const stats = QueryBuilder.init()
    .select(&.{.has_text, .is_identifier})
    .from(&fact_store)
    .groupBy(.predicate)
    .having(.count, .gt, 10)
    .execute();
```

### 2. Direct Stream Lexers

**Purpose**: Replace bridge with native streaming lexers

**JSON Stream Lexer** (`src/lib/languages/json/stream_lexer.zig`):
```zig
pub const JsonStreamLexer = struct {
    state: LexerState,
    buffer: RingBuffer(u8, 4096),
    
    pub fn init(allocator: Allocator) JsonStreamLexer;
    
    // Zero-allocation streaming
    pub fn tokenizeStream(self: *JsonStreamLexer, reader: anytype) Stream(StreamToken) {
        return Stream(StreamToken){
            .context = self,
            .nextFn = nextToken,
        };
    }
    
    fn nextToken(ctx: *anyopaque) ?StreamToken {
        const self = @ptrCast(*JsonStreamLexer, ctx);
        // Direct production of StreamToken without intermediate allocation
    }
};
```

**Benefits over Bridge**:
- No intermediate token array allocation
- Direct StreamToken production (no conversion)
- Streaming from any reader (file, network, memory)
- Backpressure support
- ~10x less memory usage

### 3. Performance Benchmark Suite

**Location**: `src/benchmark/stream_first/`

**Benchmarks to Implement**:
```zig
// Token dispatch performance
test "benchmark: tagged union vs vtable dispatch" {
    // Measure cycles for:
    // - Tagged union dispatch (target: 1-2 cycles)
    // - VTable dispatch (baseline: 3-5 cycles)
    // - Direct call (optimal: 1 cycle)
}

// Memory usage
test "benchmark: token memory overhead" {
    // Verify:
    // - StreamToken ≤ 24 bytes
    // - Language tokens = 16 bytes
    // - Zero allocations in steady state
}

// Throughput
test "benchmark: tokenization throughput" {
    // Target: >10MB/sec source text
    // Measure: tokens/second, bytes/second
}

// Query performance
test "benchmark: fact query latency" {
    // Simple queries: <1μs
    // Complex queries: <1ms
    // Aggregations: <10ms
}
```

### 4. Language Migration Plan

**Priority Order**:
1. **JSON** - Most common, simplest grammar
2. **ZON** - Similar to JSON, Zig-specific
3. **TypeScript** - Complex but high value
4. **Zig** - Native language support
5. **CSS** - Different paradigm (stylesheets)
6. **HTML** - Markup language
7. **Svelte** - Multi-language (defer to Phase 4)

**Migration Steps per Language**:
1. Implement stream lexer
2. Update fact extraction
3. Remove bridge dependency
4. Add comprehensive tests
5. Benchmark against old implementation

## Implementation Tasks

### Week 1: Query Engine Core
- [ ] Create query module structure
- [ ] Implement QueryBuilder with basic operations
- [ ] Add Query type with AST representation
- [ ] Implement basic executor (no optimization)
- [ ] Write query engine tests

### Week 2: Query Optimization
- [ ] Implement QueryOptimizer
- [ ] Add index selection logic
- [ ] Implement cost estimation
- [ ] Add query plan caching
- [ ] Benchmark query performance

### Week 3: Direct Stream Lexers
- [ ] Implement JSON stream lexer
- [ ] Implement ZON stream lexer
- [ ] Remove bridge dependency for JSON/ZON
- [ ] Verify zero allocations
- [ ] Add streaming tests

### Week 4: Performance & Migration
- [ ] Create benchmark suite
- [ ] Validate performance targets
- [ ] Migrate TypeScript lexer
- [ ] Migrate Zig lexer
- [ ] Update documentation

## Success Criteria

### Performance Targets
- [x] Token dispatch: 1-2 cycles (already achieved)
- [ ] Query latency: <1μs for simple queries
- [ ] Streaming throughput: >10MB/sec
- [ ] Memory usage: O(1) for streaming
- [ ] Zero allocations in hot paths

### Quality Metrics
- [ ] All Phase 2 tests still passing
- [ ] New query tests comprehensive
- [ ] Direct lexer tests passing
- [ ] No performance regressions
- [ ] Documentation complete

## Risk Mitigation

### Risk: Query Performance
**Mitigation**: Start with simple queries, optimize incrementally

### Risk: Breaking Changes
**Mitigation**: Keep bridge as fallback until direct lexers proven

### Risk: Language Complexity
**Mitigation**: Start with simple languages (JSON/ZON), defer complex ones

## Dependencies

### On Phase 2
- StreamToken type (complete)
- Fact storage (complete)
- Cache infrastructure (complete)
- AtomTable (complete)

### External
- None - pure Zig implementation

## Open Questions

1. **Query Language Syntax**: SQL-like or custom DSL?
2. **Parallel Execution**: How many worker threads?
3. **Query Caching**: LRU or adaptive replacement?
4. **Streaming Backpressure**: Token-level or chunk-level?

## Phase 3 Completion Checklist

- [ ] Query engine with SQL-like DSL
- [ ] Direct stream lexers for JSON/ZON
- [ ] Performance benchmarks validated
- [ ] 2+ additional languages migrated
- [ ] Bridge code marked for deletion
- [ ] Documentation updated
- [ ] All tests passing (or documented)

## Notes

### Design Decisions
1. **SQL-like DSL**: Familiar to developers, powerful
2. **Stream-first lexers**: Eliminate allocation overhead
3. **Query optimization**: Critical for large fact stores
4. **Incremental migration**: Reduce risk, maintain stability

### Future Optimizations (Phase 4+)
1. **SIMD query execution**: Vectorized fact comparison
2. **Query compilation**: JIT compile hot queries
3. **Distributed queries**: Multi-machine fact stores
4. **Persistent indices**: Disk-backed query indices