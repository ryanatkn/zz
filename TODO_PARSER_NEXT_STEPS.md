# TODO_PARSER_NEXT_STEPS

## ✅ Completed (Latest Session - Pattern Organization & Lexer Utils)
- **Created language-specific pattern modules** (clean architecture!)
  - `typescript/patterns.zig` - Functions, types, imports, keywords
  - `zig/patterns.zig` - Functions, declarations, types, builtins
  - `css/patterns.zig` - Selectors, at-rules, properties, units
  - `html/patterns.zig` - Void elements, attributes, input types
- **Cleaned up `patterns/text.zig`** - Removed all language-specific patterns
- **Created `parser/lexical/utils.zig`** - Shared lexer utilities
  - Character predicates: `isDigit()`, `isAlpha()`, `isHexDigit()`
  - Token consumers: `consumeString()`, `consumeNumber()`, `consumeIdentifier()`
  - Comment handlers: `consumeSingleLineComment()`, `consumeMultiLineComment()`
  - Whitespace utilities: `skipWhitespace()`, `skipWhitespaceAndNewlines()`
- **Started JSON formatter refactoring** to use visitor pattern
  - Added `ASTTraversal` and `ASTUtils` imports
  - Modified to use `*const Node` for immutability

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
1. Fix AST module compilation errors
2. Complete JSON/ZON formatter visitor pattern refactoring
3. Update JSON/ZON lexers to use shared `lexical/utils.zig`
4. Update parsers to use `patterns/text.zig` utilities
5. Apply memory utilities throughout codebase

## 📊 Metrics
- Code organization: ~400+ lines of patterns properly placed
- Potential reduction: ~100+ lines from lexer deduplication
- Test status: 537/569 passing (94.5%)
- Languages with patterns: 4/7 (TypeScript, Zig, CSS, HTML)
- Memory leak stable at 6