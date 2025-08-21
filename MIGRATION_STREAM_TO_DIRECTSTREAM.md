# Migration Guide: Stream to DirectStream

## Overview
This guide helps migrate code from vtable-based Stream to tagged union DirectStream, achieving 60-80% faster dispatch (1-2 cycles vs 3-5).

## Why Migrate?
- **Performance**: 1-2 cycle dispatch vs 3-5 for vtable
- **Memory**: Stack allocation vs heap
- **Cache**: Linear access vs pointer chasing
- **Principles**: Follows stream-first architecture

## Migration Priority

### High Priority (Performance Critical)
1. **Query Module** - FactStream used heavily
2. **Token Iterator** - Hot path for lexing
3. **Parser Streams** - Performance sensitive

### Medium Priority (Frequently Used)
4. **Cache Module** - Stream iteration
5. **Transform Module** - Pipeline operations
6. **Test Infrastructure** - Benchmark accuracy

### Low Priority (Rarely Used)
7. **Debug Tools** - Not performance critical
8. **CLI Commands** - User won't notice
9. **Documentation Examples** - Update gradually

## Migration Steps

### Step 1: Update Imports
```zig
// Before
const Stream = @import("stream/mod.zig").Stream;
const fromSlice = @import("stream/mod.zig").fromSlice;

// After  
const DirectStream = @import("stream/mod.zig").DirectStream;
const directFromSlice = @import("stream/mod.zig").directFromSlice;
```

### Step 2: Update Type Declarations
```zig
// Before
pub const FactStream = Stream(Fact);
fn processStream(stream: Stream(u32)) !void {

// After
pub const FactStream = DirectStream(Fact);
fn processStream(stream: DirectStream(u32)) !void {
```

### Step 3: Update Stream Creation
```zig
// Before
var stream = fromSlice(u32, &data);
var stream = fromIterator(u32, iter);

// After
var stream = directFromSlice(u32, &data);
// Iterator support needs custom implementation
```

### Step 4: Update Usage (No Changes!)
```zig
// Usage remains identical
while (try stream.next()) |value| {
    process(value);
}

const pos = stream.getPosition();
if (try stream.peek()) |next_val| {
    // ...
}
```

## Common Patterns

### Stream Composition
```zig
// Before (operators not yet migrated)
var mapped = stream.map(u32, double);
var filtered = mapped.filter(isEven);

// After (use direct iteration for now)
var stream = directFromSlice(u32, &data);
while (try stream.next()) |value| {
    const doubled = double(value);
    if (isEven(doubled)) {
        process(doubled);
    }
}
```

### Custom Stream Sources
```zig
// Before - implement vtable
const MySource = struct {
    fn next(ptr: *anyopaque) ?T { ... }
    fn peek(ptr: *const anyopaque) ?T { ... }
    // ... other vtable functions
};

// After - add variant to DirectStream
// OR use generator pattern:
const gen_fn = struct {
    fn generate(state: *anyopaque) ?T {
        // Your logic here
    }
}.generate;

var stream = DirectStream(T){
    .generator = GeneratorStream(T).init(state, gen_fn)
};
```

## Testing Migration

### Verify Performance
```zig
test "Migration improves performance" {
    // Measure old
    var old_stream = fromSlice(u32, &data);
    const old_start = std.time.nanoTimestamp();
    while (try old_stream.next()) |_| {}
    const old_time = std.time.nanoTimestamp() - old_start;
    
    // Measure new
    var new_stream = directFromSlice(u32, &data);
    const new_start = std.time.nanoTimestamp();
    while (try new_stream.next()) |_| {}
    const new_time = std.time.nanoTimestamp() - new_start;
    
    // Should be faster
    try testing.expect(new_time < old_time);
}
```

### Verify Behavior
```zig
test "Migration preserves behavior" {
    const data = [_]u32{ 1, 2, 3, 4, 5 };
    
    // Both should produce same results
    var old = fromSlice(u32, &data);
    var new = directFromSlice(u32, &data);
    
    while (try old.next()) |old_val| {
        const new_val = try new.next();
        try testing.expectEqual(old_val, new_val);
    }
    
    try testing.expect(try new.next() == null);
}
```

## Gotchas

### Operators Not Migrated
Current operators still heap allocate. For now, use direct iteration instead of chained operators.

### No Batch Stream
BatchStream returns `[]T` not `T`, needs special handling. Not yet implemented in DirectStream.

### Iterator Support Limited
fromIterator needs custom generator implementation for DirectStream.

## Module Status

| Module | Stream Usage | Migration Status | Priority |
|--------|-------------|------------------|----------|
| query/executor.zig | FactStream | ✅ directExecute() implemented | High |
| query/test.zig | Query tests | ✅ DirectStream tests added | High |
| token/iterator.zig | TokenStream | ✅ toDirectStream() added | High |
| cache/fact_cache.zig | Stream iteration | ✅ No Stream usage found | High |
| lexer/stream_adapter.zig | Stream(Token) | ✅ toDirectStream() added | Medium |
| lexer/lexer_bridge.zig | Stream adapters | ✅ tokenizeDirectStream() added | Medium |
| stream/test_direct_stream.zig | Tests | ✅ Created comprehensive tests | High |
| languages/json/stream_lexer.zig | Direct iterator | ✅ Already optimal | N/A |
| languages/zon/stream_lexer.zig | Direct iterator | ✅ Already optimal | N/A |

## Phase 5 Progress

### Completed
- ✅ Type aliases created for easy migration
- ✅ Helper functions reduce boilerplate
- ✅ QueryExecutor has directExecute() method
- ✅ TokenIterator has toDirectStream() method
- ✅ Performance benchmark validates 1-2 cycle claim

### In Progress
- 🚧 Migrating high-priority modules
- 🚧 Operator pool integration

### TODO
- [ ] Embed operator state for zero-allocation
- [ ] Complete module migration
- [ ] Delete vtable Stream implementation

## Direct Iterator Pattern (Best)

For maximum performance, bypass Stream entirely:

```zig
// Don't use Stream at all
pub const JsonStreamLexer = struct {
    pub fn next(self: *@This()) ?Token {
        // Direct implementation - 1-2 cycles
        // No Stream overhead at all
    }
};

// Usage
var lexer = JsonStreamLexer.init(source);
while (lexer.next()) |token| {
    // Fastest possible iteration
}
```

This pattern is already used by JSON/ZON lexers and achieves optimal performance.

## Questions?

See:
- `src/lib/stream/DIRECTSTREAM.md` - Technical details
- `TODO_STREAM_FIRST_PHASE_4.md` - Implementation status
- `TODO_STREAM_FIRST_PRINCIPLES.md` - Design principles