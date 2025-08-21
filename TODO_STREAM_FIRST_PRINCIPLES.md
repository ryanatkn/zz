# TODO_STREAM_FIRST_PRINCIPLES.md - Technical Design Principles

## Core Performance Principles

### Zero-Copy Architecture
- **Spans reference source text** - Never duplicate strings, always use slices
- **PackedSpan encoding** - 8 bytes (u32 start + u32 length) vs 16 bytes
- **View types over data** - StreamView, FactView for zero-copy iteration
- **Borrowed vs Owned** - Clear lifetime markers, minimize ownership transfers

### No Hot Path Allocations
- **Ring buffers** - Fixed capacity, reuse memory
- **Arena allocators** - Bulk allocate, bulk free
- **Object pools** - Pre-allocate common types (Tokens, Facts)
- **Stack buffers** - Small arrays on stack (e.g., `[256]u8` for paths)

### Cache-Friendly Layouts
- **Fact = 24 bytes** - Fits in half cache line (32 bytes with padding)
- **Struct-of-arrays** - Group similar fields for vectorization
- **Dense packing** - Minimize padding, use `packed struct` where safe
- **Linear access** - Sequential memory access patterns

## Type System Principles

### Tagged Unions (Zero-Cost)
```zig
// Good: Enum dispatch, stack allocated
const Value = union(enum) {
    none: void,
    number: i64,
    span: PackedSpan,
    atom: AtomId,
};

// Bad: Interface pointers, heap allocated
const Value = struct {
    vtable: *const ValueVTable,
    data: *anyopaque,
};
```

### Comptime Generics
```zig
// Stream(T) specialized at compile time
pub fn Stream(comptime T: type) type {
    return struct {
        // No vtable overhead, monomorphized
        nextFn: *const fn (self: *Self) ?T,
    };
}

// RingBuffer with comptime capacity
pub fn RingBuffer(comptime T: type, comptime capacity: usize) type {
    return struct {
        items: [capacity]T,  // Stack allocated
    };
}
```

### Enum-Based Dispatch
```zig
// Fast: Switch on enum (jump table)
switch (token) {
    .identifier => processIdent(),
    .number => processNum(),
    // Compiler optimizes to jump table
}

// Slow: String comparison
if (std.mem.eql(u8, token_type, "identifier")) {
    // O(n) string comparison
}
```

## Architecture Principles

### Stream Composition
- **Lazy evaluation** - Process on-demand, not eagerly
- **Pipeline fusion** - Combine adjacent operations
- **Backpressure handling** - Consumer controls flow rate
- **Tee/Merge patterns** - Split and join streams efficiently

### Fact Immutability
```zig
const Fact = struct {
    id: FactId,           // 4 bytes
    subject: PackedSpan,  // 8 bytes  
    predicate: Predicate, // 2 bytes (enum)
    object: Value,        // 8 bytes (union)
    confidence: f16,      // 2 bytes
    // Total: 24 bytes, immutable after creation
};
```

### Bounded Memory
- **Ring buffers** - `RingBuffer(Fact, 4096)` = fixed 96KB
- **Arena rotation** - 4 arenas, rotate on generation
- **Capacity limits** - Explicit bounds on all collections
- **Overflow strategies** - Drop oldest, compress, or spill

## Language Extensibility

### Pure Function Adapters
```zig
const LanguageAdapter = struct {
    // Pure functions, no state
    tokenizeFn: *const fn ([]const u8) TokenStream,
    extractFactsFn: *const fn (TokenStream) FactStream,
    
    // Capabilities as data
    capabilities: packed struct {
        has_symbols: bool,
        has_types: bool,
        supports_streaming: bool,
    },
};
```

### Fact-Based IR
- **Language agnostic** - Core knows only facts
- **No AST types** - Facts describe structure
- **Uniform queries** - Same query language for all languages
- **Progressive enhancement** - Languages add facts incrementally

## Generic Programming

### Zero-Cost Abstractions
```zig
// Inline for zero overhead
inline fn map(comptime T: type, comptime U: type, 
              stream: Stream(T), f: fn(T) U) Stream(U) {
    // Comptime specialization, no runtime cost
}

// Comptime interface checking
fn assertStreamLike(comptime T: type) void {
    comptime {
        _ = T.next;
        _ = T.peek;
        // Compile error if missing methods
    }
}
```

## Memory Patterns

### Arena Pool Strategy
```zig
const ArenaPool = struct {
    arenas: [4]Arena,
    current: u2,  // 2 bits for 4 arenas
    
    // Rotate on generation boundary
    pub fn rotate(self: *ArenaPool) void {
        self.current +%= 1;
        self.arenas[self.current].reset();
    }
};
```

### String Interning
```zig
const AtomTable = struct {
    // Single allocation for all strings
    buffer: []u8,
    entries: std.HashMap(u32, Atom),
    
    // Return stable ID, not pointer
    pub fn intern(self: *AtomTable, str: []const u8) AtomId {
        // Hash-consing for deduplication
    }
};
```

### Packed Representations
```zig
// 8 bytes instead of 16
const PackedSpan = packed struct {
    start: u32,
    length: u32,
};

// 16 bytes instead of 24+ 
const PackedFact = packed struct {
    subject_start: u24,
    subject_len: u16,
    predicate: u8,
    object: u32,
};
```

## Performance Targets

### Throughput
- **Tokenization**: >10MB/sec source text
- **Fact extraction**: >1M facts/sec
- **Stream operations**: >10M items/sec
- **Query execution**: >100K queries/sec

### Latency
- **First token**: <100μs from input
- **Fact query**: <1μs for indexed lookup
- **Stream next()**: <10ns amortized
- **Cache hit**: <5ns for hot data

### Memory
- **Per-fact overhead**: 0 bytes (packed in arrays)
- **Stream buffer**: <4KB per stream
- **Index overhead**: <10% of fact size
- **Arena waste**: <5% due to rotation

## Anti-Patterns to Avoid

### Hidden Allocations
```zig
// Bad: Hidden allocation
fn processToken(token: Token) []const u8 {
    return std.fmt.allocPrint(...);  // Allocates!
}

// Good: Explicit allocation
fn processToken(token: Token, buf: []u8) []const u8 {
    return std.fmt.bufPrint(buf, ...);  // Uses provided buffer
}
```

### String Comparisons
```zig
// Bad: O(n) string comparison
if (std.mem.eql(u8, predicate_name, "is_function")) {

// Good: O(1) enum comparison  
if (predicate == .is_function) {
```

### Pointer Chasing
```zig
// Bad: Linked list traversal
var node = list.head;
while (node) |n| {
    process(n.data);  // Cache miss likely
    node = n.next;
}

// Good: Array iteration
for (array) |item| {
    process(item);  // Sequential, cache-friendly
}
```

### Unbounded Recursion
```zig
// Bad: Stack overflow risk
fn parseExpr(tokens: []Token) Expr {
    return Expr{
        .left = parseExpr(tokens[0..mid]),  // Recursive
        .right = parseExpr(tokens[mid..]),
    };
}

// Good: Iterative with explicit stack
fn parseExpr(tokens: []Token) Expr {
    var stack = Stack(ParseFrame).init();
    // Iterative processing with bounded stack
}
```

## Validation Checklist

### Every Module Must:
- [ ] Have zero allocations in hot paths
- [ ] Use tagged unions over interfaces
- [ ] Provide comptime generic versions
- [ ] Support streaming/incremental operation
- [ ] Have bounded memory usage
- [ ] Include benchmarks proving targets

### Every Type Must:
- [ ] Be packed or have documented padding reason
- [ ] Have size assertion: `comptime assert(@sizeOf(T) == expected)`
- [ ] Use smallest sufficient integer types
- [ ] Prefer enums over strings
- [ ] Document ownership/lifetime

### Every Function Must:
- [ ] Be inline if <10 lines and hot path
- [ ] Return errors explicitly, not panic
- [ ] Accept allocator if allocating
- [ ] Have comptime-known bounds
- [ ] Avoid hidden copies

## Conclusion

These principles ensure the Stream-First architecture achieves:
- **Maximum performance** through zero-copy, no allocations
- **Full extensibility** through fact-based IR
- **Type safety** through Zig's comptime features
- **Predictable behavior** through bounded resources

Every design decision should be validated against these principles.