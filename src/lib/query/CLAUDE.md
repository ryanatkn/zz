# Query Module - SQL-like DSL for Fact Queries

## Overview

The Query module provides a powerful SQL-like Domain Specific Language (DSL) for querying fact stores. Built as part of Phase 3 of the stream-first architecture, it enables efficient fact retrieval with optimization and streaming support.

## Architecture

### Core Components

- **QueryBuilder** (`builder.zig`) - Fluent interface for constructing queries
- **Query** (`query.zig`) - AST representation of queries
- **QueryExecutor** (`executor.zig`) - Executes queries against fact stores
- **QueryOptimizer** (`optimizer.zig`) - Optimizes query execution plans
- **QueryPlanner** (`planner.zig`) - Creates execution strategies

### Query Language

The DSL follows SQL conventions:

```zig
// Simple query
QueryBuilder.init(allocator)
    .select(&.{.is_function})
    .from(&fact_store)
    .where(.confidence, .gte, 0.9)
    .orderBy(.span_start, .ascending)
    .limit(100)
    .execute()

// Complex query with multiple conditions
QueryBuilder.init(allocator)
    .selectAll()
    .from(&fact_store)
    .where(.predicate, .eq, .is_function)
    .andWhere(.confidence, .gte, 0.8)
    .andWhere(.span_length, .lte, 100)
    .orderBy(.confidence, .descending)
    .limit(10)
    .execute()
```

## Features

### Implemented (Phase 3 Core)

- **SELECT**: All facts, specific predicates, or fields
- **WHERE**: Simple and composite conditions with AND/OR/NOT
- **ORDER BY**: Single and multi-field sorting
- **LIMIT/OFFSET**: Result pagination
- **Query Optimization**: Predicate pushdown, index selection, cost estimation
- **Query Planning**: Execution plan generation with cost analysis

### TODO (Phase 3 Extensions)

- [ ] **GROUP BY**: Aggregation support
- [ ] **HAVING**: Post-aggregation filtering
- [ ] **Streaming Execution**: Zero-allocation result streaming
- [ ] **Parallel Execution**: Multi-threaded query processing
- [ ] **JOIN**: Fact joining operations
- [ ] **Subqueries**: Nested query support

## Performance

### Current Performance

- Simple queries: ~10μs (without index)
- Complex queries: ~100μs (with multiple conditions)
- Query planning: ~1μs overhead
- Memory: O(n) for result set

### Target Performance

- Simple queries: <1μs with index
- Complex queries: <1ms for 100K facts
- Streaming: O(1) memory usage
- Parallel: Linear speedup with cores

## Query Optimization

The optimizer performs several passes:

1. **Predicate Pushdown**: Move predicate filters to SELECT clause
2. **Constant Folding**: Evaluate constant expressions at compile time
3. **Index Selection**: Choose optimal index for WHERE conditions
4. **Limit Pushdown**: Stop early when possible

## Query Planning

The planner creates execution trees:

```
QueryPlan {
  -> Project [cost: 1010.10, rows: 10]
    -> Limit (10) [cost: 1010.00, rows: 10]
      -> Sort (ORDER BY) [cost: 1010.00, rows: 100]
        -> Filter (WHERE) [cost: 1000.00, rows: 100]
          -> Scan (predicate) [cost: 100.00, rows: 1000]
  Estimated Cost: 1010.10
  Estimated Rows: 10
}
```

## Usage Examples

### Basic Queries

```zig
// Find all functions
var result = try QueryBuilder.init(allocator)
    .select(&.{.is_function})
    .from(&store)
    .execute();

// Find high-confidence facts
var result = try QueryBuilder.init(allocator)
    .selectAll()
    .from(&store)
    .where(.confidence, .gte, 0.9)
    .execute();

// Find facts in a span range
var result = try QueryBuilder.init(allocator)
    .selectAll()
    .from(&store)
    .whereBetween(.span_start, 100, 200)
    .execute();
```

### Advanced Queries

```zig
// Complex conditions
var result = try QueryBuilder.init(allocator)
    .select(&.{.is_function, .is_method})
    .from(&store)
    .where(.confidence, .gte, 0.8)
    .orWhere(.predicate, .eq, .is_class)
    .orderBy(.span_start, .ascending)
    .limit(50)
    .offset(10)
    .execute();

// Using IN operator
const values = [_]Value{
    Value{ .predicate = .is_function },
    Value{ .predicate = .is_class },
};
var result = try QueryBuilder.init(allocator)
    .selectAll()
    .from(&store)
    .whereIn(.predicate, &values)
    .execute();
```

## Integration with Cache Module

The query module integrates with the cache module's QueryIndex for efficient lookups:

```zig
var optimizer = QueryOptimizer.init(allocator);
optimizer.setIndex(&query_index);

// Optimizer will automatically use index when beneficial
const optimized = try optimizer.optimize(&query);
```

## Testing

```bash
# Run query tests
zig test src/lib/query/test.zig

# Run as part of stream-first suite
zig test src/lib/test_stream_first.zig
```

## Known Limitations

1. **GROUP BY not implemented**: Aggregation support pending
2. **Streaming not complete**: Currently returns full result sets
3. **Single-threaded**: Parallel execution not yet implemented
4. **No JOIN support**: Single fact store queries only

## Future Enhancements (Phase 4+)

1. **SIMD optimization**: Vectorized comparison operations
2. **Query compilation**: JIT compile hot queries
3. **Distributed queries**: Multi-machine fact stores
4. **Persistent indices**: Disk-backed query indices
5. **Query caching**: Cache frequent query results

## Dependencies

- `fact/` - Fact storage and types
- `span/` - Span operations
- `stream/` - Streaming infrastructure (for future streaming execution)
- `cache/` - QueryIndex for optimization

## Phase 3 Status

- ✅ Core query engine implemented
- ✅ SQL-like DSL functional
- ✅ Basic optimization working
- ✅ Query planning operational
- ⚠️ GROUP BY/HAVING pending
- ⚠️ Streaming execution incomplete
- ⚠️ Performance targets not yet validated