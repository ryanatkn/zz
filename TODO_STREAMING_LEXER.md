# TODO_STREAMING_LEXER.md - High-Performance Stateful Lexer Implementation

## Executive Summary

Implement a **zero-allocation, stateful streaming lexer** that handles all edge cases correctly while maintaining maximum performance. This replaces the current broken stateless approach that loses data when chunks split tokens.

## Current Problem

The JSON streaming tokenizer has a fundamental architectural flaw:
- **Data Loss**: When chunks split mid-token (especially strings), entire chunks are skipped
- **Silent Failures**: Returns empty token array instead of proper error handling
- **Position Corruption**: Position advances even with 0 tokens, causing drift

### Root Cause
```
Chunk 1: {"name": "Alice", "valu|  <- Split here
Chunk 2: e": 42, "active": true}
```
Current JsonLexerAdapter treats each chunk independently, causing:
1. Chunk 1: UnterminatedString error → returns empty array
2. Chunk 2: Starts mid-string → lexer fails to parse correctly
3. Result: Data loss and corrupted tokenization

## Solution: High-Performance Stateful Lexer

### Core Design Principles
- **Zero heap allocations** in hot paths
- **Stack-based buffers** for partial tokens  
- **Branchless code** where possible
- **Single source of truth** for state
- **100% correctness** - no data loss ever

### Architecture

#### 1. Stateful Lexer Infrastructure

```zig
// Stack-allocated state for zero heap pressure
pub const LexerState = struct {
    // Fixed-size buffer on stack (no allocations)
    partial_token_buf: [4096]u8 = undefined,
    partial_token_len: u16 = 0,
    
    // Compact state machine (1 byte)
    context: enum(u8) {
        normal = 0,
        in_string = 1,
        in_escape = 2,
        in_unicode = 3,
        in_number = 4,
        in_comment = 5,
    } = .normal,
    
    // Minimal tracking (4 bytes total)
    quote_char: u8 = 0,        // ' or " or 0
    unicode_count: u8 = 0,      // For \uXXXX sequences
    number_state: u8 = 0,       // Bitfield for number parsing
    flags: u8 = 0,              // General purpose flags
    
    // Total: 4KB + 8 bytes, stack-allocated
};
```

#### 2. StatefulJsonLexer Implementation

```zig
pub const StatefulJsonLexer = struct {
    state: LexerState = .{},
    allocator: std.mem.Allocator,
    
    pub fn tokenizeChunk(self: *Self, chunk: []const u8, chunk_pos: usize) ![]Token {
        var tokens = try std.ArrayList(Token).initCapacity(
            self.allocator,
            chunk.len / 4  // Heuristic: avg 4 bytes per token
        );
        
        var pos: usize = 0;
        
        // Step 1: Resume partial token (zero-copy when possible)
        if (self.state.partial_token_len > 0) {
            pos = try self.completePartialToken(chunk, &tokens, chunk_pos);
        }
        
        // Step 2: Main tokenization loop (hot path)
        while (pos < chunk.len) {
            const remaining = chunk.len - pos;
            
            // Fast path for complete tokens
            if (self.state.context == .normal) {
                if (try self.tryFastToken(chunk[pos..], &tokens, chunk_pos + pos)) |consumed| {
                    pos += consumed;
                    continue;
                }
            }
            
            // Check if we're at chunk boundary with incomplete token
            if (remaining < 16 and !self.canCompleteToken(chunk[pos..])) {
                self.savePartialToken(chunk[pos..]);
                break;
            }
            
            // Normal token processing
            const consumed = try self.processToken(chunk[pos..], &tokens, chunk_pos + pos);
            pos += consumed;
        }
        
        return tokens.toOwnedSlice();
    }
};
```

#### 3. Edge Case Handling

**String Splits:**
- Mid-string: Save partial, resume with quote context
- Mid-escape: Track escape state, complete sequence
- Mid-unicode: Count \uXXXX chars, complete hex sequence

**Number Splits:**
- After minus: Save "-", continue number
- At decimal: Save partial, continue fraction
- In exponent: Track e/E, complete notation

**Comment Splits (JSON5):**
- Line comment: Continue until newline
- Block comment: Track /* */, handle nesting

### Unified Node Architecture

Replace dual ParseNode/AST.Node with single efficient type:

```zig
// Single, optimized node type (48 bytes, cache-line friendly)
pub const Node = struct {
    rule_id: u16,               // 2 bytes
    node_flags: u16,            // 2 bytes (replaces node_type enum)
    start_pos: u32,             // 4 bytes (supports 4GB files)
    end_pos: u32,               // 4 bytes  
    text: []const u8,           // 16 bytes (fat pointer)
    children: []Node,           // 16 bytes (fat pointer)
    _padding: [4]u8 = undefined, // 4 bytes (align to 48)
};
```

Benefits:
- Single type throughout system
- Cache-line aligned (48 bytes fits in L1)
- No conversion overhead
- Optional metadata in separate cold storage

### Implementation Plan

#### Phase 1: Core Infrastructure (Day 1)
- [x] Create `/src/lib/transform/streaming/stateful_lexer.zig`
- [ ] Implement LexerState with stack buffers
- [ ] Add state transition functions
- [ ] Create StatefulLexer interface

#### Phase 2: JSON Implementation (Day 1-2)
- [ ] Implement StatefulJsonLexer
- [ ] Handle string tokenization with all escapes
- [ ] Handle number tokenization (int, float, scientific)
- [ ] Add JSON5 support (comments, trailing commas)
- [ ] Create comprehensive test suite

#### Phase 3: Parser Unification (Day 2)
- [ ] Update Node structure in `/src/lib/ast/node.zig`
- [ ] Remove ParseNode from `/src/lib/parser/detailed/parser.zig`
- [ ] Fix boundary_parser.zig to use direct language dispatch
- [ ] Update all affected tests

#### Phase 4: Testing & Optimization (Day 3)
- [ ] Add exhaustive chunk boundary tests
- [ ] Fix memory leaks in BoundaryCache
- [ ] Performance benchmarking
- [ ] Fuzzing tests for edge cases

### Test Strategy

```zig
test "exhaustive chunk boundary testing" {
    const inputs = [_][]const u8{
        \\{"name": "value", "number": 42}
        ,
        \\["string", true, false, null, 3.14e-10]
        ,
        \\{"escape": "line\nbreak", "unicode": "\u0041"}
        ,
        \\{"deep": {"nested": {"object": "value"}}}
    };
    
    for (inputs) |input| {
        // Test splitting at every possible position
        for (1..input.len) |chunk_size| {
            var lexer = StatefulJsonLexer.init(allocator);
            var all_tokens = std.ArrayList(Token).init(allocator);
            
            var pos: usize = 0;
            while (pos < input.len) {
                const end = @min(pos + chunk_size, input.len);
                const tokens = try lexer.tokenizeChunk(input[pos..end], pos);
                try all_tokens.appendSlice(tokens);
                pos = end;
            }
            
            // Verify tokens match non-chunked result
            const expected = try getExpectedTokens(input);
            try assertTokensEqual(expected, all_tokens.items);
        }
    }
}
```

### Performance Targets

- **Tokenization Speed**: <50ns per token
- **Chunk Overhead**: <5% vs non-chunked
- **Memory Usage**: Zero allocations in hot path
- **State Size**: <4KB stack allocation
- **Cache Efficiency**: >95% L1 cache hits

### Success Criteria

- ✅ **100% Correctness**: No data loss on any chunk boundary
- ✅ **All Tests Pass**: 840/840 tests passing
- ✅ **Performance**: <5% overhead for streaming
- ✅ **Memory Safe**: Zero leaks, bounded memory usage
- ✅ **Production Ready**: Handles all JSON RFC 8259 edge cases

### Files to Modify

1. **New Files:**
   - `/src/lib/transform/streaming/stateful_lexer.zig` - Core infrastructure
   - `/src/lib/languages/json/stateful_lexer.zig` - JSON implementation
   - `/src/lib/test/streaming_boundary_test.zig` - Comprehensive tests

2. **Modified Files:**
   - `/src/lib/transform/streaming/token_iterator.zig` - Use stateful lexer
   - `/src/lib/ast/node.zig` - Unified node structure
   - `/src/lib/parser/detailed/parser.zig` - Remove ParseNode
   - `/src/lib/parser/detailed/boundary_parser.zig` - Direct dispatch
   - `/src/lib/parser/detailed/cache.zig` - Fix memory leaks

### Risks & Mitigations

**Risk**: State machine complexity
**Mitigation**: Comprehensive tests, clear state diagram

**Risk**: Performance regression
**Mitigation**: Benchmarks, profiling, hot path optimization

**Risk**: Breaking existing code
**Mitigation**: Careful migration, compatibility layer if needed

### Long-term Benefits

1. **Correctness**: Industrial-strength streaming parser
2. **Performance**: Zero-allocation design scales to GB files
3. **Reusability**: Pattern works for all languages
4. **Maintainability**: Single node type, clear architecture
5. **Future-proof**: Ready for LSP, incremental parsing

---

**Status**: READY FOR IMPLEMENTATION
**Priority**: CRITICAL - Data loss bug must be fixed
**Estimated**: 3 days for complete implementation