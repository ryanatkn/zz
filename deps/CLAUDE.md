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

### 4. tree-sitter-css (`deps/tree-sitter-css/`)
- **What it is**: A tree-sitter grammar for parsing CSS files
- **Purpose**: Enables parsing of CSS stylesheets into AST
- **Key files**:
  - `src/parser.c` - Generated C parser for CSS language
  - `src/scanner.c` - Custom scanner for CSS-specific lexing
  - `queries/highlights.scm` - Syntax highlighting patterns
- **How we use it**: Compile as a static C library that provides `tree_sitter_css()` function
- **Note**: Supports modern CSS including variables, media queries, and complex selectors

### 5. tree-sitter-html (`deps/tree-sitter-html/`)
- **What it is**: A tree-sitter grammar for parsing HTML files
- **Purpose**: Enables parsing of HTML documents into AST
- **Key files**:
  - `src/parser.c` - Generated C parser for HTML language
  - `src/scanner.c` - Custom scanner for HTML-specific lexing
  - `src/tag.h` - HTML tag definitions
  - `queries/highlights.scm` - Syntax highlighting patterns
  - `queries/injections.scm` - Language injection patterns for embedded scripts/styles
- **How we use it**: Compile as a static C library that provides `tree_sitter_html()` function
- **Note**: Supports HTML5, custom elements, and language injections

### 6. tree-sitter-json (`deps/tree-sitter-json/`)
- **What it is**: A tree-sitter grammar for parsing JSON files
- **Purpose**: Enables parsing of JSON data into AST
- **Key files**:
  - `src/parser.c` - Generated C parser for JSON language
  - `queries/highlights.scm` - Syntax highlighting patterns
- **How we use it**: Compile as a static C library that provides `tree_sitter_json()` function
- **Note**: Strictly validates JSON syntax, supports all JSON data types

### 7. tree-sitter-svelte (`deps/tree-sitter-svelte/`)
- **What it is**: A tree-sitter grammar for parsing Svelte components
- **Purpose**: Enables parsing of Svelte single-file components into AST
- **Key files**:
  - `src/parser.c` - Generated C parser for Svelte language
  - `src/scanner.c` - Custom scanner for Svelte-specific lexing
  - `src/tag.h` - Svelte tag definitions
  - `queries/highlights.scm` - Syntax highlighting patterns
  - `queries/injections.scm` - Language injection for script/style sections
- **How we use it**: Compile as a static C library that provides `tree_sitter_svelte()` function
- **Note**: Supports Svelte's template syntax, reactive statements, and multi-section components

### 8. tree-sitter-typescript (`deps/tree-sitter-typescript/`)
- **What it is**: A tree-sitter grammar for parsing TypeScript files
- **Purpose**: Enables parsing of TypeScript code into AST
- **Key files**:
  - `src/parser.c` - Generated C parser for TypeScript language
  - `src/scanner.c` - Custom scanner for TypeScript-specific lexing
  - `grammar.js` - Grammar definition
- **How we use it**: Compile as a static C library that provides `tree_sitter_typescript()` function
- **Note**: Supports TypeScript syntax including types, interfaces, generics (no TSX/JSX support)

### 9. zig-spec (`deps/zig-spec/`)
- **What it is**: Official Zig language specification
- **Purpose**: Reference for Zig language syntax and semantics
- **Key files**:
  - `grammar/grammar.peg` - PEG grammar for Zig
  - `grammar/tests/` - Test files covering Zig language features
- **How we use it**: Documentation reference only, not compiled or linked
- **Note**: tree-sitter-zig is based on this specification

## Relationship Diagram

```
                    ┌──────────────────┐
                    │   tree-sitter    │
                    │   (C library)     │
                    └────────┬─────────┘
                             │
                    ┌────────▼─────────┐
                    │ zig-tree-sitter  │
                    │ (Zig bindings)   │
                    └────────┬─────────┘
                             │
                    ┌────────▼─────────┐
                    │   Our Zig Code   │
                    │ (lib/language/)  │
                    └────────┬─────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
        ▼                    ▼                    ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│ Language     │    │ Language     │    │ Language     │
│ Grammars:    │    │ Grammars:    │    │ Grammars:    │
├──────────────┤    ├──────────────┤    ├──────────────┤
│ • CSS        │    │ • HTML       │    │ • Svelte     │
│ • JSON       │    │ • TypeScript │    │ • Zig        │
└──────────────┘    └──────────────┘    └──────────────┘
                             
                    ┌──────────────┐
                    │   zig-spec   │
                    │ (reference)  │
                    └──────────────┘
```

Each grammar provides a `tree_sitter_{language}()` function that returns
a language parser, which our code uses to parse files of that type.

## Build Process

1. **Core Libraries**:
   - **tree-sitter**: Compiled as static C library (core parsing engine)
   - **zig-tree-sitter**: Used as Zig module (imported, not compiled separately)

2. **Language Grammars** (all compiled as static C libraries):
   - **tree-sitter-css**: Provides `tree_sitter_css()` extern function
   - **tree-sitter-html**: Provides `tree_sitter_html()` extern function  
   - **tree-sitter-json**: Provides `tree_sitter_json()` extern function
   - **tree-sitter-svelte**: Provides `tree_sitter_svelte()` extern function
   - **tree-sitter-typescript**: Provides `tree_sitter_typescript()` extern function
   - **tree-sitter-zig**: Provides `tree_sitter_zig()` extern function

3. **Our Code Integration**:
   - Imports zig-tree-sitter as "tree-sitter" module
   - Links all C libraries (tree-sitter core + all language grammars)
   - Dynamically selects appropriate `tree_sitter_{language}()` based on file extension
   - Uses unified AST visitor pattern for all languages

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