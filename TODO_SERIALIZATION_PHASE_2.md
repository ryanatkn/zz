# TODO_SERIALIZATION_PHASE_2 - Integration & Migration

**Created**: 2025-08-18  
**Status**: Planning  
**Duration**: 2 weeks estimated  
**Goal**: Integrate transform pipeline with existing language implementations

## 📊 Phase 1 Accomplishments

### What We Built
- ✅ **Transform Infrastructure** - Clean, working Transform/Context/Pipeline system
- ✅ **Text Utilities** - Indentation, escaping, and quote management extracted
- ✅ **SimplePipeline** - Pragmatic same-type transform composition
- ✅ **Memory Safety** - Context-based allocation with arena support

### Key Learnings
- SimplePipeline covers 80% of use cases without type erasure complexity
- Interface pattern (like ILexer) works better than function pointer capture in Zig
- Existing patterns from codebase integrate smoothly
- Text module is the natural home for encoding utilities

## 🎯 Phase 2 Goals

Transform existing JSON and ZON implementations to use the pipeline architecture while:
1. **Maintaining backwards compatibility** - All existing tests must pass
2. **Preserving performance** - No regression in speed or memory
3. **Enabling new capabilities** - Format preservation, streaming, reversibility
4. **Creating reusable patterns** - Templates for other language migrations

## 📋 Implementation Plan

### Week 1: JSON Migration

#### Day 1-2: Lexer Transformation
- [ ] Create `lib/transform/stages/lexical.zig` with Token interface
- [ ] Wrap JSON lexer as Transform([]const u8, []Token)
- [ ] Implement reverse operation (tokens → text with trivia)
- [ ] Test round-trip: text → tokens → text

#### Day 3-4: Parser Transformation  
- [ ] Create `lib/transform/stages/syntactic.zig` with AST interface
- [ ] Wrap JSON parser as Transform([]Token, AST)
- [ ] Implement reverse operation (AST → tokens)
- [ ] Test round-trip: tokens → AST → tokens

#### Day 5: Pipeline Assembly
- [ ] Create JSON pipeline: text → tokens → AST
- [ ] Add formatting transform: AST → formatted text
- [ ] Test end-to-end: JSON → AST → formatted JSON
- [ ] Benchmark against current implementation

### Week 2: ZON Migration & Advanced Features

#### Day 1-2: ZON Migration
- [ ] Wrap ZON lexer as Transform
- [ ] Wrap ZON parser as Transform
- [ ] Create ZON pipeline
- [ ] Test compatibility with build.zig.zon files

#### Day 3: AST ↔ Native Conversion
- [ ] Create `lib/encoding/ast/` module
- [ ] Implement `astToNative(comptime T: type, ast: AST) !T`
- [ ] Implement `nativeToAST(value: anytype) !AST`
- [ ] Test with common Zig types

#### Day 4: Streaming Support
- [ ] Add TokenIterator for streaming lexing
- [ ] Implement incremental parsing
- [ ] Test with large JSON files (>10MB)
- [ ] Memory usage benchmarks

#### Day 5: Format Preservation
- [ ] Implement trivia preservation in lexer
- [ ] Add format-preserving AST modifications
- [ ] Test: modify JSON while preserving style
- [ ] Create demo: config file updater

## 🏗️ Architecture Evolution

### Stage Interfaces

```
┌─────────────────────────────────────────────────┐
│                 Lexical Stage                    │
├─────────────────────────────────────────────────┤
│ Transform([]const u8, []Token)                  │
│ • Tokenization with trivia preservation         │
│ • Reversible: tokens → text                     │
│ • Streaming via TokenIterator                   │
└─────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────┐
│                Syntactic Stage                   │
├─────────────────────────────────────────────────┤
│ Transform([]Token, AST)                         │
│ • Parsing with error recovery                   │
│ • Reversible: AST → tokens                      │
│ • Incremental parsing support                   │
└─────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────┐
│                Semantic Stage                    │
├─────────────────────────────────────────────────┤
│ Transform(AST, Schema)                          │
│ • Type extraction and validation                │
│ • Symbol resolution                             │
│ • Dependency analysis                           │
└─────────────────────────────────────────────────┘
```

### Migration Strategy

```zig
// Before: Direct function calls
const tokens = try lexer.tokenize(text);
const ast = try parser.parse(tokens);
const formatted = try formatter.format(ast);

// After: Pipeline composition
var pipeline = Pipeline.init(allocator);
try pipeline.add(JsonLexer.transform());
try pipeline.add(JsonParser.transform());
try pipeline.add(JsonFormatter.transform());

const formatted = try pipeline.run(text, &context);
```

## 🔍 Technical Challenges

### 1. Type Erasure for Heterogeneous Pipelines
**Challenge**: SimplePipeline only works for same-type transforms  
**Solution**: Create specialized pipelines for common patterns:
- `LexParsePipeline`: Text → Tokens → AST
- `FormatPipeline`: AST → Tokens → Text
- Use comptime known types, avoid runtime erasure

### 2. Trivia Preservation
**Challenge**: Preserving comments and whitespace through transforms  
**Solution**: 
- Attach trivia to tokens during lexing
- Maintain trivia references in AST nodes
- Reconstruct on reverse transform

### 3. Performance Maintenance
**Challenge**: Transform overhead vs direct calls  
**Solution**:
- Inline small transforms at comptime
- Use arena allocators for temporary data
- Benchmark critical paths continuously

### 4. Error Recovery
**Challenge**: Partial success in pipeline stages  
**Solution**:
- TransformResult with success/partial/failure states
- Accumulate diagnostics in Context
- Allow pipeline to continue on recoverable errors

## 🎯 Success Metrics

### Functional Requirements
- [ ] All existing JSON tests pass
- [ ] All existing ZON tests pass  
- [ ] Round-trip preservation (parse → emit → parse)
- [ ] Format preservation works
- [ ] Streaming handles 100MB+ files

### Performance Requirements
- [ ] Parsing speed within 5% of current
- [ ] Memory usage ≤ current implementation
- [ ] Pipeline overhead < 5% for simple transforms
- [ ] Streaming reduces memory by 90% for large files

### Code Quality
- [ ] Zero code duplication between JSON/ZON
- [ ] Clear separation of concerns (lex/parse/format)
- [ ] Comprehensive test coverage
- [ ] Documentation with examples

## 🚀 Phase 3 Preview

After successful JSON/ZON migration:
1. **Language Expansion**
   - Migrate TypeScript, Zig, CSS, HTML to pipeline
   - Create language-agnostic formatter
   - Build universal linter framework

2. **Advanced Features**
   - Parallel pipeline execution
   - Caching and memoization
   - Language server protocol integration
   - WASM compilation for browser use

3. **Performance Optimization**
   - SIMD tokenization
   - Lock-free pipeline execution
   - Zero-copy streaming
   - Compile-time pipeline fusion

## 📝 Implementation Notes

### Incremental Migration
1. **Start with wrappers** - Don't rewrite, wrap existing code
2. **Test continuously** - Each step must pass all tests
3. **Benchmark often** - Catch performance regressions early
4. **Document patterns** - Create templates for future migrations

### Code Organization
```
lib/
├── transform/
│   ├── stages/
│   │   ├── lexical.zig    # Token interface
│   │   ├── syntactic.zig  # AST interface
│   │   └── semantic.zig   # Schema interface
│   └── pipelines/
│       ├── lex_parse.zig  # Common Text→AST pipeline
│       └── format.zig     # Common AST→Text pipeline
├── languages/
│   ├── json/
│   │   ├── transform.zig  # JSON-specific transforms
│   │   └── pipeline.zig   # JSON pipeline assembly
│   └── zon/
│       ├── transform.zig  # ZON-specific transforms
│       └── pipeline.zig   # ZON pipeline assembly
└── encoding/
    └── ast/
        ├── to_native.zig   # AST → Zig types
        └── from_native.zig # Zig types → AST
```

### Risk Mitigation
1. **Performance regression** → Profile before/after each change
2. **Breaking changes** → Maintain compatibility layer
3. **Complexity explosion** → Keep simple things simple
4. **Memory leaks** → Test with valgrind/ASAN regularly

## 🎓 Learning Goals

By the end of Phase 2, we will have:
1. **Proven the architecture** with real implementations
2. **Established patterns** for language migration
3. **Created reusable components** for future languages
4. **Maintained performance** while adding capabilities
5. **Built foundation** for advanced features

---

*Phase 2 transforms the theoretical foundation of Phase 1 into practical, production-ready infrastructure. The focus is on proving viability through JSON/ZON migration while maintaining all existing capabilities.*