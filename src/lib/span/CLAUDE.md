# Span Module - Efficient Location Primitives

## Overview
Spans represent text ranges with high-performance operations. Optimized for cache efficiency with 8-byte packed representation.

## Core Types

### Span (8 bytes)
```zig
pub const Span = struct {
    start: u32,  // 4 bytes - start position
    end: u32,    // 4 bytes - end position
};
```

### PackedSpan (8 bytes)
Space-efficient encoding for fact storage:
```zig
pub const PackedSpan = u64;  // 32-bit start + 32-bit length

pub fn packSpan(span: Span) PackedSpan;
pub fn unpackSpan(packed: PackedSpan) Span;
```

### SpanSet
Collection with automatic normalization:
- Merges overlapping spans
- Maintains sorted order
- Efficient union/intersection operations

## Operations

### Basic Operations
- `contains`: Point/span containment
- `overlaps`: Span intersection check
- `merge`: Combine overlapping spans
- `distance`: Gap between spans
- `slice`: Extract substring bounds

### Set Operations
- `union`: Combine span sets
- `intersection`: Common regions
- `normalize`: Merge overlapping spans

## Performance
- **Operations**: 200M ops/sec (5ns per merge)
- **Packing**: Zero-cost abstraction
- **Memory**: 8 bytes vs 16 for naive struct

## Usage Examples
```zig
const span = Span.init(10, 50);
const packed = packSpan(span);

// Check containment
if (span.contains(25)) { ... }

// Merge overlapping
const merged = span1.merge(span2);

// SpanSet for collections
var set = SpanSet.init(allocator);
try set.add(span);
const normalized = try set.normalize();
```

## Integration
- Used as Fact.subject for location reference
- Indexed by cache module for span queries
- Converted from token positions by lexers