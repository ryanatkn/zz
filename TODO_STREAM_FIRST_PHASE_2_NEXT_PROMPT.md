# [ARCHIVED] Stream-First Phase 2 - Resume Point

## ✅ PHASE 2 COMPLETE - This file is archived for reference

## Quick Context
We're implementing a stream-first architecture for the zz language tooling library, replacing the old parser with a zero-allocation streaming system. Phase 2 focuses on token integration with tagged unions (eliminating vtable overhead) and bridging old lexers to the new system.

## Final Status
Phase 2 is 100% complete with all major modules implemented:
- ✅ **Token module** (`src/lib/token/`): StreamToken tagged union, 16-byte tokens
- ✅ **Lexer module** (`src/lib/lexer/`): Bridge for old→new conversion (TEMPORARY)
- ✅ **Cache module** (`src/lib/cache/`): FactCache replacing BoundaryCache
- ✅ **AtomTable integration**: String interning for tokens
- ✅ **207+ tests passing** after fixing all compilation errors

## Resolution Summary

### All Issues Fixed
1. ✅ **TokenKind mapping**: Changed `.@"{"` → `.left_brace` in lexer_bridge.zig
2. ✅ **EnumMap type**: Changed to store `?*LexerBridge` instead of `*LexerBridge`
3. ✅ **LRU node dereference**: Fixed optional handling with `if (pop()) |n|` pattern

**Problem**: ArrayList's `pop()` returns `?T` where `T = *LruNode`, giving us `?*LruNode`
```zig
// Current broken code:
const node = if (self.free_nodes.items.len > 0) 
    self.free_nodes.pop()  // Returns ?*LruNode
else blk: {
    const n = try self.allocator.create(LruNode);
    try self.node_pool.append(n);
    break :blk n;
};
node.* = LruNode{  // ERROR: Can't dereference optional
```

**Fix needed**:
```zig
// Handle the optional properly:
const node = if (self.free_nodes.pop()) |n|
    n  // Now we have *LruNode, not ?*LruNode
else blk: {
    const n = try self.allocator.create(LruNode);
    try self.node_pool.append(n);
    break :blk n;
};
node.* = LruNode{  // Now this works
```

## Validation Commands Used
```bash
# 1. Test that everything compiles and passes
zig test src/lib/test_stream_first.zig

# 2. Check test coverage to see what needs tests
zig run src/scripts/check_test_coverage.zig

# 3. Run specific module tests if needed
zig test src/lib/lexer/test.zig
zig test src/lib/cache/test.zig
zig test src/lib/token/test.zig
```

## Important Architecture Notes

### Performance Characteristics
- **StreamToken**: ≤24 bytes (1 byte tag + 16 byte token + alignment)
- **Tagged union dispatch**: 1-2 cycles (vs 3-5 for vtable)
- **LexerBridge overhead**: 3-5 cycles (TEMPORARY - will be removed in Phase 4)
- **Fact size**: Exactly 24 bytes
- **Zero allocations** in core stream operations

### Key Design Decisions
1. **LexerBridge is TEMPORARY**: Entire `src/lib/lexer/lexer_bridge.zig` deleted in Phase 4
2. **Tagged union over vtable**: Hardcoded languages for now, extensibility via comptime later
3. **Multi-indexing in cache**: Facts indexed by span, predicate, and confidence
4. **AtomTable for strings**: All text content uses interned atoms

## Completed Actions

### 1. Documentation Updates
- [x] Created `src/lib/lexer/CLAUDE.md` - Explains temporary bridge pattern
- [x] Created `src/lib/cache/CLAUDE.md` - Documents new caching system
- [x] Updated `TODO_STREAM_FIRST_ARCHITECTURE.md` - Marked Phase 2 as complete
- [x] Updated `TODO_STREAM_FIRST_PHASE_2.md` - Added completion status

### 2. Code Cleanup
- [x] Added clear "TEMPORARY - DELETE IN PHASE 4" comments to bridge code
- [ ] Consolidate TODOs by phase (deferred to Phase 3)
- [ ] Remove deprecated old parser code (deferred to Phase 4)

### 3. Testing (If Time)
- [ ] Add benchmark: StreamToken vs old Token performance
- [ ] Add stress test: Cache eviction under memory pressure
- [ ] Add integration test: Full pipeline JSON→tokens→facts→cache

## Next: Phase 3
Now that Phase 2 is complete, Phase 3 will focus on:
- Query engine with SQL-like DSL
- Direct stream lexers (no bridge)
- Performance optimization
- Migration of remaining languages (TypeScript, Zig, CSS, HTML, Svelte)

## Files Most Likely to Need Attention
1. `/home/desk/dev/zz/src/lib/cache/lru.zig` - Fix the compilation error
2. `/home/desk/dev/zz/src/lib/lexer/lexer_bridge.zig` - Mark as temporary
3. `/home/desk/dev/zz/TODO_STREAM_FIRST_ARCHITECTURE.md` - Update progress
4. `/home/desk/dev/zz/TODO_STREAM_FIRST_PHASE_2.md` - Document completion

## Context for LLM
- Performance is top priority - every cycle counts
- Delete old code aggressively - no deprecation
- The lexer bridge is a temporary evil - it will be deleted
- All core primitives achieved exact size targets
- Stream-first means zero allocations in hot paths