# TODO_STREAMING_LEXER.md - Fix JSON Streaming Tokenizer Architecture

## Problem Statement

The JSON streaming tokenizer has a fundamental architectural flaw where chunks can be split mid-token (especially strings), causing data loss and incorrect tokenization.

### Current Broken Behavior

1. **Data Loss**: When chunk ends inside a string literal, entire chunk is skipped
2. **Silent Failures**: Returns empty token array, losing valid tokens before the error
3. **Position Advances**: Even with 0 tokens, position moves forward, skipping content

### Root Cause Analysis

```
Chunk 1: {"name": "Alice", "valu|  <- Split here
Chunk 2: e": 42, "active": true}
```

- JsonLexer sees unterminated string in Chunk 1: `"valu`
- Returns `error.UnterminatedString`
- Current fix returns empty array, skips entire chunk
- Chunk 2 starts mid-string, lexer doesn't know it's inside a string
- Result: Corrupted tokenization or cascading errors

## Implementation Options

### Option A: Stateful Lexer (Correct Solution)

**Core Idea**: Lexer maintains state between chunks, handles partial tokens properly.

#### Required State Structure

```zig
pub const JsonLexerState = struct {
    // Parsing context
    in_string: bool = false,
    in_escape: bool = false,
    in_number: bool = false,
    in_comment: bool = false,  // JSON5
    
    // Partial token accumulator
    partial_token: std.ArrayList(u8),
    partial_token_kind: ?TokenKind = null,
    partial_start_pos: usize = 0,
    
    // Position tracking (global)
    global_position: usize = 0,
    line: u32 = 1,
    column: u32 = 1,
};
```

#### Implementation Steps

1. **Modify JsonLexerAdapter**:
   - Add persistent `JsonLexerState` field
   - Pass state to lexer for each chunk

2. **Create StatefulJsonLexer**:
   - Initialize from saved state
   - Complete partial tokens first
   - Save incomplete tokens at chunk end
   - Update state for next chunk

3. **Handle Chunk Boundaries**:
   ```zig
   pub fn tokenizeChunk(self: *Self, chunk: []const u8, start_pos: usize) ![]Token {
       var tokens = std.ArrayList(Token).init(self.allocator);
       
       // 1. Complete partial token from previous chunk
       if (self.state.partial_token_kind) |kind| {
           const completed = try self.completePartialToken(chunk);
           try tokens.append(completed);
       }
       
       // 2. Tokenize chunk normally
       while (position < chunk.len) {
           if (atChunkEnd() and insideToken()) {
               self.savePartialToken();
               break;
           }
           const token = try self.nextToken();
           try tokens.append(token);
       }
       
       return tokens.toOwnedSlice();
   }
   ```

### Option B+: Smart Quote-Aware Chunking (Simpler Alternative)

**Core Idea**: Adjust chunk boundaries to avoid breaking inside strings.

#### Implementation in loadNextChunk()

```zig
fn findSafeChunkBoundary(input: []const u8, start: usize, ideal_end: usize) usize {
    var quote_count: usize = 0;
    var in_escape = false;
    
    // Count quotes from start to ideal_end
    var pos = start;
    while (pos < ideal_end) : (pos += 1) {
        if (in_escape) {
            in_escape = false;
            continue;
        }
        if (input[pos] == '\\') {
            in_escape = true;
        } else if (input[pos] == '"') {
            quote_count += 1;
        }
    }
    
    // Even quotes = safe to break
    if (quote_count % 2 == 0) return ideal_end;
    
    // Odd quotes = we're inside a string, scan for closing quote
    while (pos < input.len) : (pos += 1) {
        if (in_escape) {
            in_escape = false;
            continue;
        }
        if (input[pos] == '\\') {
            in_escape = true;
        } else if (input[pos] == '"') {
            return pos + 1; // Include closing quote
        }
    }
    
    return ideal_end; // Couldn't find safe boundary
}
```

## Critical Architecture Questions

### 1. Memory Management
- **Q**: Who owns partial_token buffer? Adapter or Lexer?
- **Q**: Max size limit for partial tokens? (Prevent DoS with huge strings)
- **Q**: How to handle cleanup on stream abort?

### 2. Error Recovery
- **Q**: Reset strategy for non-recoverable errors?
- **Q**: Should we track error state to prevent cascades?
- **Q**: Fallback behavior when state is corrupted?

### 3. Performance Impact
- **Q**: Is stateful overhead worth it vs. smart chunking?
- **Q**: Should we have fast path for complete tokens?
- **Q**: Buffer size tuning for typical JSON structures?

### 4. API Compatibility
- **Q**: Keep existing JsonLexer for non-streaming?
- **Q**: Or make all lexing stateful with wrapper?
- **Q**: How to version/migrate existing code?

### 5. Implementation Priority
- **Q**: Try Option B+ first as 80% solution?
- **Q**: Full Option A only if B+ proves insufficient?
- **Q**: Hybrid approach possible?

## Testing Strategy

### Chunk Boundary Test Cases

1. **String Splits**:
   - Before opening quote
   - After opening quote
   - Mid-string
   - Inside escape sequence
   - Before closing quote
   - After closing quote

2. **Number Splits**:
   - After minus sign
   - Between digits
   - At decimal point
   - In exponent

3. **Stress Tests**:
   - 1-byte chunks (pathological)
   - Chunks ending at every position
   - Very long strings (>chunk_size)
   - Nested structures at boundaries

### Test Utilities Needed

```zig
fn testChunkingAtEveryPosition(input: []const u8) !void {
    for (1..input.len) |chunk_size| {
        var iterator = createIterator(input, chunk_size);
        const tokens = try collectAllTokens(&iterator);
        try verifyTokensMatch(expected_tokens, tokens);
    }
}
```

## Decision Required

**Recommended Approach**:
1. Start with Option B+ (smart chunking) - simpler, solves most cases
2. Implement Option A (stateful) only if B+ proves insufficient
3. Consider hybrid: B+ for performance, A as fallback

**Why**: Option B+ is 10x simpler, likely solves 95% of real-world cases, and doesn't require major architectural changes. Option A is the "correct" solution but adds significant complexity.

## Implementation Checklist

- [ ] Decide on approach (B+ first or straight to A)
- [ ] Answer architecture questions
- [ ] Implement chosen solution
- [ ] Add comprehensive chunk boundary tests
- [ ] Performance benchmark streaming vs. full tokenization
- [ ] Update documentation with streaming limitations
- [ ] Consider deprecating streaming for JSON if too complex

## Files to Modify

1. `/src/lib/transform/streaming/token_iterator.zig` - Core streaming logic
2. `/src/lib/languages/json/lexer.zig` - Add stateful support (Option A)
3. `/src/lib/test/performance_gates.zig` - Update streaming tests
4. New: `/src/lib/transform/streaming/stateful_lexer.zig` (Option A)
5. New: `/src/lib/test/streaming_boundary_test.zig` - Edge case tests

## Success Criteria

- No data loss when chunks split tokens
- Correct tokenization regardless of chunk boundaries  
- Performance within 20% of non-streaming for typical JSON
- All chunk boundary test cases pass
- No infinite loops or position stalls

---

**Priority**: HIGH - Data loss is worse than performance issues
**Complexity**: MEDIUM (B+) to HIGH (A)
**Estimated**: 2-3 days for Option B+, 1 week for Option A