# Stream Module - Zero-Allocation Generic Streaming

## Overview
Generic streaming infrastructure providing composable, zero-allocation data flow. Foundation for all stream operations in the architecture.

## Core Types

### Stream(T)
Generic stream with vtable dispatch:
```zig
pub fn Stream(comptime T: type) type {
    return struct {
        context: *anyopaque,
        nextFn: *const fn(*anyopaque) ?T,
        peekFn: ?*const fn(*anyopaque) ?T,
    };
}
```

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
- **Throughput**: 8.9M ops/sec (112ns per next())
- **Memory**: O(1) with ring buffers
- **Allocation**: Zero in core operations

## Usage Examples
```zig
// Create stream from slice
var source = SliceSource(u32).init(&data);
var stream = source.stream();

// Transform with operators
var mapped = MapOperator(u32, u64).init(&stream, doubleValue);
var filtered = FilterOperator(u64).init(&mapped.stream(), isEven);

// Consume results
while (try filtered.stream().next()) |value| {
    process(value);
}
```

## Design Principles
- **Lazy evaluation**: Process on-demand
- **Backpressure**: Consumer controls rate
- **Composable**: Operators chain naturally
- **Generic**: Works with any type

## Integration
- Used by TokenStream for lexer output
- Powers FactStream in query execution
- Enables streaming parser architecture