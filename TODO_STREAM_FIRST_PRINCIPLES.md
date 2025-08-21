# Stream-First Architecture Principles

## Core Philosophy
Everything is a stream. Data flows through typed, composable pipelines with zero allocation and minimal dispatch overhead.

## Fundamental Design Decisions

### 1. Tagged Union Dispatch (DirectStream)
```zig
pub fn DirectStream(comptime T: type) type {
    return union(enum) {
        // Sources embedded directly (no allocation)
        slice: SliceStream(T),
        ring_buffer: RingBufferStream(T),
        generator: GeneratorStream(T),
        empty: EmptyStream(T),
        
        // Operators use pointers (arena allocated)
        filter: *FilterOperator(T),
        take: *TakeOperator(T),
        drop: *DropOperator(T),
        map: *MapOperator(T),
    };
}
```

**Why**: 1-2 cycle dispatch through compile-time enum switching vs 3-5 cycles for vtable indirection. CPU branch predictor can optimize fixed switch statements.

### 2. Arena Allocation Strategy
```zig
threadlocal var operator_arena: ?*ArenaPool = null;

fn getArena() !*ArenaPool {
    if (operator_arena) |arena| return arena;
    // Lazy initialization per thread
    const arena = try std.heap.page_allocator.create(ArenaPool);
    arena.* = ArenaPool.init(std.heap.page_allocator);
    operator_arena = arena;
    return arena;
}
```

**Why**: Zero heap allocations in hot paths. Arena rotation (4 arenas) prevents fragmentation. Thread-local eliminates contention.

### 3. Universal Fact Representation
```zig
pub const Fact = extern struct {  // Exactly 24 bytes
    id: FactId,           // 8 bytes
    subject: PackedSpan,  // 6 bytes (48-bit)
    predicate: Predicate, // 2 bytes (enum)
    object: Value,        // 8 bytes (union)
};
```

**Why**: Fixed-size facts enable array storage, SIMD operations, and cache-line optimization. Extern struct guarantees memory layout.

### 4. Zero-Copy Streaming Lexer
```zig
pub const StreamingLexer = struct {
    buffer: RingBuffer(u8, 4096),  // Stack allocated
    position: u32,
    state: LexerState,
    
    pub fn next(self: *StreamingLexer) ?Token {
        // Direct dispatch, no allocations
        return switch (self.state) {
            .start => self.scanStart(),
            .in_string => self.scanString(),
            .in_number => self.scanNumber(),
            // ...
        };
    }
};
```

**Why**: Ring buffer on stack avoids allocation. State machine dispatch is predictable for CPU.

### 5. Query Engine Integration
```zig
pub fn directExecuteStream(self: *QueryExecutor, query: *const Query) !DirectFactStream {
    const gen = GeneratorStream(Fact).init(
        self,
        struct {
            fn generate(ctx: *anyopaque) ?Fact {
                const executor = @ptrCast(*QueryExecutor, ctx);
                return executor.nextFact();
            }
        }.generate
    );
    return DirectStream(Fact){ .generator = gen };
}
```

**Why**: Type-erased function pointers allow query execution without heap allocation. Generator pattern enables lazy evaluation.

## Performance Principles

### 1. Measure Everything
- Use `rdtsc` for cycle-accurate measurements
- Profile with `perf` for cache misses
- Benchmark real workloads, not microbenchmarks

### 2. Optimize for Common Case
- Simple iteration should be fastest (slice source)
- Complex operators pay their own cost
- Rare paths can allocate if needed

### 3. Data Layout Matters
- Pack structures to minimize size
- Align for SIMD when beneficial
- Group hot fields together

### 4. Predictable Patterns
- Fixed dispatch through enums
- Avoid virtual calls in hot paths
- Inline aggressively with `inline` keyword

## Architecture Guidelines

### 1. Layered Abstractions
```
Application Layer    (CLI commands)
        ↓
Stream Layer        (DirectStream, operators)
        ↓
Fact Layer          (Facts, predicates, values)
        ↓
Token Layer         (Lexers, tokens)
        ↓
Memory Layer        (Arenas, pools, buffers)
```

### 2. Type Safety Without Cost
- Comptime generics for zero-cost abstractions
- Extern unions for exact memory control
- Tagged unions only when dispatch is needed

### 3. Composition Over Inheritance
- Small, focused operators that compose
- No deep hierarchies or complex inheritance
- Functions and data, not objects

### 4. Fail Fast, Fail Clearly
- Errors at comptime when possible
- Clear error types, not error codes
- Panics for programmer errors, errors for user errors

## Implementation Checklist

### For New Stream Sources
- [ ] Embed directly in DirectStream union
- [ ] Implement next(), peek(), skip()
- [ ] No heap allocation
- [ ] Benchmark dispatch cycles

### For New Operators
- [ ] Arena allocate operator state
- [ ] Store source by value (composition)
- [ ] Implement all required methods
- [ ] Test with multiple sources

### For New Languages
- [ ] Streaming lexer with ring buffer
- [ ] Token type fits in 16 bytes
- [ ] Fact extraction during tokenization
- [ ] DirectTokenStream support

### For Performance
- [ ] Profile before optimizing
- [ ] Measure cycles, not just time
- [ ] Check assembly output for hot paths
- [ ] Validate with real workloads

## Anti-Patterns to Avoid

### 1. Hidden Allocations
```zig
// BAD: Hidden allocation
pub fn filter(pred: Predicate) Stream {
    const op = allocator.create(FilterOp); // Hidden!
}

// GOOD: Explicit arena
pub fn filter(arena: *Arena, pred: Predicate) Stream {
    const op = arena.create(FilterOp);
}
```

### 2. Type Erasure Without Need
```zig
// BAD: Unnecessary dynamic dispatch
const AnyStream = struct {
    ptr: *anyopaque,
    nextFn: *const fn(*anyopaque) ?Item,
};

// GOOD: Comptime generic
pub fn Stream(comptime T: type) type {
    return union(enum) { ... };
}
```

### 3. Premature Abstraction
```zig
// BAD: Over-engineered
const StreamFactory = struct {
    fn createBuilder() StreamBuilder { ... }
};

// GOOD: Simple functions
pub fn fromSlice(data: []const T) DirectStream(T) {
    return .{ .slice = SliceStream(T).init(data) };
}
```

## Future Optimizations

### Near Term
- SIMD fact comparison for queries
- Parallel arena allocation
- Specialized operators for common patterns

### Long Term  
- JIT compilation for complex queries
- GPU acceleration for large datasets
- Distributed streaming across cores

## Success Metrics

### Performance
- ✅ 1-2 cycle dispatch for DirectStream
- ✅ <0.1ms lexical analysis for 1KB files
- ✅ <1ms structural parsing for 10KB files
- ✅ Zero heap allocations in steady state

### Architecture
- ✅ Single implementation (no dual APIs)
- ✅ Composable operators
- ✅ Type-safe without runtime cost
- ✅ Clear ownership and lifetimes

### Usability
- ✅ Simple API for common cases
- ✅ Progressive disclosure of complexity
- ✅ Good error messages
- ✅ Predictable performance