# Module Architecture

> ⚠️ AI slop code and docs, is unstable and full of lies

## Core Architecture

- **CLI Module:** `src/cli/` - Command parsing, validation, and dispatch system
- **Tree Module:** `src/tree/` - Directory traversal with configurable filtering and multiple output formats
- **Prompt Module:** `src/prompt/` - LLM prompt generation with glob support, smart fencing, and deduplication
- **Format Module:** `src/format/` - Language-aware code formatting with configurable styles
- **Demo Module:** `src/demo.zig` - Interactive demonstration of zz capabilities with terminal output
- **Benchmark Module:** `src/benchmark/` - Performance measurement and regression detection
- **Config Module:** `src/config/` - Configuration system with ZON parsing and pattern resolution
- **Lib Module:** `src/lib/` - Consolidated infrastructure and utilities (Phase 5 reorganization)

## Key Components

- **Shared Configuration:** Root-level `zz.zon` with cross-cutting concerns (ignore patterns, hidden files, symlink behavior)
- **Performance Optimizations:** Early directory skip, memory management, efficient traversal, arena allocators
- **Modular Design:** Clean interfaces with shared utilities and consolidated implementations
- **POSIX-Only Utilities:** Custom path operations optimized for POSIX systems (leaner than std.fs.path)

## Shared Infrastructure in `src/lib/`

### Core Utilities (`src/lib/core/`)
- **`path.zig`** - POSIX-only path utilities with direct buffer manipulation
- **`traversal.zig`** - Unified directory traversal with filesystem abstraction
- **`filesystem.zig`** - Consolidated error handling patterns for filesystem operations
- **`collections.zig`** - Memory-managed collections with RAII cleanup
- **`errors.zig`** - Centralized error handling patterns
- **`io.zig`** - I/O utilities and file operations
- **`ownership.zig`** - Memory ownership patterns

### Analysis Infrastructure (`src/lib/analysis/`)
- **`cache.zig`** - AST cache system with LRU eviction
- **`incremental.zig`** - Incremental processing with dependency tracking
- **`semantic.zig`** - Semantic analysis and code understanding
- **`code.zig`** - Code analysis patterns and utilities

### Memory Management (`src/lib/memory/`)
- **`pools.zig`** - ArrayList and memory pool reuse
- **`scoped.zig`** - Scoped allocation patterns
- **`zon.zig`** - ZON-specific memory management

### Parsing Infrastructure (`src/lib/parsing/`)
- **`matcher.zig`** - Pattern matching engine with optimized fast/slow paths
- **`glob.zig`** - Glob pattern implementation
- **`gitignore.zig`** - Gitignore pattern support
- **`formatter.zig`** - Core formatting infrastructure
- **`ast_formatter.zig`** - AST-based formatting
- **`cached_formatter.zig`** - Formatter with caching support

### Language Support
- **`src/lib/language/`** - Language detection and management
  - `detection.zig` - File extension to language mapping
  - `extractor.zig` - Unified extraction interface
  - `flags.zig` - Extraction flags and options
  - `tree_sitter.zig` - Tree-sitter integration layer
- **`src/lib/extractors/`** - Language-specific code extractors
- **`src/lib/parsers/`** - Language parsers with AST support
- **`src/lib/formatters/`** - Language-specific formatters

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