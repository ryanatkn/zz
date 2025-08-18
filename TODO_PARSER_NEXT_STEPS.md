# TODO_PARSER_NEXT_STEPS

## ✅ Completed (Latest Session - Centralized Character Module)
- **Created centralized `src/lib/char/` module** - Single source of truth!
  - `predicates.zig` - All character classification (isDigit, isAlpha, etc.)
  - `consumers.zig` - Text consumption utilities (skipWhitespace, consumeString, etc.)
  - `mod.zig` - Clean module exports
- **Eliminated 5+ duplicate implementations of skipWhitespace**
  - Updated `parser/lexical/scanner.zig` to use char module
  - Updated `parser/lexical/tokenizer.zig` to use char module
  - Updated `languages/json/lexer.zig` to use char module
  - Updated `languages/zon/lexer.zig` to use char module
- **Cleaned up `parser/lexical/utils.zig`** - Now just re-exports char module
- **Deleted `languages/common/patterns.zig`** - Fully replaced by char module
- **Created language-specific pattern modules** (from previous session)
  - `typescript/patterns.zig`, `zig/patterns.zig`, `css/patterns.zig`, `html/patterns.zig`
- **Started JSON formatter refactoring** to use visitor pattern

## ✅ Previous Session Completions
- Fixed `memory.zig` compilation errors (MemoryPool & ScopedAllocator)
- **Refactored JSON analyzer** to use AST traversal utilities
- **Refactored ZON analyzer** to use AST utilities
- Added `ASTTraversal` to ZON common imports
- Fixed AST traversal utilities (unused parameters)

## 🔧 Build Status
- **537/569 tests passing** (94.5% success rate)
- **7 compilation errors** in AST modules (needs fixing)
- **6 memory leaks** (stable)

## 📝 Immediate Fixes Needed
1. Fix compilation errors in `test_helpers.zig` (AST deinit issues)
2. Fix `traversal.zig` comptime value resolution
3. Fix `analyzer.zig` type conversion (usize to u32)
4. Update `deps/config.zig` to handle dynamic dependencies

## 🎯 Architecture Improvements Completed
1. **✅ Clean Pattern Organization**
   - Language patterns moved to respective language modules
   - Generic text utilities separated from language specifics
   - ~400+ lines properly organized

2. **✅ Shared Lexer Utilities Created**
   - Common tokenization functions in `parser/lexical/utils.zig`
   - Ready to eliminate ~100+ lines of duplication
   - Character predicates and token consumers centralized

3. **✅ AST Utils Usage Increased**
   - JSON/ZON analyzers use `ASTTraversal` for tree walking
   - Replaced ~200 lines of manual traversal code
   - Visitor pattern consistently applied

## 🚀 Next Priority Tasks
1. Fix AST module compilation errors (7 errors remaining)
2. Complete ZON formatter visitor pattern refactoring
3. Apply memory utilities throughout codebase
4. Continue unifying shared utilities across modules

## 📊 Metrics
- **Code reduction: ~300+ lines eliminated** through char module consolidation
- Code organization: ~400+ lines of patterns properly placed
- Duplication eliminated: 5+ skipWhitespace, 3+ isDigit implementations
- Test status: 537/569 passing (94.5%)
- Languages with patterns: 4/7 (TypeScript, Zig, CSS, HTML)
- Memory leak stable at 6