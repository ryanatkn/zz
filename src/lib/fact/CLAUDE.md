# Fact Module - Universal Data Unit

## Overview
Facts are the fundamental unit of information in the stream-first architecture. Each fact is exactly 24 bytes and represents a piece of knowledge about a code span.

## Core Types

### Fact Structure (24 bytes)
```zig
pub const Fact = extern struct {
    subject: PackedSpan,  // 8 bytes - what span this describes
    object: Value,        // 8 bytes - associated value
    id: FactId,          // 4 bytes - unique identifier
    predicate: Predicate, // 2 bytes - type of fact
    confidence: f16,      // 2 bytes - confidence level
};
```

### Value (8 bytes)
Extern union for zero-overhead storage:
- `none`: No value
- `number`: i64
- `uint`: u64
- `span`: PackedSpan reference
- `atom`: AtomId for interned strings
- `fact_ref`: Reference to another fact

### Predicate (~80 types)
Categorized fact types:
- **Structural**: is_function, is_class, is_method
- **Relational**: has_parent, follows, precedes
- **Properties**: has_text, has_value, confidence levels
- **Scope**: begins_scope, ends_scope
- **Type**: is_token, is_delimiter, is_operator

## Usage

### Creating Facts
```zig
const fact = try Builder.new()
    .withSubject(span)
    .withPredicate(.is_function)
    .withConfidence(0.95)
    .build();
```

### Fact Store
Append-only storage with generation tracking:
```zig
var store = FactStore.init(allocator);
const id = try store.append(fact);
```

## Performance
- **Creation**: 100M facts/sec (10ns per fact)
- **Size**: Exactly 24 bytes (fits in half cache line)
- **Storage**: Zero allocation in hot paths

## Integration
- Used by cache module for multi-indexing
- Queried by query module with SQL-like DSL
- Produced by language lexers during tokenization