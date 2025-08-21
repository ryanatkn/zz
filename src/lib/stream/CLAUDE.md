# Stream Module - Zero-Allocation Generic Streaming

## Overview
Generic streaming infrastructure providing composable, zero-allocation data flow. Foundation for all stream operations in the architecture.

## Two Implementations (Phase 4)

### 1. Stream(T) - VTable-Based (Original)
Generic stream with vtable dispatch (3-5 cycles):
```zig
pub fn Stream(comptime T: type) type {
    return struct {
        ptr: *anyopaque,
        vtable: *const VTable,
    };
}
```
**Status**: Kept for backward compatibility during migration

### 2. DirectStream(T) - Tagged Union (New)
Tagged union dispatch achieving 1-2 cycles:
```zig
pub fn DirectStream(comptime T: type) type {
    return union(enum) {
        slice: SliceStream(T),
        ring_buffer: RingBufferStream(T),
        generator: GeneratorStream(T),
        // ... other variants
    };
}
```
**Status**: Phase 4 implementation following stream-first principles

## Performance Comparison

| Metric | Stream (VTable) | DirectStream (Tagged) | Improvement |
|--------|----------------|--------------------|-------------|
| Dispatch | 3-5 cycles | 1-2 cycles | 60-80% faster |
| Memory | Heap allocated | Stack/embedded | Zero alloc |
| Cache | Pointer chase | Linear access | Better locality |

## Migration Guide

### New Code
Use DirectStream for all new implementations:
```zig
const stream = directFromSlice(u32, &data);
while (try stream.next()) |item| {
    process(item);
}
```

### Existing Code
Continue using Stream until ready to migrate:
```zig
const stream = fromSlice(u32, &data);  // Still works
```

### Direct Iterator Pattern (Optimal)
For maximum performance, bypass Stream entirely:
```zig
var lexer = JsonStreamLexer.init(source);
while (lexer.next()) |token| {
    // 1-2 cycle dispatch, no overhead
}
```

## Core Types

### RingBuffer
Fixed-capacity circular buffer:
```zig
pub fn RingBuffer(comptime T: type, comptime capacity: usize) type;
// Stack-allocated, zero heap usage
```

## Stream Sources & Sinks

### Sources
- `SliceSource`: Stream from array
- `GeneratorSource`: Computed values
- `FileSource`: File reading
- `RingBufferSource`: From circular buffer

### Sinks
- `BufferSink`: Collect to buffer
- `NullSink`: Discard output
- `ChannelSink`: Inter-thread communication

## Operators

### Transformation
- `map`: Transform elements
- `filter`: Select elements
- `take`/`drop`: Limit elements
- `fusedMap`: Optimized map chains

### Composition
- `merge`: Combine streams
- `tee`: Split stream
- `chain`: Sequential composition

## Performance
- **Stream throughput**: 8.9M ops/sec (112ns per next())
- **DirectStream dispatch**: 1-2 cycles (vs 3-5 for vtable)
- **Memory**: O(1) with ring buffers
- **Allocation**: Zero in core operations

## Usage Examples

### VTable Stream (Compatibility)
```zig
// Create stream from slice
var stream = fromSlice(u32, &data);

// Transform with operators
var mapped = stream.map(u64, doubleValue);
var filtered = mapped.filter(isEven);

// Consume results
while (try filtered.next()) |value| {
    process(value);
}
```

### DirectStream (Recommended)
```zig
// Create direct stream
var stream = directFromSlice(u32, &data);
defer stream.close(); // IMPORTANT: Always close streams to free resources

// Direct dispatch - 1-2 cycles
while (try stream.next()) |value| {
    process(value);
}
```

#### Memory Management
DirectStream with generators may allocate context memory that needs cleanup:
```zig
// Query streams allocate context
var stream = try queryBuilder.directExecuteStream();
defer stream.close(); // Required to free context

// Simple slice streams don't allocate
var simple = directFromSlice(u32, &data);
// close() is no-op here but good practice to always call it
defer simple.close();
```

## Design Principles
- **Lazy evaluation**: Process on-demand
- **Backpressure**: Consumer controls rate
- **Composable**: Operators chain naturally
- **Generic**: Works with any type
- **Zero-cost**: DirectStream achieves theoretical minimum dispatch

## Integration
- Used by TokenStream for lexer output
- Powers FactStream in query execution
- Enables streaming parser architecture
- Direct iterators bypass for maximum performance

## Technical Debt
- **Stream (vtable)**: Kept for compatibility, should be removed after migration
- **Operator allocation**: Need arena pools for zero-allocation chains
- **Migration incomplete**: Many modules still use vtable Stream

## Files
- `stream.zig` - VTable implementation (compatibility)
- `direct_stream.zig` - Tagged union implementation (recommended)
- `buffer.zig` - Ring buffer implementation
- `operators.zig` - Stream operators
- `source.zig` - Stream sources
- `sink.zig` - Stream sinks
- `fusion.zig` - Operator fusion optimizations