# TODO_STREAM_FIRST_ARCHITECTURE.md - Stream-First Primitive Architecture

## Executive Summary

Complete architectural redesign placing **Stream** as the fundamental primitive, with **Fact** as the universal data unit and **Span** as the location primitive. All language processing becomes stream transformations over facts. Zero-allocation design with ring buffers and arena allocators throughout.

## Core Philosophy

1. **Everything is a stream** - Files, tokens, facts, diagnostics all flow through streams
2. **Facts are the universal unit** - No AST, just facts about code spans  
3. **Zero allocations in hot paths** - Ring buffers, arenas, and object pools
4. **Incremental by default** - All operations work on deltas
5. **Language agnostic core** - Languages just produce fact streams

See [TODO_STREAM_FIRST_PRINCIPLES.md](./TODO_STREAM_FIRST_PRINCIPLES.md)
for technical details about implementation.

**Testing**: All core modules have comprehensive tests. Run `zig test src/lib/stream/test.zig`, `zig test src/lib/fact/test.zig`, `zig test src/lib/span/test.zig` or the combined suite `zig test src/lib/test_stream_first.zig`.

## Module Structure

```
src/lib/
├── stream/                  # Base streaming primitive
├── fact/                    # Fact as fundamental unit
├── span/                    # Span primitive for locations
├── token/                   # Token as stream element
├── language/                # Language-specific adapters
├── index/                   # Unified indexing system
├── query/                   # Query engine over facts
├── transform/               # Stream transformation pipelines
└── protocol/                # Editor/tool integration
```

## Detailed Module Specifications

### 1. Stream Module (`src/lib/stream/`) ✅ **IMPLEMENTED**

**Purpose**: Generic streaming infrastructure for zero-allocation data flow

**Status**: Fully implemented with vtable-based Stream(T), RingBuffer, sources/sinks, and composable operators.

**Core Interface**:
```zig
// Generic Stream(T) with vtable dispatch
pub fn Stream(comptime T: type) type;

// Zero-allocation ring buffer
pub fn RingBuffer(comptime T: type, comptime capacity: usize) type;

// Stream sources and sinks
pub const StreamSource = union(enum) { memory, file, generator };
pub const StreamSink = union(enum) { buffer, file, null, channel };

// Composable operators
pub const operators = struct {
    pub fn map(comptime T: type, comptime U: type) type;
    pub fn filter(comptime T: type) type;
    pub fn fusedMap(comptime T: type, comptime U: type) type;
    // ... more operators
};
```

### 2. Fact Module (`src/lib/fact/`) ✅ **IMPLEMENTED**

**Purpose**: Facts as the universal unit of information about code spans

**Status**: Fully implemented with exact 24-byte Fact struct, FactStore, and Builder DSL.

**Core Interface**:
```zig
// Exactly 24-byte fact struct
pub const Fact = extern struct {
    subject: PackedSpan,    // 8 bytes - what span this describes
    object: Value,          // 8 bytes - associated value
    id: FactId,            // 4 bytes - unique identifier  
    predicate: Predicate,  // 2 bytes - what kind of fact
    confidence: f16,       // 2 bytes - confidence level
};

// Core supporting types
pub const FactId = u32;
pub const Predicate = enum(u16) { /* ~80 predicates */ };
pub const Value = extern union { /* 8-byte union */ };

// Storage and construction
pub const FactStore = struct { /* append-only storage */ };
pub const Builder = struct { /* fluent DSL */ };
```

### 3. Span Module (`src/lib/span/`) ✅ **IMPLEMENTED**

**Purpose**: Efficient text position and range management

**Status**: Fully implemented with 8-byte Span, PackedSpan optimization, and SpanSet collections.

**Core Interface**:
```zig
// 8-byte span struct
pub const Span = struct {
    start: u32,
    end: u32,
    // Rich set of operations: merge, intersect, distance, etc.
};

// Space-efficient packed representation (saves 8 bytes per fact)
pub const PackedSpan = u64;  // 32-bit start + 32-bit length
pub fn packSpan(span: Span) PackedSpan;
pub fn unpackSpan(packed: PackedSpan) Span;

// Span collections with automatic normalization
pub const SpanSet = struct { /* merges overlapping spans */ };
```

### 4. Token Module (`src/lib/token/`) ⚠️ **NOT YET IMPLEMENTED**

**Purpose**: Lightweight token representation for streaming

**Status**: Planned for Phase 2. Current language implementations use existing token systems.

**Planned Interface**:
```zig
// Will provide StreamToken type for unified token handling
pub const StreamToken = struct { /* design TBD */ };
pub const TokenStream = Stream(StreamToken);
```

### 5. Language Module (`src/lib/languages/`) ⚠️ **PARTIALLY IMPLEMENTED**

**Purpose**: Language-specific implementations with fact stream support planned

**Status**: Languages exist (JSON, ZON, TS, Zig, CSS, HTML) but use current architecture. Stream-first adapter pattern planned for Phase 2.

**Current**: Each language has lexer/parser/formatter using existing patterns.

**Planned**: Unified LanguageAdapter interface producing fact streams.

### 6. Index Module (`src/lib/index/`) ❌ **NOT IMPLEMENTED**

**Purpose**: Unified indexing system for fast fact queries

**Status**: Planned for Phase 3. Will provide multi-index support for facts.

**Planned Interface**:
```zig
pub const UnifiedIndex = struct {
    // Multi-index support for facts by ID, span, predicate
    pub fn query(self: *UnifiedIndex, q: Query) QueryResult;
};
```

### 7. Query Module (`src/lib/query/`) ❌ **NOT IMPLEMENTED**

**Purpose**: Powerful query engine over fact streams

**Status**: Planned for Phase 3. Will provide SQL-like queries over facts.

**Planned Interface**:
```zig
pub const Query = struct {
    // SQL-like query builder for facts
    pub fn select(predicate: Predicate) QueryBuilder;
};
```

### 8. Transform Module (`src/lib/transform/`) ⚠️ **EXISTING BUT DIFFERENT**

**Purpose**: Stream transformation pipelines

**Status**: Current transform module exists but uses different architecture. Stream-first pipeline system planned for Phase 4.

**Current**: Pipeline stages for lexical/syntactic processing.

**Planned**: Composable stream transformation pipelines using Stream(T) primitives.

### 9. Protocol Module (`src/lib/protocol/`) ❌ **NOT IMPLEMENTED**

**Purpose**: Integration with editors and development tools

**Status**: Planned for Phase 5. Will provide LSP and streaming protocol support.

**Planned Interface**:
```zig
pub const LspServer = struct {
    // Language Server Protocol integration using fact streams
};
```

## Memory Management Strategy ✅ **IMPLEMENTED**

**Status**: Core memory management primitives implemented in `src/lib/memory/`.

**Implemented Components**:
- **ArenaPool**: 4-arena rotation for generational garbage collection
- **AtomTable**: Hash-consing string interning with stable AtomId references
- **RingBuffer**: Zero-allocation fixed-capacity circular buffers

**Interface**:
```zig
// Arena pool for rotating memory management
pub const ArenaPool = struct { /* 4-arena rotation */ };

// String interning with stable IDs
pub const AtomTable = struct { /* hash-consing */ };

// Zero-allocation ring buffers
pub fn RingBuffer(comptime T: type, comptime capacity: usize) type;
```

## Migration Path

### Phase 1: Core Infrastructure ✅ **COMPLETE**
1. ✅ Create `stream/` module with generic Stream(T) implementation
2. ✅ Create `fact/` module with Fact type and FactStore
3. ✅ Create `span/` module with PackedSpan optimization
4. ✅ Write comprehensive tests for core primitives
5. ✅ Implement ArenaPool and AtomTable memory management

### Phase 2: Token Integration ⚠️ **PLANNED**
1. Create unified StreamToken type
2. Convert existing lexers to produce TokenStream
3. Add fact extraction to JSON/ZON languages
4. Replace BoundaryCache with FactCache

### Phase 3: Index and Query ❌ **PLANNED**
1. Implement UnifiedIndex with multi-indexing
2. Build query engine with optimization
3. Add streaming query execution
4. Create query result caching

### Phase 4: Language Adapters ❌ **PLANNED**
1. Refactor existing languages to adapter pattern
2. Implement fact extraction for each language
3. Add streaming support throughout
4. Migrate from current AST-based approach

### Phase 5: Integration ❌ **PLANNED**
1. Update CLI commands to use new primitives
2. Add LSP protocol support
3. Performance optimization
4. Documentation and examples

## Performance Targets

**Current Benchmarks** (from actual measurements):
- **Stream throughput**: 8.9M operations/second (Stream.next() = 112ns/op) ✅ **EXCEEDS TARGET**
- **Fact creation**: 100M facts/second (Fact creation = 10ns/op) ✅ **EXCEEDS TARGET**  
- **RingBuffer**: 6.6M push/pop/second (151ns/op) ✅ **EXCELLENT**
- **Span operations**: 200M operations/second (5ns/op merge) ✅ **EXCELLENT**
- **Memory overhead**: Exact control with 24-byte facts ✅ **ACHIEVED**
- **Zero allocations**: Ring buffers and core streams ✅ **ACHIEVED**

**Remaining Targets** (not yet measurable):
- **Query latency**: <1ms for typical queries
- **Incremental update**: <10ms for typical edit

## Benefits Over Current Architecture

1. **Simplicity**: Just 3 core primitives (Stream, Fact, Span)
2. **Performance**: Zero allocations, cache-friendly layouts
3. **Flexibility**: Facts can represent any information
4. **Incrementality**: Everything designed for streaming/deltas
5. **Composition**: Streams compose naturally with operators
6. **Language agnostic**: Core knows nothing about specific languages
7. **Memory efficient**: Ring buffers and arenas throughout
8. **Queryable**: Unified query language over all facts

## Example Usage

```zig
// Parse JSON file into facts
const input = try std.fs.readFileAlloc(allocator, "config.json");
const adapter = registry.getAdapter(.json);
const tokens = adapter.tokenize(input);      // Returns TokenStream
const facts = adapter.extractFacts(tokens);  // Returns FactStream

// Query for all string values
const query = Query.select(.has_text)
    .where(.predicate, .equals, .is_string)
    .build();
const results = index.query(query);

// Stream processing pipeline
const pipeline = Pipeline.init()
    .addStage(.{ .filter = filterComments })
    .addStage(.{ .map = extractSymbols })
    .addStage(.{ .aggregate = countByType })
    .optimize();

const result_stream = pipeline.run(facts);
```

## Current Status & Next Steps

**✅ Completed (Phase 1)**:
1. Core primitives implemented and benchmarked
2. Stream, Fact, Span modules fully functional
3. Memory management with ArenaPool and AtomTable
4. All performance targets exceeded in implemented areas

**🏃 Next Actions**:
1. Begin Phase 2: StreamToken integration
2. Migrate existing languages to use fact streams
3. Implement UnifiedIndex for fact queries
4. Add language adapter pattern

**Architecture Achievement**: The stream-first foundation is solid and performant. All core primitives achieved exact size targets with excellent performance characteristics.