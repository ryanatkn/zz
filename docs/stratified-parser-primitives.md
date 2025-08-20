# Stratified Parser Core Primitives

## Overview

This document details the fundamental types and data structures that form the foundation of the Stratified Parser. These primitives are designed for high performance, zero-copy operations, and efficient incremental updates.

## Core Type Hierarchy

```
Foundation Types
├── Span           - Text position and range management
├── Fact           - Immutable information about text
├── Token          - Lexical unit with span and kind
├── Predicate      - Fact classification system
└── Generation     - Update tracking counter

Collection Types
├── FactIndex      - Multi-index fact storage
├── QueryCache     - Cached query results
├── FactStream     - Streaming fact processor
└── FactDelta      - Incremental changes

Parser Types
├── Edit           - Text modification
├── TokenDelta     - Token stream changes
├── ParseBoundary  - Structural boundary
└── StructuralDelta - Boundary changes
```

## Foundation Types

### Span - The Fundamental Unit

**Purpose**: Represents a range of text positions, the atomic unit of all location tracking.

```zig
pub const Span = struct {
    start: usize,
    end: usize,
    
    // Core operations (all <10ns)
    pub fn init(start: usize, end: usize) Span;
    pub fn point(position: usize) Span;
    pub fn empty() Span;
    
    // Range operations
    pub fn len(self: Span) usize;
    pub fn contains(self: Span, pos: usize) bool;
    pub fn overlaps(self: Span, other: Span) bool;
    pub fn merge(self: Span, other: Span) Span;
    pub fn intersect(self: Span, other: Span) Span;
    
    // Text extraction
    pub fn getText(self: Span, input: []const u8) []const u8;
};
```

**Key Properties**:
- Immutable after creation
- Copy semantics (8 bytes)
- Zero allocation
- Hashable and comparable

**Usage Patterns**:
```zig
// Creating spans
const span = Span.init(10, 20);        // Range [10, 20)
const point = Span.point(15);          // Single position
const empty = Span.empty();            // Empty at 0

// Span operations
if (span.contains(15)) { /* position in span */ }
if (span.overlaps(other)) { /* spans overlap */ }
const merged = span.merge(other);      // Union
const common = span.intersect(other);  // Intersection

// Text extraction (zero-copy)
const text = span.getText(source);     // Returns slice
```

### Fact - The Information Atom

**Purpose**: Immutable fact about a span of text, the fundamental unit of the fact stream.

```zig
pub const Fact = struct {
    id: FactId,                // Unique identifier (u32)
    subject: Span,              // What span this describes
    predicate: Predicate,       // Type of information
    object: ?Value,             // Optional associated value
    confidence: f32,            // 0.0 to 1.0
    generation: Generation,     // When created
    
    // Factory methods
    pub fn simple(id: FactId, subject: Span, 
                  predicate: Predicate, gen: Generation) Fact;
    pub fn withValue(id: FactId, subject: Span, 
                     predicate: Predicate, value: Value, 
                     gen: Generation) Fact;
    pub fn speculative(id: FactId, subject: Span, 
                       predicate: Predicate, confidence: f32, 
                       gen: Generation) Fact;
    
    // Query methods
    pub fn overlapsSpan(self: Fact, span: Span) bool;
    pub fn containsPosition(self: Fact, pos: usize) bool;
    pub fn isCertain(self: Fact) bool;        // confidence >= 1.0
    pub fn isSpeculative(self: Fact) bool;    // confidence < 1.0
};
```

**Key Design Decisions**:
- Facts are immutable once created
- Each fact has a globally unique ID
- Confidence enables speculative parsing
- Generation enables incremental updates
- Subject span links fact to source text

**Fact Relationships**:
```zig
// Facts can reference other facts
const parent_fact = Fact.simple(1, span1, .{ .is_node = .function }, 0);
const child_fact = Fact.withValue(2, span2, 
                                  .{ .has_parent = 1 }, 
                                  Value{ .fact_id = 1 }, 0);

// Facts can be speculative (for predictive parsing)
const maybe_fact = Fact.speculative(3, span3, 
                                    .{ .is_token = .identifier }, 
                                    0.7, 0);
```

### Predicate - The Classification System

**Purpose**: Defines what kind of information a fact conveys, organized by parsing layer.

```zig
pub const Predicate = union(enum) {
    // Layer 0: Lexical facts
    is_token: TokenKind,        // Token classification
    has_text: []const u8,       // Literal text content
    bracket_depth: u16,         // Nesting level
    is_trivia,                  // Whitespace/comments
    
    // Layer 1: Structural facts
    is_boundary: BoundaryKind,  // Function/class/block
    is_error_region,            // Error recovery zone
    is_foldable,                // Can be collapsed
    indent_level: u16,          // Indentation depth
    
    // Layer 2: Syntactic facts
    is_node: NodeKind,          // AST node type
    has_child: FactId,          // Parent-child relation
    has_parent: FactId,         // Child-parent relation
    
    // Semantic facts (analysis layers)
    binds_symbol: SymbolId,     // Symbol declaration
    references_symbol: SymbolId, // Symbol usage
    has_type: TypeId,           // Type information
    
    // Get the category for indexing
    pub fn category(self: Predicate) PredicateCategory;
    pub fn isRelational(self: Predicate) bool;
    pub fn eql(self: Predicate, other: Predicate) bool;
};
```

**Predicate Categories** (for efficient indexing):
```zig
pub const PredicateCategory = enum {
    lexical,      // From tokenizer
    structural,   // From boundary detector
    syntactic,    // From detailed parser
    semantic,     // From analysis
    relational,   // Links between facts
    metadata,     // Additional information
};
```

### Token - The Lexical Unit

**Purpose**: Represents a lexical token from Layer 0 parsing.

```zig
pub const Token = struct {
    id: u32,                    // Unique token ID
    span: Span,                 // Position in source
    kind: TokenKind,            // Classification
    text: ?[]const u8,          // Optional text (for literals)
    
    // Cached for performance
    is_delimiter: bool,         // Opening/closing delimiter
    is_keyword: bool,           // Language keyword
    bracket_depth: u16,         // Nesting depth
    
    // Token operations
    pub fn isTrivia(self: Token) bool;
    pub fn precedence(self: Token) u8;
    pub fn associativity(self: Token) Associativity;
};
```

**TokenKind Enum**:
```zig
pub const TokenKind = enum(u8) {
    // Literals
    identifier,
    number,
    string,
    
    // Keywords (language-specific)
    keyword,
    
    // Operators
    operator,
    
    // Delimiters
    left_paren,
    right_paren,
    left_brace,
    right_brace,
    left_bracket,
    right_bracket,
    
    // Trivia
    whitespace,
    comment,
    
    // Special
    eof,
    error_token,
};
```

### Generation - Update Tracking

**Purpose**: Monotonic counter for tracking updates and cache invalidation.

```zig
pub const Generation = u32;

// Usage in incremental updates
const current_gen = system.nextGeneration();
const fact = Fact.simple(id, span, predicate, current_gen);

// Query by generation
const new_facts = index.findByGeneration(current_gen);
```

## Collection Types

### FactIndex - Multi-Index Storage

**Purpose**: Provides O(1) and O(log n) access patterns for fact queries.

```zig
pub const FactIndex = struct {
    // Primary indices
    by_id: HashMap(FactId, Fact),              // O(1) lookup
    by_span: SpanIndex,                        // O(log n) spatial
    by_predicate: HashMap(Category, List),      // O(1) by type
    by_generation: HashMap(Generation, List),   // O(1) by gen
    parent_child: HashMap(FactId, List),        // O(1) hierarchy
    
    // Operations
    pub fn insert(self: *FactIndex, fact: Fact) !void;
    pub fn remove(self: *FactIndex, id: FactId) bool;
    pub fn get(self: *FactIndex, id: FactId) ?Fact;
    
    // Queries
    pub fn findOverlapping(self: *FactIndex, span: Span) ![]FactId;
    pub fn findByCategory(self: *FactIndex, cat: Category) ?[]FactId;
    pub fn findByGeneration(self: *FactIndex, gen: Generation) ?[]FactId;
};
```

**SpanIndex Implementation** (spatial indexing):
```zig
// Interval tree for O(log n) span queries
const SpanIndex = struct {
    root: ?*Node,
    
    const Node = struct {
        span: Span,
        facts: ArrayList(FactId),
        max_end: usize,        // For efficient pruning
        left: ?*Node,
        right: ?*Node,
    };
};
```

### QueryCache - Result Caching

**Purpose**: Cache query results with generation-based invalidation.

```zig
pub const QueryCache = struct {
    entries: HashMap(QueryId, CacheEntry),
    generation: Generation,
    max_entries: usize,
    ttl_seconds: i64,
    
    pub fn get(self: *QueryCache, query: Query) ?[]FactId;
    pub fn put(self: *QueryCache, query: Query, results: []FactId) !void;
    pub fn invalidateSpan(self: *QueryCache, span: Span) void;
    pub fn invalidateGeneration(self: *QueryCache, gen: Generation) void;
};

const CacheEntry = struct {
    results: []FactId,
    generation: Generation,
    timestamp: i64,
    hit_count: u32,
};
```

### FactStream - Streaming Processor

**Purpose**: Process facts as they're generated without buffering all in memory.

```zig
pub const FactStream = struct {
    allocator: Allocator,
    
    pub fn processBatch(self: *FactStream, facts: []const Fact) !void;
    pub fn flush(self: *FactStream) !void;
};
```

### FactDelta - Incremental Changes

**Purpose**: Represent changes between generations for incremental updates.

```zig
pub const FactDelta = struct {
    added: []const Fact,       // New facts
    removed: []const Fact,     // Deleted facts  
    modified: []const Fact,    // Changed facts
    
    pub fn isEmpty(self: FactDelta) bool;
    pub fn apply(self: FactDelta, index: *FactIndex) !void;
};
```

## Parser-Specific Types

### Edit - Text Modification

**Purpose**: Represents a text edit for incremental parsing.

```zig
pub const Edit = struct {
    range: Span,               // Range being replaced
    new_text: []const u8,      // Replacement text
    generation: Generation,    // Edit generation
    
    pub fn init(range: Span, text: []const u8, gen: Generation) Edit;
    pub fn affectsSpan(self: Edit, span: Span) bool;
};
```

### TokenDelta - Token Stream Changes

**Purpose**: Changes in token stream after an edit.

```zig
pub const TokenDelta = struct {
    removed: []u32,            // Removed token IDs
    added: []Token,            // New tokens
    affected_range: Span,      // Total affected range
    generation: Generation,
    
    pub fn affectsStructure(self: TokenDelta) bool;
    pub fn toFacts(self: TokenDelta) []Fact;
};
```

### ParseBoundary - Structural Unit

**Purpose**: Defines a boundary for independent parsing in Layer 2.

```zig
pub const ParseBoundary = struct {
    span: Span,                // Boundary extent
    kind: BoundaryKind,        // Type (function/class/block)
    confidence: f32,           // Detection confidence
    depth: u16,                // Nesting depth
    has_error: bool,           // Contains errors
    
    pub fn contains(self: ParseBoundary, span: Span) bool;
    pub fn overlaps(self: ParseBoundary, span: Span) bool;
};

pub const BoundaryKind = enum {
    function,
    class,
    block,
    module,
    error_recovery_region,
};
```

## Memory Management Types

### FactPool - Fixed-Size Allocation

**Purpose**: Efficient allocation of fixed-size fact objects.

```zig
pub const FactPool = struct {
    chunks: ArrayList(*Chunk),
    free_list: ?*Fact,
    chunk_size: usize,
    
    pub fn alloc(self: *FactPool) !*Fact;
    pub fn free(self: *FactPool, fact: *Fact) void;
};
```

### FactArena - Bulk Allocation

**Purpose**: Arena allocator for temporary fact generation.

```zig
pub const FactArena = struct {
    buffer: []u8,
    used: usize,
    
    pub fn alloc(self: *FactArena, comptime T: type) !*T;
    pub fn reset(self: *FactArena) void;
};
```

## Query Types

### Query - Fact Query Specification

**Purpose**: Specify what facts to retrieve from the index.

```zig
pub const Query = union(enum) {
    overlapping_span: Span,
    by_category: PredicateCategory,
    by_generation: Generation,
    containing_position: usize,
    by_predicate: Predicate,
    complex: ComplexQuery,
};

pub const ComplexQuery = struct {
    span: ?Span = null,
    category: ?PredicateCategory = null,
    generation: ?Generation = null,
    min_confidence: f32 = 0.0,
    include_speculative: bool = true,
};
```

## Type Relationships

### Fact Creation Flow

```
Source Text
    ↓
[Layer 0: Lexer]
    ↓
Tokens (with Spans)
    ↓
[Layer 1: Structural]
    ↓
ParseBoundaries
    ↓
[Layer 2: Detailed]
    ↓
AST Nodes
    ↓
[Fact Generator]
    ↓
Facts (with Predicates)
    ↓
[FactIndex]
    ↓
Indexed Storage
```

### Query Execution Flow

```
Query Request
    ↓
[QueryCache Check]
    ↓ (miss)
[FactIndex Search]
    ↓
[Result Collection]
    ↓
[Cache Storage]
    ↓
Query Results
```

### Incremental Update Flow

```
Text Edit
    ↓
[Edit → TokenDelta]
    ↓
[TokenDelta → StructuralDelta]
    ↓
[StructuralDelta → FactDelta]
    ↓
[FactDelta → Index Update]
    ↓
[Cache Invalidation]
    ↓
Updated Facts
```

## Performance Characteristics

### Size Analysis

| Type | Size (bytes) | Notes |
|------|--------------|-------|
| Span | 16 | Two usize values |
| Fact | 48 | With padding |
| Token | 32 | Optimized layout |
| Predicate | 24 | Union with tag |
| FactId | 4 | u32 identifier |
| Generation | 4 | u32 counter |
| ParseBoundary | 32 | Compact representation |

### Operation Complexity

| Operation | Complexity | Typical Time |
|-----------|------------|--------------|
| Span.contains | O(1) | <5ns |
| Span.overlaps | O(1) | <5ns |
| FactIndex.get | O(1) | <50ns |
| FactIndex.findOverlapping | O(log n + k) | <1μs |
| QueryCache.get | O(1) | <100ns |
| Fact creation | O(1) | <20ns |
| Token creation | O(1) | <30ns |

## Usage Examples

### Creating and Querying Facts

```zig
// Create facts for a function
const fn_span = Span.init(100, 200);
const fn_fact = Fact.simple(1, fn_span, 
                            .{ .is_boundary = .function }, 0);

// Create facts for tokens within
const id_span = Span.init(110, 115);
const id_fact = Fact.withValue(2, id_span, 
                               .{ .is_token = .identifier },
                               Value{ .string = "myFunc" }, 0);

// Index the facts
try index.insert(fn_fact);
try index.insert(id_fact);

// Query facts in the function
const facts_in_fn = try index.findOverlapping(fn_span);
```

### Incremental Update

```zig
// Process an edit
const edit = Edit.init(Span.init(150, 160), "new_code", gen);

// Generate deltas through layers
const token_delta = try lexer.processEdit(edit);
const struct_delta = try structural.processDelta(token_delta);

// Create fact delta
const old_facts = try index.findOverlapping(edit.range);
const new_facts = try generateFacts(new_tokens);

const fact_delta = FactDelta{
    .removed = old_facts,
    .added = new_facts,
    .modified = &.{},
};

// Apply delta
try fact_delta.apply(&index);
```

### Complex Queries

```zig
// Find all high-confidence function boundaries in viewport
const query = Query{ 
    .complex = ComplexQuery{
        .span = viewport,
        .category = .structural,
        .min_confidence = 0.9,
        .include_speculative = false,
    }
};

const results = try system.queryFacts(query, allocator);
defer allocator.free(results);

// Get the actual facts
for (results) |fact_id| {
    const fact = index.get(fact_id) orelse continue;
    if (fact.predicate == .{ .is_boundary = .function }) {
        // Process function boundary
    }
}
```

## Design Rationale

### Why Facts Instead of AST?

1. **Incremental Updates**: Facts can be individually added/removed
2. **Multiple Views**: Same facts support different query patterns
3. **Speculation**: Facts can have confidence levels
4. **Caching**: Query results cache better than tree traversals
5. **Parallelism**: Facts can be generated independently

### Why Multiple Indices?

1. **Access Patterns**: Different queries need different indices
2. **Performance**: O(1) or O(log n) for all common operations
3. **Cache Locality**: Related facts stored together
4. **Memory Trade-off**: 2x memory for 10-100x query speed

### Why Generations?

1. **Cache Invalidation**: Know exactly what changed when
2. **Incremental Updates**: Track fact age
3. **Undo/Redo**: Can maintain fact history
4. **Debugging**: Track when facts were created

## Conclusion

The Stratified Parser's primitive types form a coherent system optimized for incremental parsing, efficient querying, and predictive operations. The fact-based approach, combined with multi-index storage and generation tracking, enables the sophisticated caching and speculation features that make sub-millisecond response times achievable.