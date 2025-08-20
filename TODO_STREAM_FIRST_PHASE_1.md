# TODO_STREAM_FIRST_PHASE_1.md - Core Infrastructure Implementation

## Phase 1 Overview
Implement the three core primitives (Stream, Fact, Span) and establish the foundation for the stream-first architecture. Focus on zero-allocation patterns and comprehensive testing.

## Timeline: Weeks 1-2

## Module Changes

### New Modules to Create

#### 1. `src/lib/stream/` - Generic Streaming Infrastructure
**New Files**:
- `mod.zig` - Exports and core Stream(T) type
- `source.zig` - MemorySource, FileSource implementations
- `sink.zig` - BufferSink, NullSink implementations  
- `operators.zig` - map, filter, batch core operators
- `buffer.zig` - RingBuffer(T, capacity) implementation
- `error.zig` - StreamError types
- `test.zig` - Stream primitive tests

**Key Exports in mod.zig**:
```zig
pub const Stream = @import("stream.zig").Stream;
pub const RingBuffer = @import("buffer.zig").RingBuffer;
pub const StreamSource = @import("source.zig").StreamSource;
pub const StreamSink = @import("sink.zig").StreamSink;
pub const operators = @import("operators.zig");
```

#### 2. `src/lib/fact/` - Fact Primitive System
**New Files**:
- `mod.zig` - Exports and Fact type definition
- `store.zig` - Append-only FactStore
- `predicate.zig` - Predicate enum definitions
- `value.zig` - Value union type
- `builder.zig` - Fluent fact construction API
- `test.zig` - Fact primitive tests

**Key Exports in mod.zig**:
```zig
pub const Fact = struct { ... };  // 24-byte struct
pub const FactId = u32;
pub const FactStore = @import("store.zig").FactStore;
pub const Predicate = @import("predicate.zig").Predicate;
pub const Value = @import("value.zig").Value;
pub const Builder = @import("builder.zig").Builder;
```

#### 3. `src/lib/span/` - Span Primitive System
**New Files**:
- `mod.zig` - Exports and core Span type
- `packed.zig` - PackedSpan (u64) implementation
- `set.zig` - SpanSet for collections
- `ops.zig` - Span operations (merge, intersect, etc.)
- `test.zig` - Span primitive tests

**Key Exports in mod.zig**:
```zig
pub const Span = struct { start: u32, end: u32 };
pub const PackedSpan = @import("packed.zig").PackedSpan;
pub const SpanSet = @import("set.zig").SpanSet;
pub const packSpan = @import("packed.zig").packSpan;
pub const unpackSpan = @import("packed.zig").unpackSpan;
```

### Existing Modules to Modify

#### 1. `src/lib/` - Add New Module Exports
**File**: `src/lib/mod.zig`
- Add exports for stream, fact, span modules
- Maintain backward compatibility with existing exports

#### 2. `src/lib/memory/` - Arena Pool Implementation
**New Files**:
- `arena_pool.zig` - ArenaPool for rotating arenas
- `atom_table.zig` - Global string interning

**Modified Files**:
- `mod.zig` - Export new arena pool and atom table

### Migration Preparations (Non-Breaking)

#### 1. `src/lib/parser/foundation/types/`
- Keep existing span.zig, fact.zig, predicate.zig
- Add deprecation comments pointing to new modules
- These will be removed in Phase 2

#### 2. `src/lib/transform/streaming/`
- Keep existing for now
- Will be replaced by stream module in Phase 2

## Implementation Tasks

### Week 1: Core Primitives

#### Day 1-2: Stream Module
- [ ] Create directory structure
- [ ] Implement Stream(T) generic type with vtable pattern
- [ ] Implement RingBuffer with zero allocations
- [ ] Add MemorySource and BufferSink
- [ ] Write comprehensive tests

#### Day 3-4: Fact Module  
- [ ] Define 24-byte Fact struct
- [ ] Implement Predicate enum (lexical, structural, semantic)
- [ ] Implement Value union (8 bytes)
- [ ] Create append-only FactStore
- [ ] Write fact builder DSL
- [ ] Write comprehensive tests

#### Day 5: Span Module
- [ ] Implement core Span operations
- [ ] Create PackedSpan optimization (u64)
- [ ] Implement SpanSet with normalization
- [ ] Write comprehensive tests

### Week 2: Integration & Optimization

#### Day 1-2: Memory Management
- [ ] Implement ArenaPool with rotation
- [ ] Create AtomTable for string interning
- [ ] Add memory benchmarks
- [ ] Verify zero-allocation goals

#### Day 3-4: Stream Operators
- [ ] Implement map operator
- [ ] Implement filter operator
- [ ] Implement batch operator
- [ ] Add operator fusion optimization
- [ ] Write operator composition tests

#### Day 5: Performance Validation
- [ ] Create benchmark suite
- [ ] Verify performance targets:
  - Stream throughput: >1M items/sec
  - Fact creation: >100K facts/sec
  - Zero allocations in hot paths
- [ ] Document performance characteristics

## Testing Strategy

### Unit Tests
Each module includes comprehensive test.zig:
- Correctness tests
- Edge cases
- Performance characteristics
- Memory usage validation

### Integration Tests
Create `src/lib/test/stream_first/`:
- Stream → Fact pipeline tests
- Memory management tests
- Cross-module integration

### Benchmark Suite
Create `src/benchmark/stream_first/`:
- Stream throughput benchmarks
- Fact insertion benchmarks
- Memory allocation tracking
- Comparison with current architecture

## Success Criteria

### Functional
- [ ] All three core modules implemented
- [ ] All tests passing
- [ ] Zero memory leaks
- [ ] Documentation complete

### Performance
- [ ] Stream: >1M tokens/second throughput
- [ ] Fact: >100K facts/second insertion
- [ ] Memory: Zero allocations in hot paths
- [ ] Size: Fact = 24 bytes, PackedSpan = 8 bytes

### Quality
- [ ] 100% test coverage for core paths
- [ ] No breaking changes to existing code
- [ ] Clear migration path documented

## Dependencies

### Build System
- No changes required to build.zig
- Add test targets for new modules

### External
- None - pure Zig implementation

## Risks & Mitigations

### Risk 1: Performance Targets Not Met
- **Mitigation**: Profile early, optimize data structures
- **Fallback**: Adjust targets based on real-world usage

### Risk 2: Integration Complexity
- **Mitigation**: Keep existing code working, gradual migration
- **Fallback**: Extend Phase 1 timeline if needed

## Phase 1 Deliverables

1. **Core Modules**: stream/, fact/, span/ fully implemented
2. **Tests**: Comprehensive test coverage
3. **Benchmarks**: Performance validation suite
4. **Documentation**: API docs and migration guide
5. **Examples**: Sample usage of new primitives

## Next Phase Preview

Phase 2 will:
- Migrate existing token types to StreamToken
- Convert lexers to produce TokenStream
- Replace BoundaryCache with FactCache
- Begin language adapter implementation

## Notes

- Focus on simplicity and performance
- Avoid premature optimization except for known hot paths
- Keep backward compatibility throughout Phase 1
- Document all design decisions in code comments