# Dependency Overview

This document explains the purpose and relationship of each vendored dependency in the `deps/` directory.

## Dependencies

### 1. tree-sitter (`deps/tree-sitter/`)
- **What it is**: The core tree-sitter parsing library written in C
- **Purpose**: Provides the foundational parsing engine for language-aware code analysis
- **Key files**:
  - `lib/src/lib.c` - Core parser implementation
  - `lib/include/tree_sitter/api.h` - C API headers
- **How we use it**: Compile as a static C library and link to our Zig code

### 2. zig-tree-sitter (`deps/zig-tree-sitter/`)
- **What it is**: Official Zig bindings to the tree-sitter C library
- **Purpose**: Provides idiomatic Zig interfaces to tree-sitter's C API
- **Key files**:
  - `src/root.zig` - Main Zig module with Parser, Tree, Node, Query types
  - `src/*.zig` - Individual Zig wrappers for tree-sitter types
- **How we use it**: Import as a Zig module named "tree-sitter"
- **Note**: This is NOT a grammar, it's the Zig language bindings to tree-sitter

### 3. tree-sitter-zig (`deps/tree-sitter-zig/`)
- **What it is**: A tree-sitter grammar for parsing Zig source code
- **Purpose**: Enables parsing of Zig language files into AST
- **Key files**:
  - `src/parser.c` - Generated C parser for Zig language
  - `src/tree_sitter/parser.h` - Parser header
  - `queries/*.scm` - Tree-sitter query patterns for syntax highlighting
  - `grammar.js` - Grammar definition (source, not used at runtime)
- **How we use it**: Compile as a static C library that provides `tree_sitter_zig()` function
- **Note**: This is a GRAMMAR (language definition), not bindings

### 4. zig-spec (`deps/zig-spec/`)
- **What it is**: Official Zig language specification
- **Purpose**: Reference for Zig language syntax and semantics
- **Key files**:
  - `grammar/spec.md` - Zig language specification
- **How we use it**: Documentation reference only, not compiled or linked
- **Note**: tree-sitter-zig is based on this specification

## Relationship Diagram

```
┌─────────────────┐     ┌──────────────────────┐
│  tree-sitter    │────▶│  zig-tree-sitter     │
│  (C library)    │     │  (Zig bindings)      │
└─────────────────┘     └──────────────────────┘
        │                         │
        │                         ▼
        │               ┌──────────────────────┐
        │               │   Our Zig Code       │
        │               │   (parser.zig)       │
        │               └──────────────────────┘
        │                         │
        ▼                         ▼
┌─────────────────┐     Uses both at runtime
│ tree-sitter-zig │     to parse Zig files
│ (Zig grammar)   │
└─────────────────┘

┌─────────────────┐
│    zig-spec     │ ← Reference for grammar
│ (documentation) │
└─────────────────┘
```

## Build Process

1. **tree-sitter**: Compiled as static C library
2. **tree-sitter-zig**: Compiled as static C library (provides `tree_sitter_zig()` extern function)
3. **zig-tree-sitter**: Used as Zig module (imported, not compiled separately)
4. **Our code**: 
   - Imports zig-tree-sitter as "tree-sitter" module
   - Links both C libraries
   - Calls `tree_sitter_zig()` to get the language parser

## Common Confusion Points

- **zig-tree-sitter** is NOT a grammar - it's Zig bindings to tree-sitter
- **tree-sitter-zig** is NOT Zig bindings - it's a grammar for parsing Zig code
- The naming is confusing but follows tree-sitter conventions:
  - `{language}-tree-sitter` = language bindings TO tree-sitter
  - `tree-sitter-{language}` = tree-sitter grammar FOR that language

## Why We Vendor These

- **Reliability**: No network dependencies at build time
- **Reproducibility**: Exact versions locked
- **Compatibility**: We know these versions work together (ABI v15)
- **Simplicity**: No complex package management needed