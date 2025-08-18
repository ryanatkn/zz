# TODO_PARSER_NEXT - Unified Language Module Architecture

**Status**: Phase 2 Complete | JSON Reference Implementation Complete | Ready for Remaining Languages  
**Goal**: Unified architecture for TypeScript, Svelte, JSON, Zig, ZON, CSS, HTML support  
**Last Updated**: 2025-08-18 - Phase 2 Complete: JSON Implementation

## 📊 Current State Analysis

### ✅ Phase 1 Complete: Unified Language Architecture
The codebase now has a clean, unified language support architecture:

1. **src/lib/languages/** - Unified language implementations
   - `mod.zig` - Central language registry and dispatch
   - `interface.zig` - Language support contracts (LanguageSupport, Lexer, Parser, Formatter, etc.)
   - `registry.zig` - Enhanced registry with caching and global instance management
   - `common/` - Shared utilities for all languages (tokens, patterns, formatting, analysis)
   - Individual language modules for all 7 supported languages

2. **Legacy modules** - Still present for compatibility:
   - **src/lib/parsing/** - Legacy formatter stubs (to be deprecated)
   - **src/lib/language/** - Language detection and flags (integrated with new system)

3. **Foundation systems** - Ready for integration:
   - **src/lib/parser/** - Pure Zig Stratified Parser (lexical, structural, detailed layers)
   - **src/lib/grammar/** - Grammar DSL system with examples
   - **src/lib/text/** - Text utilities for delimiter tracking and formatting

### ✅ Phase 2 Complete: JSON Reference Implementation
The JSON language module is now **production-ready** and serves as the reference implementation:

1. **Complete JSON Language Support** (`src/lib/languages/json/`):
   - ✅ **High-Performance Lexer** - Streaming tokenization with <0.1ms for 10KB
   - ✅ **Robust Parser** - AST-based parsing with error recovery (<1ms for 10KB)
   - ✅ **Configurable Formatter** - Pretty-printing with smart decisions (<0.5ms for 10KB)
   - ✅ **Comprehensive Linter** - 7 validation rules with configurable severity
   - ✅ **Advanced Analyzer** - Schema extraction, TypeScript interface generation
   - ✅ **Complete Integration** - Full LanguageSupport interface implementation
   - ✅ **Extensive Testing** - 698 lines of comprehensive tests
   - ✅ **Performance Benchmarks** - Validated <2ms complete pipeline for 10KB
   - ✅ **Complete Documentation** - 650+ lines including API reference and examples

2. **Performance Targets Achieved**:
   - ✅ **Lexing**: <0.1ms for 10KB JSON (target: 0.1ms)
   - ✅ **Parsing**: <1ms for 10KB JSON (target: 1ms)
   - ✅ **Formatting**: <0.5ms for 10KB JSON (target: 0.5ms)
   - ✅ **Complete Pipeline**: <2ms for 10KB JSON (target: 2ms)

3. **Reference Implementation Value**:
   - ✅ **Patterns Established** - Clear template for implementing other languages
   - ✅ **Interface Validation** - Proven LanguageSupport contract works in practice
   - ✅ **Integration Success** - Seamlessly works with existing `zz format` command
   - ✅ **Quality Standard** - Production-ready with comprehensive error handling

### What We Have Now
- ✅ **Unified Language Architecture** - All languages implement common interface
- ✅ **Language Registry** - Centralized dispatch with caching
- ✅ **Shared Infrastructure** - Common utilities for tokens, patterns, formatting, analysis
- ✅ **Interface Contracts** - Well-defined APIs proven with JSON implementation
- ✅ **JSON Complete** - Production-ready reference implementation (4,473 lines)
- ✅ **6 Language Stubs** - TypeScript, Svelte, Zig, ZON, CSS, HTML ready for implementation
- ✅ **Backward Compatibility** - Existing functionality preserved
- ✅ **Performance Foundation** - Registry caching, shared patterns, performance targets validated
- ✅ **Proven Architecture** - JSON implementation validates the unified design

## 🎯 Final Module Architecture

### Core Design Principles
1. **Language as First-Class Citizen**: Each language gets complete module ownership
2. **Stratified Parser Integration**: Leverage the three-layer architecture
3. **Shared Infrastructure**: Common utilities in lib/core
4. **Performance First**: <10ms parsing for 1000 lines
5. **Pluggable Design**: Easy to add new languages

### Directory Structure
```
src/lib/languages/              # Unified language support
├── mod.zig                     # Language registry and dispatch
├── interface.zig               # Common interfaces all languages implement
├── common/                     # Shared language utilities
│   ├── tokens.zig              # Common token types (operators, keywords)
│   ├── patterns.zig            # Shared parsing patterns
│   ├── formatting.zig          # Common formatting utilities
│   └── analysis.zig            # Shared analysis tools
│
├── typescript/                 # TypeScript/JavaScript support
│   ├── mod.zig                 # Module exports
│   ├── lexer.zig               # Layer 0: Tokenization
│   ├── structure.zig           # Layer 1: Boundary detection
│   ├── parser.zig              # Layer 2: Full AST parsing
│   ├── formatter.zig           # Code formatting
│   ├── linter.zig              # Linting rules
│   ├── analyzer.zig            # Semantic analysis
│   ├── grammar.zig             # Grammar definition
│   └── test.zig                # Language tests
│
├── svelte/                     # Svelte multi-language support
│   ├── mod.zig                 
│   ├── regions.zig             # Script/style/template regions
│   ├── lexer.zig               # Multi-mode tokenization
│   ├── structure.zig           # Component boundaries
│   ├── parser.zig              # Embedded language parsing
│   ├── formatter.zig           # Region-aware formatting
│   ├── linter.zig              # Svelte-specific rules
│   ├── analyzer.zig            # Component analysis
│   └── test.zig
│
├── json/                       # JSON support (✅ COMPLETE - Reference Implementation)
│   ├── mod.zig                 # LanguageSupport implementation & convenience functions
│   ├── lexer.zig               # High-performance streaming tokenization
│   ├── parser.zig              # AST-based parsing with error recovery
│   ├── formatter.zig           # Configurable pretty-printing with smart decisions
│   ├── linter.zig              # Comprehensive validation with 7 built-in rules
│   ├── analyzer.zig            # Schema extraction & TypeScript interface generation
│   ├── test.zig                # Comprehensive test suite (698 lines)
│   ├── benchmark.zig           # Performance benchmarks & validation
│   └── README.md               # Complete documentation & API reference
│
├── zig/                        # Zig language support
│   ├── mod.zig                 
│   ├── lexer.zig               # Zig tokenization
│   ├── structure.zig           # Function/struct boundaries
│   ├── parser.zig              # Full Zig AST
│   ├── formatter.zig           # Zig formatting (delegates to zig fmt)
│   ├── linter.zig              # Zig best practices
│   ├── analyzer.zig            # Comptime analysis
│   ├── grammar.zig             # Zig grammar
│   └── test.zig
│
├── zon/                        # ZON configuration language
│   ├── mod.zig                 
│   ├── lexer.zig               # ZON tokenization
│   ├── parser.zig              # Proper AST-based parsing
│   ├── formatter.zig           # ZON formatting
│   ├── validator.zig           # Config validation
│   └── test.zig
│
├── css/                        # CSS support
│   ├── mod.zig                 
│   ├── lexer.zig               # CSS tokenization
│   ├── parser.zig              # Rule parsing
│   ├── formatter.zig           # CSS formatting
│   ├── linter.zig              # Style rules
│   ├── analyzer.zig            # Selector analysis
│   └── test.zig
│
└── html/                       # HTML support
    ├── mod.zig                 
    ├── lexer.zig               # Tag tokenization
    ├── parser.zig              # DOM tree construction
    ├── formatter.zig           # HTML formatting
    ├── linter.zig              # Accessibility rules
    ├── analyzer.zig            # Structure analysis
    └── test.zig
```

## 🔌 Unified Language Interface

### Core Interfaces
```zig
// src/lib/languages/interface.zig

pub const LanguageSupport = struct {
    /// Language identifier
    language: Language,
    
    /// Layer 0: Lexical tokenization
    lexer: Lexer,
    
    /// Layer 1: Structural boundaries (optional)
    structure: ?StructureParser,
    
    /// Layer 2: Detailed parsing
    parser: Parser,
    
    /// Code formatter
    formatter: Formatter,
    
    /// Linter (optional)
    linter: ?Linter,
    
    /// Semantic analyzer (optional)
    analyzer: ?Analyzer,
};

pub const Lexer = struct {
    /// Tokenize input into stream of tokens
    tokenizeFn: *const fn (input: []const u8) anyerror![]Token,
    
    /// Incremental tokenization for edits
    updateFn: ?*const fn (tokens: []Token, edit: Edit) anyerror!TokenDelta,
};

pub const StructureParser = struct {
    /// Detect structural boundaries
    detectBoundariesFn: *const fn (tokens: []Token) anyerror![]Boundary,
    
    /// Get state machine for language
    getStateMachineFn: *const fn () StateMachine,
};

pub const Parser = struct {
    /// Parse tokens into AST
    parseFn: *const fn (tokens: []Token) anyerror!AST,
    
    /// Parse with boundaries for optimization
    parseWithBoundariesFn: ?*const fn (tokens: []Token, boundaries: []Boundary) anyerror!AST,
};

pub const Formatter = struct {
    /// Format AST back to source code
    formatFn: *const fn (ast: AST, options: FormatOptions) anyerror![]const u8,
    
    /// Format range (for editor integration)
    formatRangeFn: ?*const fn (ast: AST, range: Range, options: FormatOptions) anyerror![]const u8,
};

pub const Linter = struct {
    /// Available linting rules
    rules: []Rule,
    
    /// Run linting on AST
    lintFn: *const fn (ast: AST, rules: []Rule) anyerror![]Diagnostic,
};

pub const Analyzer = struct {
    /// Extract symbols (functions, types, variables)
    extractSymbolsFn: *const fn (ast: AST) anyerror![]Symbol,
    
    /// Build call graph
    buildCallGraphFn: ?*const fn (ast: AST) anyerror!CallGraph,
    
    /// Find references
    findReferencesFn: ?*const fn (ast: AST, symbol: Symbol) anyerror![]Reference,
};
```

## 🚀 Wide-Ranging Use Cases

### 1. Code Formatting
```zig
// Universal formatting interface
const formatter = try LanguageRegistry.getFormatter(language);
const formatted = try formatter.format(ast, .{
    .indent_size = 4,
    .line_width = 100,
    .trailing_comma = true,
});
```

### 2. Linting & Static Analysis
```zig
// Run language-specific linting rules
const linter = try LanguageRegistry.getLinter(language);
const diagnostics = try linter.lint(ast, .{
    .rules = &.{"no-unused-vars", "naming-convention"},
    .severity = .warning,
});
```

### 3. Type Checking
```zig
// TypeScript type checking
const analyzer = try LanguageRegistry.getAnalyzer(.typescript);
const type_errors = try analyzer.checkTypes(ast, .{
    .strict = true,
    .no_any = true,
});
```

### 4. Semantic Analysis
```zig
// Extract symbols and build call graphs
const symbols = try analyzer.extractSymbols(ast);
const call_graph = try analyzer.buildCallGraph(ast);
const deps = try analyzer.findDependencies(ast);
```

### 5. Editor Integration (LSP)
```zig
// Language Server Protocol support
pub const LanguageServer = struct {
    pub fn hover(self: *LS, params: HoverParams) !Hover {
        const language = detectLanguage(params.uri);
        const support = try LanguageRegistry.get(language);
        const ast = try support.parser.parse(params.content);
        const symbol = try support.analyzer.getSymbolAt(ast, params.position);
        return Hover{ .contents = symbol.documentation };
    }
    
    pub fn completion(self: *LS, params: CompletionParams) ![]CompletionItem {
        const support = try LanguageRegistry.get(params.language);
        return support.analyzer.getCompletions(params.ast, params.position);
    }
};
```

### 6. LLM Context Generation
```zig
// Optimize code for LLM prompts
pub fn generatePromptContext(files: []File) ![]const u8 {
    var context = StringBuilder.init(allocator);
    
    for (files) |file| {
        const support = try LanguageRegistry.get(file.language);
        const ast = try support.parser.parse(file.content);
        
        // Extract only signatures and key structures
        const symbols = try support.analyzer.extractSymbols(ast);
        for (symbols) |symbol| {
            if (symbol.kind == .function) {
                try context.append(symbol.signature);
            }
        }
    }
    
    return context.toOwnedSlice();
}
```

### 7. Code Transformation
```zig
// Modernize JavaScript to use async/await
pub fn modernizeCallbacks(ast: AST) !AST {
    const transformer = Transformer.init(.{
        .rules = &.{
            .{ .pattern = "callback", .replacement = "async_await" },
        },
    });
    return transformer.transform(ast);
}
```

### 8. Cross-Language Analysis
```zig
// Analyze Svelte component with embedded languages
pub fn analyzeSvelteComponent(content: []const u8) !ComponentAnalysis {
    const svelte = try LanguageRegistry.get(.svelte);
    const regions = try svelte.detectRegions(content);
    
    var analysis = ComponentAnalysis{};
    
    // Analyze script region with TypeScript
    if (regions.script) |script| {
        const ts = try LanguageRegistry.get(.typescript);
        analysis.script = try ts.analyzer.analyze(script);
    }
    
    // Analyze style region with CSS
    if (regions.style) |style| {
        const css = try LanguageRegistry.get(.css);
        analysis.style = try css.analyzer.analyze(style);
    }
    
    return analysis;
}
```

## 📋 Implementation Phases

### Phase 1: Infrastructure Setup ✅ COMPLETED
- [x] Create src/lib/languages/ directory structure
- [x] Define interface.zig with common language interfaces
- [x] Implement LanguageRegistry for language dispatch
- [x] Set up common/ utilities for shared patterns
- [x] Create stub modules for all 7 languages
- [x] Test compilation and backward compatibility

### Phase 2: Core Languages ✅ JSON COMPLETE
- [x] **JSON**: ✅ **COMPLETE** - Production-ready reference implementation
  - [x] High-performance lexer with JSON5 support (<0.1ms for 10KB)
  - [x] Robust parser with error recovery (<1ms for 10KB)
  - [x] Configurable formatter with smart decisions (<0.5ms for 10KB)
  - [x] Comprehensive linter with 7 validation rules
  - [x] Advanced analyzer with schema extraction & TypeScript generation
  - [x] Complete test suite (698 lines) and benchmarks
  - [x] Full documentation and API reference
- [ ] **ZON**: Fix parser using std.zig.Ast, add formatter
- [ ] **CSS**: Migrate existing formatter, add parser
- [ ] **HTML**: Migrate existing formatter, add parser

### Phase 3: Complex Languages (Week 4-5)
- [ ] **Zig**: Integrate with stratified parser, delegate to zig fmt
- [ ] **TypeScript**: Full lexer, parser, formatter implementation
- [ ] **Svelte**: Multi-region support, embedded language handling

### Phase 4: Advanced Features (Week 6)
- [ ] Implement linters for each language
- [ ] Add semantic analyzers where applicable
- [ ] Create language-specific test suites
- [ ] Performance optimization and benchmarking

### Phase 5: Integration (Week 7)
- [ ] Update format module to use new architecture
- [ ] Update prompt module for better extraction
- [ ] Add LSP foundation for future editor support
- [ ] Documentation and examples

## 🎯 Performance Targets

### Parsing Performance
- **Small files (<100 lines)**: <1ms
- **Medium files (100-1000 lines)**: <10ms
- **Large files (1000-10000 lines)**: <100ms
- **Memory usage**: <3x file size

### Formatting Performance
- **Format speed**: >10,000 lines/second
- **Round-trip**: format(format(x)) = format(x)
- **Incremental**: <1ms for single-line changes

### Analysis Performance
- **Symbol extraction**: <5ms for 1000 lines
- **Linting**: <20ms with all rules
- **Type checking**: <100ms for typical file

## 🧪 Testing Strategy

### Unit Tests
```zig
// Per-language test files
test "typescript parser" {
    const ts = try TypeScript.init(allocator);
    const ast = try ts.parser.parse("const x: number = 42;");
    try testing.expect(ast.root.children.len == 1);
}
```

### Integration Tests
```zig
// Cross-language scenarios
test "svelte component parsing" {
    const svelte = try Svelte.init(allocator);
    const component = 
        \\<script lang="ts">
        \\  let count: number = 0;
        \\</script>
        \\<style>
        \\  button { color: red; }
        \\</style>
        \\<button>{count}</button>
    ;
    const ast = try svelte.parse(component);
    try testing.expect(ast.regions.len == 3);
}
```

### Performance Benchmarks
```zig
// Benchmark each language
pub fn benchmarkLanguages() !void {
    inline for (supported_languages) |lang| {
        const large_file = try getLargeTestFile(lang);
        const time = try benchmark(lang, large_file);
        try testing.expect(time < performance_targets[lang]);
    }
}
```

## 🔄 Migration Path

### Step 1: Create New Structure
1. Set up src/lib/languages/ with subdirectories
2. Create interface definitions
3. Implement registry pattern

### Step 2: Migrate Existing Code
1. Move language detection from lib/language/
2. Extract formatters from scattered locations
3. Consolidate parser implementations

### Step 3: Deprecate Old Modules
1. Update imports to use new paths
2. Remove old parsing/ directory
3. Clean up duplicate implementations

### Step 4: Enhance and Extend
1. Add missing language features
2. Implement linters and analyzers
3. Optimize performance

## 📊 Success Metrics

### Functionality
- [x] **JSON language fully supported** ✅ (1/7 languages complete)
- [x] **JSON formatting works perfectly** ✅ (1/7 languages complete)
- [x] **JSON linting with 7 comprehensive rules** ✅ (1/7 languages complete)
- [x] **100% test coverage for JSON APIs** ✅ (JSON reference implementation)
- [ ] ZON, CSS, HTML languages (remaining core languages)
- [ ] TypeScript, Zig, Svelte languages (remaining complex languages)

### Performance
- [x] **JSON meets all performance targets** ✅ (<0.1ms lexing, <1ms parsing, <0.5ms formatting, <2ms pipeline)
- [x] **JSON has no memory leaks** ✅ (comprehensive memory management)
- [x] **JSON incremental tokenization interface ready** ✅ (foundation for editor integration)
- [ ] Remaining languages performance validation
- [ ] Cross-language incremental parsing working

### Developer Experience
- [x] **Clear, consistent JSON API** ✅ (established patterns for all languages)
- [x] **Comprehensive JSON documentation** ✅ (650+ lines including examples)
- [x] **JSON demonstrates easy language addition** ✅ (clear template for remaining languages)
- [x] **JSON provides helpful error messages** ✅ (detailed diagnostics with spans)
- [ ] Consistent API across all languages
- [ ] Documentation for all languages
- [ ] Language addition guide and examples

## 🚦 Risk Mitigation

### Technical Risks
1. **Parser Complexity**: Start with simpler languages (JSON, CSS)
2. **Performance**: Profile early and often
3. **Memory Usage**: Use arena allocators, pool resources
4. **Grammar Conflicts**: Test extensively with real-world code

### Schedule Risks
1. **Scope Creep**: Focus on core features first
2. **Integration Issues**: Test continuously
3. **Performance Regression**: Automated benchmarks

## 📝 Design Decisions

### Why Unified Architecture?
- **Consistency**: Same patterns across all languages
- **Maintainability**: Single place for language logic
- **Performance**: Shared infrastructure optimizations
- **Extensibility**: Easy to add new languages

### Why Stratified Parser?
- **Performance**: Three-layer optimization
- **Flexibility**: Can skip layers when not needed
- **Incremental**: Efficient updates
- **Fact-based IR**: Language-agnostic representation

### Why Grammar System?
- **Declarative**: Easier to understand and modify
- **Reusable**: Share patterns across languages
- **Testable**: Grammar rules can be tested in isolation
- **Extensible**: Add new constructs easily

## ✅ Definition of Done

### Phase 2 Complete: JSON Reference Implementation ✅
- [x] **JSON language module complete** ✅ (production-ready with 4,473 lines)
- [x] **JSON format command integration** ✅ (seamlessly works with `zz format`)
- [x] **JSON tests passing 100%** ✅ (comprehensive test suite)
- [x] **JSON performance targets met** ✅ (all targets exceeded)
- [x] **JSON documentation complete** ✅ (README + inline docs)
- [x] **JSON no memory leaks** ✅ (validated memory management)
- [x] **JSON examples for all use cases** ✅ (API reference with examples)
- [x] **JSON migration from stub complete** ✅ (full LanguageSupport implementation)

### Overall Project (Phase 3+ Remaining)
- [x] **1/7 languages have complete modules** ✅ (JSON complete)
- [ ] Format command uses new architecture for all languages
- [ ] All tests passing (>99.5%) for all languages
- [ ] Performance targets met for all languages
- [ ] Documentation complete for all languages
- [ ] No memory leaks in any language
- [ ] Examples for each use case across all languages
- [ ] Migration from old structure complete for all languages

---

*This document supersedes TODO_PARSER.md for language-specific implementation planning*
*Focus: Unified architecture leveraging Pure Zig Stratified Parser for all language support*
*Priority: Performance first, clean architecture, wide use case support*