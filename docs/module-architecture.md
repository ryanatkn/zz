# Module Architecture

> ⚠️ AI slop code and docs, is unstable and full of lies

## Architecture Evolution

We're transitioning from tree-sitter to a **Pure Zig grammar system**, transforming zz into a comprehensive language tooling library. See [TODO_PURE_ZIG_ROADMAP.md](../TODO_PURE_ZIG_ROADMAP.md) for details.

## Core Architecture

### CLI Modules (Application Layer)
- **CLI Module:** `src/cli/` - Command parsing, validation, and dispatch system
- **Tree Module:** `src/tree/` - Directory traversal with configurable filtering and multiple output formats
- **Prompt Module:** `src/prompt/` - LLM prompt generation using lib/ast
- **Format Module:** `src/format/` - CLI formatting commands using lib/formatting
- **Demo Module:** `src/demo.zig` - Interactive demonstration of zz capabilities
- **Benchmark Module:** `src/benchmark/` - Performance measurement and regression detection
- **Config Module:** `src/config/` - Configuration system with ZON parsing
- **Deps Module:** `src/deps/` - Dependency management CLI

### Library Modules (Reusable Infrastructure)
- **Lib Module:** `src/lib/` - **The heart of zz** - Reusable language tooling library

## Key Components

- **Shared Configuration:** Root-level `zz.zon` with cross-cutting concerns (ignore patterns, hidden files, symlink behavior)
- **Performance Optimizations:** Early directory skip, memory management, efficient traversal, arena allocators
- **Modular Design:** Clean interfaces with shared utilities and consolidated implementations
- **POSIX-Only Utilities:** Custom path operations optimized for POSIX systems (leaner than std.fs.path)

## Shared Infrastructure in `src/lib/`

### 🆕 Grammar System (`src/lib/grammar/`)
- **`grammar.zig`** - Grammar definition DSL for defining language syntax
- **`rule.zig`** - Rule types and combinators (seq, choice, repeat, etc.)
- **`builder.zig`** - Fluent API for building grammars
- **`precedence.zig`** - Operator precedence and associativity
- **`validation.zig`** - Grammar validation and conflict detection

### 🆕 Parser Infrastructure (`src/lib/parser/`)
- **`parser.zig`** - Parser interface and base types
- **`generator.zig`** - Generate parsers from grammar definitions
- **`engine.zig`** - Core parsing algorithms (Packrat with memoization)
- **`incremental.zig`** - Incremental parsing for editor integration
- **`recovery.zig`** - Error recovery strategies

### 🆕 AST Infrastructure (`src/lib/ast/`)
- **`node.zig`** - Base AST node types with embedded metadata
- **`visitor.zig`** - Visitor pattern for AST traversal
- **`walker.zig`** - Tree walking utilities
- **`builder.zig`** - AST construction helpers
- **`metadata.zig`** - Semantic information layer
- **`trivia.zig`** - Comment and whitespace preservation

### 🆕 Transformation (`src/lib/transform/`)
- **`transformer.zig`** - AST transformation framework
- **`rewriter.zig`** - Code rewriting utilities
- **`generator.zig`** - Code generation from AST
- **`optimizer.zig`** - AST optimization passes

### 🆕 Formatting Engine (`src/lib/formatting/`)
- **`formatter.zig`** - Format model and engine
- **`rules.zig`** - Formatting rules and configuration
- **`context.zig`** - Formatting context tracking
- **`renderer.zig`** - Render formatted AST to text

### Language Implementations (`src/lib/languages/`)
Each language gets its own subdirectory with:
- **`grammar.zig`** - Language grammar definition
- **`ast.zig`** - Language-specific AST nodes
- **`formatter.zig`** - AST-based formatter
- **`analyzer.zig`** - Semantic analysis
- **`linter.zig`** - Language-specific lint rules

Current languages: zig, typescript, css, html, json, svelte

### Core Utilities (`src/lib/core/`)
- **`path.zig`** - POSIX-only path utilities with direct buffer manipulation
- **`traversal.zig`** - Unified directory traversal with filesystem abstraction
- **`filesystem.zig`** - Consolidated error handling patterns for filesystem operations
- **`collections.zig`** - Memory-managed collections with RAII cleanup
- **`errors.zig`** - Centralized error handling patterns
- **`io.zig`** - I/O utilities and file operations
- **`ownership.zig`** - Memory ownership patterns
- **`cache.zig`** - Caching infrastructure for ASTs and results

### Analysis Infrastructure (`src/lib/analysis/`)
- **`semantic.zig`** - Semantic analysis framework
- **`linter.zig`** - Linting rule engine
- **`complexity.zig`** - Code complexity metrics
- **`dependencies.zig`** - Dependency analysis
- **`symbols.zig`** - Symbol table management

### Legacy Infrastructure (`src/lib/parsing/`) - TO BE REMOVED
- **`matcher.zig`** - Pattern matching engine
- **`glob.zig`** - Glob pattern implementation
- **`gitignore.zig`** - Gitignore pattern support
- **`tree_sitter.zig`** - Tree-sitter FFI (removing)

Complete AST support for CSS, HTML, JSON, TypeScript, Svelte, and Zig with:
- Unified extraction interface with walkNode() implementations
- Language-specific formatters with smart indentation
- Tree-sitter integration layer

### Test Infrastructure (`src/lib/test/`)
- **`helpers.zig`** - Test utilities and contexts (consolidated from test_helpers.zig)
- **`fixture_loader.zig`** - Test fixture loading
- **`fixture_runner.zig`** - Test fixture execution
- Language-specific test fixtures

## Adding New Commands

1. Add to `Command` enum in `src/cli/command.zig`
2. Update parsing and help text in `src/cli/help.zig`
3. Add handler in `src/cli/runner.zig`  
4. Complex features get dedicated module with `run(allocator, args)` interface
5. Use shared utilities from `src/lib/` for common operations

## Module Features

### Demo Module
- **Interactive Mode:** Full terminal experience with colors, animations, and user interaction
- **Non-interactive Mode:** Clean text output suitable for documentation and CI
- **File Output:** `--output=<file>` flag to write demo content to files
- **Terminal Integration:** Uses `src/lib/terminal.zig` for consistent terminal handling
- **Language Showcase:** Demonstrates AST extraction across TypeScript, CSS, HTML, JSON, and Svelte
- **Enhanced Animation:** Benchmark progress uses subtle pulse effect with bold styling for better visibility

### Tree Module
- **Output Formats:** Traditional tree visualization and flat list format
- **Performance:** Early directory skip, string interning, memory pools
- **Configuration:** Load from `zz.zon`, command-line override
- **Smart Filtering:** .gitignore-style patterns with fast-path optimization

### Prompt Module
- **AST-Based Extraction:** Real tree-sitter parsing for all languages
- **Glob Support:** Wildcards, recursive patterns, brace expansion
- **Directory Processing:** Recursive with ignore patterns
- **Smart Fencing:** Automatic fence length detection
- **Error Handling:** Strict by default with configurable flexibility

### Format Module
- **Language-Aware:** JSON, CSS, HTML, Zig, TypeScript, Svelte
- **Flexible Options:** In-place, check mode, stdin/stdout
- **Configurable:** Indent size/style, line width
- **Glob Support:** Same expander as prompt module

## Design Principles

1. **Modularity:** Each command is self-contained with clear interfaces
2. **Performance:** Optimized data structures and algorithms throughout
3. **Testability:** Filesystem abstraction enables comprehensive testing
4. **Reusability:** Shared infrastructure reduces duplication
5. **Simplicity:** Lean, focused modules following Unix philosophy