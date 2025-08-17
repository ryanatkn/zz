# Pure Zig Grammar System - Implementation Roadmap

## Vision

Transform **zz** from a CLI tool into a comprehensive **Zig library for language tooling**, providing reusable modules for building parsers, formatters, linters, language servers, and compilers.

### Core Philosophy
- **Library-first**: Every component is a reusable library module
- **Pure Zig**: No FFI, no C dependencies, idiomatic Zig throughout  
- **Performance**: Zero-allocation APIs, compile-time optimization
- **Extensibility**: Easy to add new languages and features

## ✅ Current Progress (as of 2025-08-17)

### Completed Components
- **Grammar System**: Full rule system with Terminal, Sequence, Choice, Optional, Repeat, Repeat1
- **Grammar Builder**: Fluent API with rule references (`ref("name")` syntax)
- **Validation System**: Detects undefined references and circular dependencies
- **Module Architecture**: Clean separation across 20+ files
- **Test Infrastructure**: 47+ passing tests across all modules
- **Working Examples**: Arithmetic expressions, JSON objects, nested structures

### Known Issues
- Memory leaks in nested rule allocation (needs production refinement)

## Architecture Overview

```
┌─────────────────────────────────────────────┐
│                  zz CLI                      │
└─────────────────┬───────────────────────────┘
                  │ uses
┌─────────────────▼───────────────────────────┐
│              src/lib/ (Library Modules)      │
├──────────────────────────────────────────────┤
│ ┌──────────┐ ┌──────────┐ ┌──────────────┐ │
│ │ grammar/ │ │ parser/  │ │     ast/     │ │
│ └────┬─────┘ └────┬─────┘ └──────┬───────┘ │
│      │            │               │         │
│      └────────────┼───────────────┘         │
│                   │                         │
│ ┌──────────────────▼────────────────────┐  │
│ │           languages/                  │  │
│ │  ┌─────┐ ┌──────────┐ ┌──────────┐  │  │
│ │  │ zig │ │typescript│ │   css    │  │  │
│ │  └─────┘ └──────────┘ └──────────┘  │  │
│ └────────────────────────────────────────┘  │
│                                             │
│ ┌──────────┐ ┌──────────┐ ┌──────────────┐ │
│ │transform/│ │analysis/ │ │ formatting/  │ │
│ └──────────┘ └──────────┘ └──────────────┘ │
└──────────────────────────────────────────────┘
```

## Implementation Phases

### 🎯 Phase 1: Foundation (Weeks 1-3) [IN PROGRESS]
**Goal**: Core grammar and parser infrastructure

#### Week 1: Grammar System [COMPLETED ✅]
- [x] Create `src/lib/grammar/grammar.zig` - Grammar DSL
- [x] Implement `src/lib/grammar/rule.zig` - Rule combinators (Terminal, Sequence, Choice, Optional, Repeat, Repeat1)
- [x] Add `src/lib/grammar/builder.zig` - Fluent grammar builder API with rule references
- [x] Implement validation system - Undefined reference and circular dependency detection
- [x] Create modular architecture - 20+ files for clean separation
- [ ] Design `src/lib/grammar/precedence.zig` - Operator precedence (deferred)

**Deliverable**: ✅ Working grammar definition system with 60+ tests

#### Week 2: Parser & AST [COMPLETED ✅]
- [x] Create `src/lib/parser/parser.zig` - Recursive descent parser
- [x] Implement `src/lib/parser/context.zig` - Parse context with error tracking
- [x] Add `src/lib/parser/mod.zig` - Clean parser API
- [x] Create `src/lib/ast/node.zig` - Generic AST node types
- [x] Implement `src/lib/ast/visitor.zig` - Visitor pattern
- [x] Add `src/lib/ast/walker.zig` - Tree traversal utilities
- [x] Complete grammar-to-AST pipeline

**Deliverable**: ✅ Complete parsing system with AST generation

#### Week 3: Real-World Applications
- [ ] Complete JSON parser implementation
- [ ] CLI argument parser using grammar system  
- [ ] Performance benchmarking vs existing solutions
- [ ] Error recovery and better diagnostics

**Deliverable**: Production-ready parsers for common use cases

---

### !! Phase 2: Language Implementation (Weeks 4-6)
**Goal**: Prove the system with Zig language support

#### Week 4: Zig Grammar
- [ ] Create `src/lib/languages/zig/grammar.zig` - Complete Zig grammar
- [ ] Define `src/lib/languages/zig/ast.zig` - Zig-specific AST nodes
- [ ] Implement parser generation for Zig
- [ ] Validate against zig-spec test cases

**Deliverable**: Working Zig parser passing spec tests

#### Week 5: Zig Formatter
- [ ] Port `src/lib/languages/zig/formatter.zig` to pure AST
- [ ] Remove text manipulation code
- [ ] Implement format model approach
- [ ] Validate against existing test suite

**Deliverable**: AST-based Zig formatter passing all tests

#### Week 6: Performance Validation
- [ ] Benchmark parser performance vs tree-sitter
- [ ] Memory usage profiling
- [ ] Optimization pass
- [ ] Real-world testing on large codebases

**Deliverable**: Performance report and optimizations

---

### 🔧 Phase 3: Feature Expansion (Weeks 7-9)
**Goal**: Add TypeScript and demonstrate multi-language support

#### Week 7: TypeScript Grammar
- [ ] Create `src/lib/languages/typescript/grammar.zig`
- [ ] Define `src/lib/languages/typescript/ast.zig`
- [ ] Handle TypeScript-specific constructs (types, generics)
- [ ] Test against real TypeScript codebases

**Deliverable**: Working TypeScript parser

#### Week 8: TypeScript Formatter
- [ ] Implement `src/lib/languages/typescript/formatter.zig`
- [ ] Handle JSX/TSX if applicable
- [ ] Port existing tests
- [ ] Validate formatting quality

**Deliverable**: TypeScript formatter matching current quality

#### Week 9: Additional Languages
- [ ] CSS grammar and formatter
- [ ] HTML grammar and formatter
- [ ] JSON grammar and formatter
- [ ] Basic Svelte support

**Deliverable**: Multi-language support demonstrated

---

### 📊 Phase 4: Advanced Features (Weeks 10-12)
**Goal**: Leverage pure AST for new capabilities

#### Week 10: Analysis Framework
- [ ] Implement `src/lib/analysis/linter.zig` - Linting engine
- [ ] Create `src/lib/analysis/semantic.zig` - Semantic analysis
- [ ] Add `src/lib/analysis/complexity.zig` - Metrics
- [ ] Design rule system for extensibility

**Deliverable**: Working linter with example rules

#### Week 11: Transformation Tools
- [ ] Create `src/lib/transform/rewriter.zig` - AST rewriting
- [ ] Implement `src/lib/transform/generator.zig` - Code generation
- [ ] Add refactoring capabilities
- [ ] Test with real refactoring scenarios

**Deliverable**: Code transformation capabilities

#### Week 12: Integration & Polish
- [ ] Update CLI to use new library modules
- [ ] Migrate prompt extraction to new AST
- [ ] Update tree command if needed
- [ ] Comprehensive testing

**Deliverable**: Fully integrated system

---

### 🧹 Phase 5: Cleanup (Week 13)
**Goal**: Remove old dependencies and finalize

- [ ] Delete `deps/tree-sitter*` directories
- [ ] Remove all FFI code
- [ ] Clean up `build.zig`
- [ ] Update all documentation
- [ ] Create migration guide
- [ ] Performance benchmarks

**Deliverable**: Clean, pure Zig codebase

## Success Metrics

### Performance Targets
- **Parse speed**: < 50ms for 10K LOC file
- **Memory usage**: < 5x source file size
- **Incremental parse**: < 5ms for typical edit

### Quality Targets
- **Test coverage**: 100% of existing tests pass
- **Formatter quality**: Identical or better output
- **Error recovery**: Parse 95%+ of malformed code

### Adoption Targets
- **API usability**: Clean, documented public API
- **Extensibility**: New language in < 3 days
- **Reusability**: Modules usable in other projects

## Technical Decisions

### Parser Algorithm Evolution
**Phase 1 (Current)**: Recursive Descent Parser
- **Status**: ✅ Implemented and working
- **Purpose**: Foundation for testing grammar system
- **Limitations**: Performance not suitable for real-time editing

**Phase 2 (Next)**: Stratified Parser Architecture
- **Status**: 📋 Planned (see TODO_PURE_ZIG_PLAN.md)
- **Purpose**: <1ms latency for editor interactions
- **Features**: Layered parsing, fact streams, speculative execution
- **Timeline**: 24 weeks implementation plan

**Original Plan**: Packrat Parser with Memoization
- **Status**: Superseded by Stratified Architecture
- **Rationale**: Stratified approach offers better incremental updates

### AST Representation
**Choice**: Tagged Union with Embedded Metadata
- **Why**: Type-safe, efficient, idiomatic Zig
- **Alternative**: Polymorphic nodes (not Zig-like)

### Memory Management
**Choice**: Arena Allocators per Parse
- **Why**: Fast allocation, simple cleanup
- **Alternative**: Reference counting (complex)

### Error Recovery
**Choice**: Panic Mode with Synchronization Points
- **Why**: Simple, effective, predictable
- **Alternative**: Error productions (grammar bloat)

## Risk Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| Performance regression | High | Continuous benchmarking, optimization budget |
| Grammar complexity | Medium | Start simple, iterative enhancement |
| Breaking changes | High | Comprehensive test suite, gradual migration |
| Scope creep | Medium | Strict phase boundaries, feature freeze periods |
| Memory usage | Medium | Arena allocators, lazy evaluation |

## Module Interface Examples

### Grammar Definition
```zig
const grammar = Grammar.builder()
    .rule("function", seq(.{
        opt("pub"),
        keyword("fn"),
        field("name", rule("identifier")),
        field("params", rule("parameter_list")),
        opt(field("return_type", rule("type"))),
        field("body", rule("block")),
    }))
    .precedence(.{
        .{ .left, 1, "or" },
        .{ .left, 2, "and" },
        .{ .left, 3, "equality" },
    })
    .build();
```

### Parser Usage
```zig
const parser = Parser.fromGrammar(grammar);
const ast = try parser.parse(source_code);

// Visit all functions
var visitor = FunctionVisitor{};
try ast.accept(&visitor);
```

### Formatter Usage
```zig
const formatter = ZigFormatter.init(.{
    .indent_size = 4,
    .line_width = 100,
});
const formatted = try formatter.format(ast);
```

## Timeline Summary

**Total Duration**: 13 weeks (3 months)

- **Month 1**: Foundation + Zig implementation
- **Month 2**: Multi-language support + features  
- **Month 3**: Advanced features + cleanup

**Key Milestones**:
- Week 3: Core system working
- Week 6: Zig fully ported
- Week 9: Multi-language support
- Week 12: Feature complete
- Week 13: Production ready

## Next Immediate Steps

### ✅ Completed (Phase 1)
1. **Created grammar module structure** in `src/lib/grammar/`
2. **Designed grammar DSL** with builder pattern
3. **Implemented rule combinators** (Terminal, Sequence, Choice, Optional, Repeat, Repeat1)
4. **Written comprehensive tests** (60+ passing)
5. **Documented public API** via mod.zig facades

### 📋 Next Steps (Stratified Parser)
1. **Review TODO_PURE_ZIG_PLAN.md** for detailed 24-week roadmap
2. **Begin Phase 1**: Foundation types and infrastructure
3. **Create** `src/lib/parser/foundation/` module structure
4. **Implement** Span, Fact, and specialized collections
5. **Migrate** existing modules to stratified architecture

---

*This roadmap is a living document. Updates will track progress and refine estimates based on actual implementation experience.*