# TODO_PARSER_NEXT_STEPS

## ✅ Completed (Latest Session)
- Fixed `memory.zig` compilation errors (MemoryPool & ScopedAllocator)
- **Refactored JSON analyzer** to use AST traversal utilities
  - `calculateStatistics()` now uses visitor pattern with `ASTTraversal.walk()`
  - `extractSymbolsFromNode()` replaced manual recursion with traversal
  - Using `ASTUtils.getASTStatistics()` for depth calculation
- **Refactored ZON analyzer** to use AST utilities
  - `collectSymbols()` uses visitor pattern
  - `extractDependenciesFromObject()` uses `ASTTraversal.findNodes()`
  - `analyzeNodeStatistics()` uses `ASTUtils.getASTStatistics()`
- Added `ASTTraversal` to ZON common imports
- Fixed AST traversal utilities (unused parameters)

## 🔧 Build Status
- **537/569 tests passing** (94.5% success rate)
- **7 compilation errors** remaining (unrelated to refactoring)
- **6 memory leaks** (stable)

## 📝 Immediate Fixes Needed
1. Fix remaining compilation errors in test_helpers.zig
2. Fix traversal.zig comptime issues
3. Update `deps/config.zig` to handle dynamic dependencies (not hardcoded)

## 🎯 Architecture Improvements Completed
1. **✅ AST Utils Usage Increased**
   - JSON/ZON analyzers now use `ASTTraversal` for tree walking
   - Replaced ~200 lines of manual traversal code
   - Using visitor pattern consistently

2. **Pattern Matching** (Still TODO)
   - Need to unify glob/text patterns API
   - Extract common lexer patterns

3. **Memory Management** 
   - `memory.zig` utilities created and fixed
   - Need to apply throughout codebase

## 🚀 Next Priority Tasks
1. Refactor JSON/ZON formatters to use visitor pattern
2. Extract common lexer patterns to shared utilities  
3. Refactor parsers to use text utilities
4. Create generic dependency parsing (not hardcoded)
5. Document new utilities usage patterns

## 📊 Metrics
- Code reduction: ~700 lines removed (200 more from traversal refactoring)
- Test improvement: 529→537 (8 more fixed)
- Refactoring coverage: 2/7 languages fully refactored
- Memory leak stable at 6