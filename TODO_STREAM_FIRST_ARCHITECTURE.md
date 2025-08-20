# TODO_STREAM_FIRST_ARCHITECTURE.md - Stream-First Primitive Architecture

## Executive Summary

Complete architectural redesign placing **Stream** as the fundamental primitive, with **Fact** as the universal data unit and **Span** as the location primitive. All language processing becomes stream transformations over facts. Zero-allocation design with ring buffers and arena allocators throughout.

## Core Philosophy

1. **Everything is a stream** - Files, tokens, facts, diagnostics all flow through streams
2. **Facts are the universal unit** - No AST, just facts about code spans  
3. **Zero allocations in hot paths** - Ring buffers, arenas, and object pools
4. **Incremental by default** - All operations work on deltas
5. **Language agnostic core** - Languages just produce fact streams

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

### 1. Stream Module (`src/lib/stream/`)

**Purpose**: Generic streaming infrastructure for all data flow

**Files**:
- `mod.zig` - Core Stream(T) interface and utilities
- `source.zig` - StreamSource implementations  
- `sink.zig` - StreamSink implementations
- `operators.zig` - Stream transformation operators
- `cursor.zig` - Stream navigation and bookmarking
- `buffer.zig` - Ring buffer implementations
- `scheduler.zig` - Stream scheduling and backpressure

**Core Interfaces**:
```zig
pub fn Stream(comptime T: type) type {
    return struct {
        const Self = @This();
        
        // Core operations
        nextFn: *const fn (self: *Self) StreamError!?T,
        peekFn: *const fn (self: *Self) ?T,
        skipFn: *const fn (self: *Self, n: usize) StreamError!void,
        closeFn: *const fn (self: *Self) void,
        
        // Metadata
        getPositionFn: *const fn (self: *Self) usize,
        getStatsFn: *const fn (self: *Self) StreamStats,
        
        // Composition
        pub fn map(self: *Self, comptime U: type, f: fn(T) U) Stream(U);
        pub fn filter(self: *Self, pred: fn(T) bool) Stream(T);
        pub fn batch(self: *Self, size: usize) Stream([]T);
        pub fn merge(self: *Self, other: Stream(T)) Stream(T);
        pub fn tee(self: *Self) struct { a: Stream(T), b: Stream(T) };
    };
}

pub const StreamSource = union(enum) {
    file: FileSource,
    memory: MemorySource,
    network: NetworkSource,
    generator: GeneratorSource,
};

pub const StreamSink = union(enum) {
    buffer: BufferSink,
    file: FileSink,
    channel: ChannelSink,
    null: NullSink,
};

pub const RingBuffer(comptime T: type, comptime capacity: usize) type;
pub const StreamScheduler = struct {
    pub fn schedule(streams: []Stream(any)) StreamError!void;
    pub fn handleBackpressure(stream: Stream(any)) BackpressureStrategy;
};
```

### 2. Fact Module (`src/lib/fact/`)

**Purpose**: Facts as the fundamental unit of information about code

**Files**:
- `mod.zig` - Fact type and core operations
- `store.zig` - Append-only fact storage
- `index.zig` - Multi-index for fact queries
- `delta.zig` - Incremental fact updates
- `cache.zig` - Zero-allocation fact cache
- `builder.zig` - Fluent fact construction
- `predicate.zig` - Predicate definitions

**Core Types**:
```zig
pub const FactId = u32;
pub const Generation = u32;

pub const Fact = struct {
    id: FactId,
    subject: PackedSpan,  // 8 bytes: start + length
    predicate: Predicate,  // 2 bytes: enum
    object: Value,         // 8 bytes: union
    confidence: f16,       // 2 bytes
    generation: Generation, // 4 bytes
    // Total: 24 bytes per fact
};

pub const Predicate = enum(u16) {
    // Lexical predicates
    is_token,
    has_text,
    has_kind,
    
    // Structural predicates  
    is_boundary,
    has_parent,
    has_child,
    precedes,
    follows,
    
    // Semantic predicates
    defines_symbol,
    references_symbol,
    has_type,
    has_scope,
    
    // Diagnostic predicates
    has_error,
    has_warning,
    has_suggestion,
};

pub const Value = union(enum) {
    none: void,
    number: i64,
    span: PackedSpan,
    atom: AtomId,  // Interned string
    fact: FactId,  // Reference to another fact
};

pub const FactStore = struct {
    pub fn append(self: *FactStore, fact: Fact) FactId;
    pub fn appendBatch(self: *FactStore, facts: []const Fact) []FactId;
    pub fn getGeneration(self: *FactStore) Generation;
    pub fn compact(self: *FactStore) void;
};

pub const FactIndex = struct {
    by_id: IdIndex,
    by_span: SpanIndex,
    by_predicate: PredicateIndex,
    
    pub fn find(self: *FactIndex, query: FactQuery) FactIterator;
    pub fn findInSpan(self: *FactIndex, span: Span) FactIterator;
    pub fn findByPredicate(self: *FactIndex, pred: Predicate) FactIterator;
};

pub const FactDelta = struct {
    generation: Generation,
    added: []Fact,
    removed: []FactId,
    modified: []FactModification,
    
    pub fn apply(self: FactDelta, store: *FactStore) !void;
    pub fn merge(self: FactDelta, other: FactDelta) FactDelta;
    pub fn reverse(self: FactDelta) FactDelta;
};

pub const FactCache = struct {
    arena: std.heap.ArenaAllocator,
    ring: RingBuffer(CacheEntry, 1024),
    spans: PackedSpanIndex,
    
    pub fn get(self: *FactCache, span: PackedSpan) ?[]Fact;
    pub fn put(self: *FactCache, span: PackedSpan, facts: []Fact) void;
    pub fn invalidate(self: *FactCache, span: PackedSpan) void;
};
```

### 3. Span Module (`src/lib/span/`)

**Purpose**: Efficient representation and manipulation of text locations

**Files**:
- `mod.zig` - Span types and operations
- `packed.zig` - Space-efficient span encoding
- `interval_tree.zig` - Fast overlap queries
- `viewport.zig` - Editor viewport management
- `set.zig` - SpanSet for multiple selections

**Core Types**:
```zig
pub const Span = struct {
    start: u32,
    end: u32,
    
    pub fn init(start: u32, end: u32) Span;
    pub fn len(self: Span) u32;
    pub fn contains(self: Span, pos: u32) bool;
    pub fn overlaps(self: Span, other: Span) bool;
    pub fn merge(self: Span, other: Span) Span;
    pub fn intersect(self: Span, other: Span) ?Span;
};

pub const PackedSpan = u64;  // 32-bit start + 32-bit length

pub fn packSpan(span: Span) PackedSpan;
pub fn unpackSpan(packed: PackedSpan) Span;

pub const SpanTree = struct {
    pub fn insert(self: *SpanTree, span: Span, data: anytype) void;
    pub fn remove(self: *SpanTree, span: Span) void;
    pub fn findOverlapping(self: *SpanTree, span: Span) Iterator;
    pub fn findContaining(self: *SpanTree, pos: u32) Iterator;
};

pub const Viewport = struct {
    visible: Span,
    focus: ?Span,
    
    pub fn update(self: *Viewport, new_visible: Span) Delta;
    pub fn isVisible(self: Viewport, span: Span) bool;
    pub fn prioritize(self: Viewport, spans: []Span) []Span;
};

pub const SpanSet = struct {
    spans: []Span,
    
    pub fn add(self: *SpanSet, span: Span) void;
    pub fn remove(self: *SpanSet, span: Span) void;
    pub fn normalize(self: *SpanSet) void;  // Merge overlapping
};
```

### 4. Token Module (`src/lib/token/`)

**Purpose**: Lightweight token representation for streaming

**Files**:
- `mod.zig` - StreamToken with vtable dispatch
- `buffer.zig` - Token ring buffer
- `iterator.zig` - Token stream implementation
- `pool.zig` - Pre-allocated token pools

**Core Types**:
```zig
pub const StreamToken = struct {
    span: PackedSpan,
    kind: TokenKind,
    depth: u16,
    flags: TokenFlags,
    
    // Optional vtable for language-specific operations
    vtable: ?*const TokenVTable,
    data: ?*anyopaque,
};

pub const TokenKind = enum(u16) {
    // Common kinds
    identifier, keyword, string, number, comment,
    delimiter, operator, whitespace, eof,
    // ... more
};

pub const TokenStream = Stream(StreamToken);

pub const TokenBuffer = RingBuffer(StreamToken, 4096);

pub const TokenPool = struct {
    tokens: [8192]StreamToken,
    free_list: FreeList,
    
    pub fn acquire(self: *TokenPool) *StreamToken;
    pub fn release(self: *TokenPool, token: *StreamToken) void;
};
```

### 5. Language Module (`src/lib/language/`)

**Purpose**: Language-specific adapters that produce fact streams

**Files**:
- `registry.zig` - Language registration and detection
- `adapter.zig` - Common adapter interface
- `capabilities.zig` - Language capability declarations

**Subdirectories**:
- `json/` - JSON language adapter
- `zon/` - ZON language adapter  
- `typescript/` - TypeScript adapter
- `zig/` - Zig adapter

**Core Interfaces**:
```zig
pub const LanguageAdapter = struct {
    // Metadata
    name: []const u8,
    extensions: []const []const u8,
    capabilities: LanguageCapabilities,
    
    // Stream producers
    tokenizeFn: *const fn (input: []const u8) TokenStream,
    extractFactsFn: *const fn (tokens: TokenStream) FactStream,
    
    // Optional advanced features
    formatFn: ?*const fn (facts: FactStream) []const u8,
    lintFn: ?*const fn (facts: FactStream) DiagnosticStream,
};

pub const LanguageCapabilities = packed struct {
    has_symbols: bool,
    has_types: bool,
    has_imports: bool,
    has_comments: bool,
    has_strings: bool,
    supports_incremental: bool,
    supports_streaming: bool,
    supports_formatting: bool,
};

pub const LanguageRegistry = struct {
    adapters: std.StringHashMap(LanguageAdapter),
    
    pub fn register(self: *Registry, adapter: LanguageAdapter) void;
    pub fn detect(self: *Registry, input: []const u8) ?Language;
    pub fn getAdapter(self: *Registry, lang: Language) ?LanguageAdapter;
};
```

**Example Language Implementation** (`json/adapter.zig`):
```zig
pub const JsonAdapter = LanguageAdapter{
    .name = "json",
    .extensions = &.{".json", ".jsonc"},
    .capabilities = .{
        .has_symbols = false,
        .has_types = false,
        .has_strings = true,
        .supports_streaming = true,
    },
    .tokenizeFn = tokenize,
    .extractFactsFn = extractFacts,
};

fn tokenize(input: []const u8) TokenStream {
    // Returns stream that produces tokens incrementally
}

fn extractFacts(tokens: TokenStream) FactStream {
    // Transforms token stream into fact stream
    // Facts like: is_object, has_key, has_value, etc.
}
```

### 6. Index Module (`src/lib/index/`)

**Purpose**: Unified indexing system for all facts

**Files**:
- `mod.zig` - UnifiedIndex facade
- `trie.zig` - Trie for symbol lookup
- `btree.zig` - B-tree for range queries  
- `bloom.zig` - Bloom filters for existence
- `spatial.zig` - R-tree for span queries

**Core Types**:
```zig
pub const UnifiedIndex = struct {
    facts: FactIndex,
    symbols: SymbolTrie,
    spans: SpanTree,
    generation: Generation,
    
    pub fn update(self: *UnifiedIndex, delta: FactDelta) !void;
    pub fn query(self: *UnifiedIndex, q: Query) QueryResult;
    pub fn snapshot(self: *UnifiedIndex) IndexSnapshot;
    pub fn restore(self: *UnifiedIndex, snapshot: IndexSnapshot) void;
};

pub const SymbolTrie = struct {
    pub fn insert(self: *SymbolTrie, name: []const u8, fact_id: FactId) void;
    pub fn find(self: *SymbolTrie, prefix: []const u8) Iterator;
    pub fn findExact(self: *SymbolTrie, name: []const u8) ?FactId;
};

pub const IndexSnapshot = struct {
    generation: Generation,
    facts: []Fact,
    metadata: SnapshotMetadata,
    
    pub fn compress(self: IndexSnapshot) []u8;
    pub fn decompress(data: []u8) IndexSnapshot;
};
```

### 7. Query Module (`src/lib/query/`)

**Purpose**: Powerful query engine over fact streams

**Files**:
- `mod.zig` - Query builder and executor
- `planner.zig` - Query optimization
- `operators.zig` - Query operators
- `cache.zig` - Query result caching

**Core Types**:
```zig
pub const Query = struct {
    pub fn select(predicate: Predicate) QueryBuilder;
    pub fn from(source: FactSource) QueryBuilder;
    
    pub const QueryBuilder = struct {
        pub fn where(self: *QB, field: Field, op: Op, value: Value) *QB;
        pub fn whereSpan(self: *QB, op: SpanOp, span: Span) *QB;
        pub fn join(self: *QB, other: Query, on: JoinCondition) *QB;
        pub fn groupBy(self: *QB, field: Field) *QB;
        pub fn orderBy(self: *QB, field: Field, dir: Direction) *QB;
        pub fn limit(self: *QB, n: usize) *QB;
        pub fn build(self: *QB) Query;
    };
};

pub const QueryPlan = struct {
    operators: []QueryOperator,
    estimated_cost: f32,
    
    pub fn optimize(self: *QueryPlan) void;
    pub fn explain(self: QueryPlan) []const u8;
};

pub const QueryExecutor = struct {
    pub fn execute(self: *QE, query: Query) QueryResult;
    pub fn executeStreaming(self: *QE, query: Query) Stream(Fact);
    pub fn executeBatch(self: *QE, queries: []Query) []QueryResult;
};

pub const QueryResult = union(enum) {
    facts: []Fact,
    stream: Stream(Fact),
    error: QueryError,
};
```

### 8. Transform Module (`src/lib/transform/`)

**Purpose**: Composable stream transformation pipelines

**Files**:
- `mod.zig` - Pipeline builder
- `stages.zig` - Common transformation stages
- `parallel.zig` - Parallel stream processing
- `fusion.zig` - Pipeline optimization

**Core Types**:
```zig
pub const Pipeline = struct {
    stages: []Stage,
    
    pub fn addStage(self: *Pipeline, stage: Stage) *Pipeline;
    pub fn optimize(self: *Pipeline) void;  // Fuse stages
    pub fn run(self: *Pipeline, input: Stream(any)) Stream(any);
};

pub const Stage = union(enum) {
    map: MapStage,
    filter: FilterStage,
    flatMap: FlatMapStage,
    window: WindowStage,
    aggregate: AggregateStage,
    custom: CustomStage,
};

pub const ParallelPipeline = struct {
    workers: []Worker,
    scheduler: WorkScheduler,
    
    pub fn split(self: *PP, input: Stream(any)) []Stream(any);
    pub fn merge(self: *PP, streams: []Stream(any)) Stream(any);
};
```

### 9. Protocol Module (`src/lib/protocol/`)

**Purpose**: Integration with editors and tools

**Files**:
- `lsp.zig` - Language Server Protocol
- `dap.zig` - Debug Adapter Protocol
- `streaming.zig` - Custom streaming protocol

**Core Types**:
```zig
pub const LspServer = struct {
    index: *UnifiedIndex,
    pipelines: std.StringHashMap(Pipeline),
    
    pub fn handleRequest(self: *LS, req: LspRequest) LspResponse;
    pub fn streamDiagnostics(self: *LS) Stream(Diagnostic);
};

pub const StreamingProtocol = struct {
    pub fn negotiate(capabilities: []const u8) Protocol;
    pub fn streamFacts(facts: Stream(Fact)) void;
    pub fn receiveCommands() Stream(Command);
};
```

## Memory Management Strategy

### Arena Allocation Pattern
```zig
pub const ArenaPool = struct {
    arenas: [4]std.heap.ArenaAllocator,
    current: usize,
    
    pub fn acquire(self: *ArenaPool) *std.heap.ArenaAllocator;
    pub fn release(self: *ArenaPool, arena: *std.heap.ArenaAllocator) void;
    pub fn rotate(self: *ArenaPool) void;  // For generational collection
};
```

### Ring Buffer Pattern
```zig
pub fn RingBuffer(comptime T: type, comptime capacity: usize) type {
    return struct {
        items: [capacity]T,
        head: usize,
        tail: usize,
        
        pub fn push(self: *@This(), item: T) void;
        pub fn pop(self: *@This()) ?T;
        pub fn isFull(self: @This()) bool;
        pub fn clear(self: *@This()) void;
    };
}
```

### String Interning
```zig
pub const AtomTable = struct {
    strings: std.ArrayList([]const u8),
    lookup: std.StringHashMap(AtomId),
    
    pub fn intern(self: *AtomTable, str: []const u8) AtomId;
    pub fn lookup(self: AtomTable, id: AtomId) []const u8;
};
```

## Migration Path

### Phase 1: Core Infrastructure (Week 1-2)
1. Create `stream/` module with generic Stream(T) implementation
2. Create `fact/` module with Fact type and FactStore
3. Create `span/` module with PackedSpan optimization
4. Write comprehensive tests for core primitives

### Phase 2: Adapt Existing Code (Week 3-4)
1. Migrate token types to use StreamToken
2. Convert existing lexers to produce TokenStream
3. Add fact extraction to JSON/ZON languages
4. Replace BoundaryCache with FactCache

### Phase 3: Build Index and Query (Week 5-6)
1. Implement UnifiedIndex with multi-indexing
2. Build query engine with optimization
3. Add streaming query execution
4. Create query result caching

### Phase 4: Language Adapters (Week 7-8)
1. Refactor existing languages to adapter pattern
2. Implement fact extraction for each language
3. Add streaming support throughout
4. Remove old AST-based code

### Phase 5: Integration (Week 9-10)
1. Update CLI commands to use new primitives
2. Add LSP protocol support
3. Performance optimization
4. Documentation and examples

## Performance Targets

- **Stream throughput**: >1M tokens/second
- **Fact insertion**: >100K facts/second  
- **Query latency**: <1ms for typical queries
- **Memory overhead**: <10MB for 100K LOC
- **Zero allocations**: In all hot paths
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

## Next Steps

1. Review and refine this design
2. Create TODO_STREAM_FIRST_IMPLEMENTATION.md with detailed tasks
3. Set up new directory structure
4. Begin Phase 1 implementation
5. Validate with performance benchmarks

This architecture fundamentally simplifies zz while making it more powerful and performant.