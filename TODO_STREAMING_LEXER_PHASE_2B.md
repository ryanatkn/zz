# TODO_STREAMING_LEXER_PHASE_2B.md - TypeScript & Zig Validation

## Phase 2B: Validate Architecture with Complex Languages

### Purpose
Implement TypeScript and Zig stateful lexers to validate our Phase 2A architecture with languages that have complex lexical features. This will confirm our design choices before moving to Phase 3 (Parser Integration).

### Critical Questions to Answer

#### 1. Token Size & Memory Efficiency
- **Current**: 96 bytes per token (2 cache lines)
- **Concern**: Is this too large for editor performance?
- **Test**: Benchmark with 10MB TypeScript file
- **Alternative**: Tagged pointer approach for common cases?

#### 2. Streaming Performance  
- **Current**: ~2100ns/token with conversion overhead
- **Target**: <50ns/token for lexing alone
- **Question**: Can we maintain performance with complex state machines?
- **Test**: Profile hot paths with TypeScript JSX/templates

#### 3. State Machine Complexity
- **TypeScript Challenges**:
  - JSX disambiguation (`<` as tag vs comparison)
  - Template literal nesting with `${}`
  - Regex literal context detection
  - Type annotations after `:`
- **Zig Challenges**:
  - Comptime context tracking
  - Raw string literals `r"..."`
  - Multiline strings `\\`
  - Builtin functions `@import`
- **Question**: Can StatefulLexer handle these without explosion?

#### 4. Memory Pool Strategy
- **Current**: Allocate per chunk
- **Concern**: Fragmentation with many small chunks
- **Alternative**: Arena allocator with reset per file?
- **Test**: Memory usage over time with incremental edits

### Implementation Plan

## Module 1: TypeScript Stateful Lexer

### TypeScriptToken Design
```
Size target: ≤128 bytes
Key variants:
- jsx_element (tag name, self-closing flag)
- template_literal (parts array reference)
- regex_literal (pattern, flags)
- type_annotation (after colon detection)
```

### State Machine Extensions
- **JSX Context**: Track `jsx_depth`, disambiguate via lookahead
- **Template Context**: Stack-based for `${}` nesting
- **Regex Context**: Heuristic detection after operators
- **Arrow Functions**: Detect `=>` for parameter lists

### Integration Points
- `src/lib/languages/typescript/stateful_lexer.zig`
- `src/lib/languages/typescript/tokens.zig`
- `src/lib/languages/typescript/streaming_adapter.zig`

## Module 2: Zig Stateful Lexer

### ZigToken Design
```
Size target: ≤96 bytes
Key variants:
- comptime_block (nesting level)
- builtin_call (function name)
- doc_comment (preserve for LSP)
- raw_string (no escapes)
```

### State Machine Extensions
- **Comptime Context**: Track entry/exit
- **String Contexts**: Raw vs normal vs multiline
- **Builtin Detection**: `@` prefix handling
- **Error Union**: `!` and `catch` tracking

### Integration Points
- `src/lib/languages/zig/stateful_lexer.zig`
- `src/lib/languages/zig/tokens.zig`
- `src/lib/languages/zig/streaming_adapter.zig`

## Module 3: Performance Validation

### Benchmarks Required
1. **Token Size Impact**
   - Measure cache misses with 96-byte tokens
   - Compare with 64-byte alternative
   
2. **Streaming Overhead**
   - Direct emission vs conversion cost
   - Iterator vs batch performance
   
3. **State Machine Cost**
   - Context switch overhead
   - Lookahead penalty for disambiguation

### Memory Analysis
- Peak usage for 1MB/10MB/100MB files
- Allocation patterns with streaming
- GC pressure (if any)

## Module 4: Architecture Refinements

### Potential Optimizations
1. **Token Compression**
   - Use indices instead of slices for common strings
   - Pack flags more aggressively
   - Consider separate metadata storage

2. **Lazy Conversion**
   - Only convert tokens in viewport
   - Cache converted tokens with TTL

3. **SIMD Opportunities**
   - Delimiter scanning for TypeScript
   - Whitespace skipping

### API Adjustments
- Should TokenIterator be the primary interface?
- Do we need a token pool for reuse?
- Can we eliminate TokenData overhead?

## Success Criteria

### Functional
- [ ] TypeScript handles all TS/TSX features correctly
- [ ] Zig handles all language features
- [ ] Chunk boundaries work for complex tokens
- [ ] Error recovery maintains correctness

### Performance  
- [ ] TypeScript: <100ns/token average
- [ ] Zig: <75ns/token average
- [ ] Memory: <100KB per MB of source
- [ ] Conversion: <10% overhead

### Architecture
- [ ] No API changes needed for complex languages
- [ ] State machine remains manageable
- [ ] Memory usage predictable

## Risk Areas

### High Risk
1. **JSX Disambiguation** - May need multi-token lookahead
2. **Template Literal Nesting** - Stack depth concerns
3. **Memory Fragmentation** - Many small allocations

### Medium Risk
1. **Token Size Growth** - TypeScript might need >128 bytes
2. **State Explosion** - Combined contexts multiply
3. **Performance Regression** - Complex state machines slow

### Mitigation Strategies
- Profile early and often
- Consider language-specific optimizations
- Have fallback to simpler token types

## Implementation Order

1. **TypeScript Tokens** (4h)
   - Define TypeScriptToken union
   - Size analysis and optimization
   
2. **TypeScript Lexer** (8h)
   - State machine implementation
   - JSX/template/regex handling
   
3. **Zig Tokens** (2h)
   - Define ZigToken union
   - Comptime/builtin support
   
4. **Zig Lexer** (6h)
   - State machine implementation
   - String variant handling
   
5. **Performance Testing** (4h)
   - Benchmarks and profiling
   - Memory analysis
   
6. **Refinements** (4h)
   - Address discovered issues
   - Optimize hot paths

Total estimate: 28 hours

## Decision Points

Before proceeding to Phase 3, we must answer:

1. **Is 96-byte token acceptable?**
   - If no: Implement compression strategy
   
2. **Is streaming conversion fast enough?**
   - If no: Consider zero-copy token wrapper
   
3. **Can state machine handle all contexts?**
   - If no: Evaluate parser-based approach
   
4. **Is memory usage bounded?**
   - If no: Implement pooling/arena strategy

## Notes

- Focus on correctness first, optimize later
- Keep language-specific logic isolated
- Document all heuristics and assumptions
- Consider editor viewport priorities
- Plan for incremental parsing needs

---

**Priority**: HIGH - Must validate before Phase 3
**Risk**: MEDIUM - Complex languages may expose issues
**Impact**: FOUNDATIONAL - Determines final architecture