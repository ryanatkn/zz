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

## Implementation Status

### ✅ Completed: Stream Module (Day 1-2)

**Files Created:**
- `src/lib/stream/mod.zig` - Core Stream(T) type with vtable dispatch
- `src/lib/stream/buffer.zig` - RingBuffer implementation (zero-allocation)
- `src/lib/stream/source.zig` - MemorySource, FileSource, GeneratorSource
- `src/lib/stream/sink.zig` - BufferSink, FileSink, NullSink, ChannelSink
- `src/lib/stream/operators.zig` - map, filter, batch, take, drop, merge
- `src/lib/stream/error.zig` - StreamError enum
- `src/lib/stream/test.zig` - Comprehensive test suite

**Key Achievements:**
- Zero-allocation ring buffer with fixed capacity
- Generic Stream(T) with vtable for type erasure
- Composable operators (map, filter, etc.)
- Multiple source/sink implementations
- Comprehensive test coverage

### ✅ Completed: Span Module (Day 3)

**Files Created:**
- `src/lib/span/mod.zig` - Core Span type (u32 start/end)
- `src/lib/span/packed.zig` - PackedSpan (u64) for space efficiency
- `src/lib/span/set.zig` - SpanSet with automatic normalization
- `src/lib/span/ops.zig` - Rich set of span operations
- `src/lib/span/test.zig` - Comprehensive test suite

**Key Achievements:**
- Span struct exactly 8 bytes as designed
- PackedSpan saves 8 bytes per fact (stores length instead of end)
- SpanSet automatically merges overlapping spans
- Rich operations: merge, intersect, distance, shift, split, etc.
- Full test coverage with size assertions

### ✅ Completed: Fact Module (Day 3-4)

**Files Created:**
- `src/lib/fact/mod.zig` - Module exports and size assertions
- `src/lib/fact/fact.zig` - 24-byte Fact struct definition
- `src/lib/fact/predicate.zig` - Predicate enum (2 bytes, ~80 variants)
- `src/lib/fact/value.zig` - Value union (8 bytes, 8 variants)
- `src/lib/fact/store.zig` - Append-only FactStore with generations
- `src/lib/fact/builder.zig` - Fluent Builder DSL and pattern helpers
- `src/lib/fact/test.zig` - Comprehensive test suite

**Key Achievements:**
- **Fact struct exactly 24 bytes** (4 + 8 + 2 + 2 + 8)
- Predicate enum covers lexical, structural, semantic, diagnostic facts
- Value union supports numbers, spans, atoms, fact refs, floats, bools
- FactStore provides append-only storage with generation tracking
- Builder DSL enables fluent fact construction
- Pattern helpers for common fact types

**Final Status:**
- ✅ **All 72 tests passing** - Stream, Span, and Fact modules fully functional
- ✅ **Exact size targets achieved** - Fact is exactly 24 bytes, Value is 8 bytes
- ✅ **Extern union/struct design** - Zero overhead, perfect memory control
- ⚠️ Some stream operators still allocate (TODOs for Phase 2 arena allocators)
- 📝 Performance benchmarks pending for Week 2 validation

## Implementation Tasks

### Week 1: Core Primitives

#### Day 1-2: Stream Module ✅ COMPLETE
- [x] Create directory structure
- [x] Implement Stream(T) generic type with vtable pattern
- [x] Implement RingBuffer with zero allocations
- [x] Add MemorySource and BufferSink
- [x] Write comprehensive tests

#### Day 3-4: Span & Fact Modules ✅ COMPLETE
- [x] **Span Module** (implemented first as Fact dependency)
  - [x] Core Span struct (u32 start/end, 8 bytes)
  - [x] PackedSpan optimization (u64: 32-bit start + 32-bit length)
  - [x] SpanSet with normalization (merge overlapping spans)
  - [x] Comprehensive span operations (merge, intersect, distance, etc.)
  - [x] Full test coverage
- [x] **Fact Module**
  - [x] 24-byte Fact struct achieved exactly
  - [x] Predicate enum (2 bytes, ~80 predicates defined)
  - [x] Value union (8 bytes with 8 variants)
  - [x] Append-only FactStore with generation tracking
  - [x] Fluent Builder DSL with pattern helpers
  - [x] Comprehensive tests written
- [x] **Run tests to verify implementation** ✅ All 72 tests pass!

**Implementation Notes:**
- Had to remove `inline` keywords (Zig 0.14.1 syntax issue with inline fn params)
- Avoided circular imports by duplicating minimal Span definition in packed.zig
- Created separate fact.zig alongside mod.zig for cleaner organization
- Achieved exact 24-byte Fact struct through careful field ordering
- FactStore includes iterator, compaction, and stats tracking
- Builder provides fluent API with shortcuts for common patterns

**Lessons Learned:**
- `packed` is a reserved keyword in Zig (for `packed struct`), cannot be used as identifier
- **Extern union vs tagged union**: Tagged unions add 8+ bytes for the tag, making Value 16 bytes instead of 8. We use `extern union` for exact size control, with the Predicate field providing type discrimination
- **Extern struct for Fact**: Ensures exactly 24 bytes with no padding, fields ordered by size (8,8,4,2,2)
- **Type safety strategy**: Predicate enum implies Value type, helper functions enforce contracts, future: comptime validation
- f16 (2 bytes) perfect for confidence values vs f32 (4 bytes)
- Zig's comptime assertions validate our size targets

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