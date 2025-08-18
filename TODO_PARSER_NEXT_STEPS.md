# TODO_PARSER_NEXT_STEPS - Final Implementation Roadmap

## 🏆 Current State (2025-08-18)
- **Test Status**: 574/591 passing (97.1% success rate)
- **Memory Status**: 12 leaks identified (down from critical segfaults)
- **Languages Complete**: JSON ✅, ZON ✅
- **Languages In Progress**: CSS (patterns ready), HTML (patterns ready)
- **Languages Pending**: TypeScript, Zig, Svelte

## 📋 Phase 1: Test Suite Stabilization (Priority: CRITICAL)

### 1.1 Tree Walker Test Fixes (5 tests)
**Location**: `src/tree/test/walker_test.zig`
**Issue**: Pattern matching logic not handling nested paths correctly

**Failed Tests**:
- `basic ignored directories are not crawled`
- `nested path patterns are not crawled` 
- `dot-prefixed directories are not crawled`
- `configuration fallbacks and edge cases`
- `real project structure is handled correctly`

**Fix Required**:
- Enhance `shouldIgnorePath` in `src/config.zig` to handle:
  - Nested path patterns (e.g., `src/ignored/deep/path`)
  - Relative vs absolute path matching
  - Proper glob pattern support

### 1.2 Deps Hashing Test Fixes (2 tests)
**Location**: `src/lib/deps/hashing.zig`
**Issue**: FileNotFound errors in temporary directory operations

**Failed Tests**:
- `ChangeDetector - hash consistent content`
- `ChangeDetector - detect changes`

**Fix Required**:
- Ensure temp directory exists before file operations
- Add proper error handling for missing directories
- Consider using mock filesystem for tests

### 1.3 Parser Structural Test Fix
**Location**: `src/lib/parser/structural/parser.zig`
**Issue**: Error recovery test failing on viewport tokenization timing

**Fix Required**:
- Adjust timing expectations for error recovery scenarios
- Consider separate thresholds for error cases

### 1.4 QueryCache LRU Test Fix
**Location**: `src/lib/parser/foundation/collections/query_cache.zig`
**Issue**: LRU eviction logic not working correctly

**Fix Required**:
- Review eviction algorithm implementation
- Ensure proper ordering of cache entries

## 📋 Phase 2: Memory Leak Resolution (Priority: HIGH)

### 2.1 Grammar Resolver Memory Leak
**Location**: `src/lib/grammar/resolver.zig:59`
**Leak**: Rules allocated with `allocator.create(rule.Rule)` not freed

**Fix Required**:
```zig
// Add tracking array in resolver
resolved_rules: std.ArrayList(*rule.Rule)

// Track allocations
try self.resolved_rules.append(resolved_rule);

// Free in deinit
for (self.resolved_rules.items) |r| {
    self.allocator.destroy(r);
}
```

### 2.2 AST Test Helpers Cleanup
**Location**: `src/lib/ast/test_helpers.zig`
**Issue**: Test context not properly cleaning up ASTs

**Fix Required**:
- Review TestContext.deinit() implementation
- Ensure all created ASTs are properly freed
- Fix cross-module import issues

### 2.3 Deps Config Memory Management
**Location**: `src/lib/deps/config.zig`
**Issue**: Complex string ownership causing leaks

**Fix Required**:
- Complete string ownership tracking
- Add proper cleanup for all allocated strings
- Consider using arena allocator for batch cleanup

### 2.4 Other Identified Leaks
- **Tree tests**: Possible config allocations not freed
- **Benchmark tests**: Timer or stats allocations
- **Format tests**: Formatter output buffers

## 📋 Phase 3: CSS Language Implementation (Priority: HIGH)

### 3.1 CSS Lexer ✅ (Pattern exists)
**Location**: `src/lib/languages/css/lexer.zig`
**Status**: Patterns ready in `css/patterns.zig`

**Implementation**:
```zig
pub const CssLexer = struct {
    // Tokenize selectors: .class, #id, element, [attribute]
    // Tokenize properties: color, margin, padding, etc.
    // Tokenize values: colors, units, functions
    // Handle comments: /* */ 
    // Handle at-rules: @media, @keyframes, @import
};
```

### 3.2 CSS Parser
**Location**: `src/lib/languages/css/parser.zig`

**Implementation**:
```zig
pub const CssParser = struct {
    // Parse rules: selector { declarations }
    // Parse media queries
    // Parse keyframes
    // Build CSS AST with specificity info
};
```

### 3.3 CSS Formatter
**Location**: `src/lib/languages/css/formatter.zig`

**Features**:
- Indent nested rules
- Format declarations (one per line or compact)
- Preserve or remove comments
- Minification mode

### 3.4 CSS Analyzer
**Location**: `src/lib/languages/css/analyzer.zig`

**Features**:
- Calculate selector specificity
- Extract CSS variables
- Find duplicate rules
- Detect unused animations

## 📋 Phase 4: HTML Language Implementation (Priority: HIGH)

### 4.1 HTML Lexer ✅ (Pattern exists)
**Location**: `src/lib/languages/html/lexer.zig`
**Status**: Patterns ready in `html/patterns.zig`

**Implementation**:
```zig
pub const HtmlLexer = struct {
    // Tokenize tags: <div>, </div>, <img />
    // Tokenize attributes: class="", id="", data-*
    // Tokenize text content
    // Handle doctypes and comments
    // Handle special tags: script, style
};
```

### 4.2 HTML Parser
**Location**: `src/lib/languages/html/parser.zig`

**Implementation**:
```zig
pub const HtmlParser = struct {
    // Build DOM-like tree
    // Handle void elements
    // Parse attributes
    // Handle malformed HTML gracefully
};
```

### 4.3 HTML Formatter
**Location**: `src/lib/languages/html/formatter.zig`

**Features**:
- Indent nested elements
- Format attributes (one per line or inline)
- Preserve whitespace in pre/code tags
- Pretty print or minify

### 4.4 HTML Analyzer
**Location**: `src/lib/languages/html/analyzer.zig`

**Features**:
- Validate nesting rules
- Check accessibility (alt tags, ARIA)
- Extract meta information
- Find broken links

## 📋 Phase 5: Final Cleanup (Priority: MEDIUM)

### 5.1 Configuration System Completion
**Location**: `src/config.zig`
- Implement `handleSymlink` function (line 54)
- Improve pattern matching for complex paths
- Add glob pattern support

### 5.2 Remove Critical TODOs
**Priority Files**:
- `src/lib/deps/config.zig` - Complete memory management
- `src/lib/languages/json/formatter.zig` - Finish visitor pattern
- `src/lib/ast/query.zig` - Complete attribute matching

### 5.3 Documentation Updates
- Update architecture docs with final state
- Document CSS/HTML implementation
- Add memory management best practices

## 🎯 Success Criteria

### Phase 1 Complete
- ✅ All 591 tests passing
- ✅ No segmentation faults
- ✅ Stable CI/CD pipeline

### Phase 2 Complete  
- ✅ Zero memory leaks
- ✅ Clean valgrind report
- ✅ Proper cleanup in all modules

### Phase 3 & 4 Complete
- ✅ CSS lexer, parser, formatter working
- ✅ HTML lexer, parser, formatter working
- ✅ Both languages integrated with CLI
- ✅ Test coverage >90%

### Phase 5 Complete
- ✅ No critical TODOs in production code
- ✅ Complete documentation
- ✅ All patterns properly implemented

## 📊 Final Metrics Target

- **Test Success**: 591/591 (100%)
- **Memory Leaks**: 0
- **Languages Complete**: 4/7 (JSON, ZON, CSS, HTML)
- **Code Coverage**: >90%
- **Performance**: All operations <10ms for typical files
- **Documentation**: 100% public API documented

## 🚀 Estimated Timeline

- **Week 1**: Phase 1 & 2 (Test fixes & memory leaks)
- **Week 2**: Phase 3 (CSS implementation)
- **Week 3**: Phase 4 (HTML implementation)  
- **Week 4**: Phase 5 (Final cleanup & documentation)

## 📝 Notes

**Priority Order**: 
1. Fix failing tests (blocks everything)
2. Fix memory leaks (blocks release)
3. Complete CSS/HTML (core functionality)
4. Clean up remaining issues

**Key Dependencies**:
- Test fixes required before new features
- Memory leaks must be fixed for production
- CSS/HTML share similar patterns and structure

**Risk Mitigation**:
- Focus on test stability first
- Use existing patterns from JSON/ZON
- Incremental implementation with tests

---

*Remember: Performance is the top priority - every cycle and byte count*
*Focus: Ship working CSS/HTML support with zero memory leaks*