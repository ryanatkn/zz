# Tree-Sitter to Pure Zig Transition

## Archive Notice

This directory contains documentation for the tree-sitter-based implementation of zz, which is being replaced by a Pure Zig grammar system.

**Transition Date:** 2025-08-17

## Why We're Moving Away from Tree-Sitter

### Limitations Encountered
1. **FFI Overhead**: C boundaries add complexity and performance cost
2. **Limited Control**: Can't extend tree-sitter AST with our metadata
3. **Text Manipulation**: Current hybrid AST/text approach loses context
4. **Grammar Lock-in**: Can't fix grammar bugs or add features
5. **Debugging Difficulty**: Cross-language debugging is painful

### Benefits of Pure Zig
1. **Complete Control**: We own the entire parsing stack
2. **Better Performance**: Compile-time optimizations, zero allocations
3. **Single Language**: All Zig, easier to debug and maintain
4. **Library Design**: Every component is reusable
5. **Innovation**: Can experiment with new parsing techniques

## What's Being Archived

### Dependencies
- `deps/tree-sitter/` - Core tree-sitter C library
- `deps/zig-tree-sitter/` - Zig bindings for tree-sitter
- `deps/tree-sitter-*` - Language grammar libraries

### Code
- `src/lib/parsing/tree_sitter.zig` - FFI layer
- Language extractors using tree-sitter queries
- Tree-sitter-based formatters

### Documentation
- Tree-sitter integration guides
- Grammar customization docs
- FFI patterns and examples

## Migration Path

See [TODO_PURE_ZIG_ROADMAP.md](../../TODO_PURE_ZIG_ROADMAP.md) for the implementation plan.

### Key Milestones
1. **Week 1-3**: Core grammar and parser infrastructure
2. **Week 4-6**: Zig language implementation (proof of concept)
3. **Week 7-9**: TypeScript and other languages
4. **Week 10-12**: Advanced features (linting, transformations)
5. **Week 13**: Cleanup and tree-sitter removal

## Lessons Learned

### What Worked Well
- AST-based extraction for semantic understanding
- Visitor pattern for tree traversal
- Language-specific modules with shared interface

### What Didn't Work
- Mixed text/AST processing
- Character-by-character spacing adjustments
- FFI complexity for simple operations
- Grammar limitations we couldn't fix

## Reference Implementation

The tree-sitter implementation will remain in git history as reference for:
- Test cases and expected behavior
- Language-specific parsing quirks
- Performance benchmarks to beat

## Future Vision

The Pure Zig implementation positions zz as:
- A comprehensive language tooling library
- Foundation for building parsers, formatters, linters
- Reusable modules for other Zig projects
- Innovation platform for language tools

---

*This archive preserves the tree-sitter era of zz development (2024-2025) as we transition to a pure Zig future.*