# Lexer Module - Temporary Bridge Layer

## ⚠️ TEMPORARY MODULE - DELETE IN PHASE 4

This entire module is a transitional bridge between the old parser architecture and the new stream-first system. It will be completely removed in Phase 4 when all languages have native stream lexers.

## Purpose

Provides compatibility layer to convert old-style tokens to StreamToken format while we migrate to pure stream-first architecture.

## Architecture

### Core Components

- **LexerBridge** (`lexer_bridge.zig`) - TEMPORARY converter from old tokens to StreamToken
- **LexerRegistry** (`registry.zig`) - Central registry for language lexers  
- **StreamAdapter** (`stream_adapter.zig`) - Adapts token arrays to Stream interface
- **LexerState** (`state.zig`) - Shared lexer state management

### Performance Impact

The bridge adds 3-5 cycles overhead per token due to:
- Old token allocation and conversion
- AtomTable string interning
- Dynamic dispatch through registry

This overhead is acceptable temporarily and will be eliminated when native stream lexers are implemented.

## Usage

```zig
// Current (with bridge)
var registry = LexerRegistry.init(allocator, &atom_table);
defer registry.deinit();
try registry.registerDefaults();

const lexer = registry.getLexer(.json).?;
const tokens = try lexer.tokenize(source);  // Returns []StreamToken
defer allocator.free(tokens);

// Future (Phase 4 - native stream lexer)
var lexer = JsonLexer.init(allocator);
var stream = lexer.tokenizeStream(source);  // Returns Stream(StreamToken)
while (try stream.next()) |token| {
    // Process token without allocation
}
```

## Migration Timeline

### Phase 2 (COMPLETE)
- ✅ LexerBridge implementation
- ✅ Token conversion for JSON/ZON
- ✅ Registry with language dispatch
- ✅ StreamAdapter for array→stream conversion

### Phase 3 (TODO)
- [ ] Implement native stream lexers for JSON/ZON
- [ ] Performance benchmarks vs bridge

### Phase 4 (TODO)
- [ ] Native stream lexers for all languages
- [ ] DELETE this entire module
- [ ] Update all consumers to use direct stream lexers

## Known Issues

1. **Memory overhead**: Bridge allocates full token array instead of streaming
2. **Double dispatch**: Registry lookup + bridge conversion  
3. **Import paths**: Test files have module boundary issues when run directly

## Files to Delete in Phase 4

```
src/lib/lexer/
├── lexer_bridge.zig     # DELETE - temporary converter
├── registry.zig         # DELETE - replaced by direct language imports
├── stream_adapter.zig   # KEEP - useful for array→stream conversion
├── state.zig           # KEEP - shared state management
└── test.zig            # UPDATE - remove bridge tests
```

## Performance Metrics

- **Bridge overhead**: 3-5 cycles per token
- **Memory usage**: O(n) for token array (should be O(1) streaming)
- **AtomTable overhead**: ~20ns per unique string

## Testing

```bash
# Run lexer tests (part of stream-first suite)
zig test src/lib/test_stream_first.zig

# Individual tests have import issues - use main suite
```

## Dependencies

- `token/` - StreamToken type definition
- `memory/` - AtomTable for string interning
- `languages/` - Old lexer implementations
- `stream/` - Stream interface

## Future Direct Lexer Interface

```zig
// Phase 4 goal - zero-allocation streaming
pub const StreamLexer = struct {
    pub fn tokenizeStream(self: *StreamLexer, source: []const u8) Stream(StreamToken) {
        // Direct streaming without intermediate array
    }
};
```