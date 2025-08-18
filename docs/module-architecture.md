# Module Architecture

## Current State: Pure Zig Architecture

The zz project has successfully transitioned from tree-sitter to a **Pure Zig language tooling system** with reusable library modules and clean separation of concerns.

## Project Structure (After Major Refactoring)

```
src/
├── cli/                 # Command parsing & execution
├── config/              # Configuration system (ZON-based)
├── lib/                 # Reusable library modules (the heart of zz)
│   ├── core/            # Fundamental utilities
│   │   ├── language.zig     # Language detection & enumeration
│   │   ├── extraction.zig   # Code extraction configuration
│   │   ├── path.zig         # POSIX path operations
│   │   ├── collections.zig  # Memory-efficient data structures
│   │   └── filesystem.zig   # Filesystem utilities
│   ├── patterns/        # Pattern matching utilities
│   │   ├── glob.zig         # Glob pattern matching
│   │   └── gitignore.zig    # Gitignore pattern handling
│   ├── ast/             # Enhanced AST infrastructure
│   │   ├── mod.zig          # AST type definition
│   │   ├── node.zig         # Core Node types
│   │   ├── factory.zig      # Programmatic construction
│   │   ├── builder.zig      # Fluent DSL
│   │   ├── utils.zig        # Manipulation utilities
│   │   ├── test_helpers.zig # Test infrastructure
│   │   ├── traversal.zig    # Tree walking strategies
│   │   ├── transformation.zig # Immutable transformations
│   │   ├── query.zig        # CSS-like queries
│   │   └── serialization.zig # ZON persistence
│   ├── parser/          # Pure Zig Stratified Parser
│   │   ├── foundation/  # Foundation types (Span, Fact, Token)
│   │   ├── lexical/     # Layer 0: Streaming tokenizer
│   │   ├── structural/  # Layer 1: Boundary detection
│   │   └── detailed/    # Layer 2: Detailed parsing
│   ├── languages/       # Unified language implementations
│   │   ├── mod.zig      # Language registry and dispatch
│   │   ├── interface.zig # Language support contracts
│   │   ├── common/      # Shared utilities
│   │   ├── json/        # ✅ Complete implementation
│   │   ├── zon/         # ✅ Complete implementation
│   │   └── [others]/    # Stub implementations
│   ├── grammar/         # Grammar definition DSL
│   ├── filesystem/      # Filesystem abstraction layer
│   └── test/            # Test framework & fixtures
├── prompt/              # LLM prompt generation (uses lib/ast)
├── tree/                # Directory visualization
├── format/              # CLI formatting commands
├── benchmark/           # Performance benchmarking (currently disabled)
└── deps/                # Dependency management CLI
```

## Deleted Legacy Code

The following directories and files were removed during aggressive cleanup:

- ❌ `src/lib/language/` - Obsolete tree-sitter detection
- ❌ `src/lib/parsing/` - Duplicate implementations
- ❌ `src/lib/analysis/` - Complex tree-sitter infrastructure
  - `cache.zig` - AST caching system
  - `incremental.zig` - Incremental processing
  - `semantic.zig` - Semantic analysis
  - `code.zig` - Code analysis features
- ❌ `src/lib/benchmark.zig` - Legacy benchmark system (~300 lines)
- ❌ `src/lib/config.zig` - Duplicate configuration
- ❌ Legacy test files:
  - `fixture_loader.zig`
  - `safe_zon_fixture_loader.zig`
  - `parser_test.zig`
  - `extraction_test.zig`

## Core Architecture

### CLI Modules (Application Layer)
- **CLI Module:** `src/cli/` - Command parsing, validation, and dispatch system
- **Tree Module:** `src/tree/` - Directory traversal with configurable filtering
- **Prompt Module:** `src/prompt/` - LLM prompt generation using lib/ast
- **Format Module:** `src/format/` - Code formatting using lib/languages
- **Benchmark Module:** `src/benchmark/` - **Currently disabled** (stub implementation)
- **Config Module:** `src/config/` - Configuration system with ZON parsing
- **Deps Module:** `src/deps/` - Dependency management

### Library Modules (Reusable Infrastructure)

#### Core Utilities (`src/lib/core/`)
Essential utilities used throughout the codebase:
- **Language detection** - File extension to language mapping
- **Extraction flags** - Configuration for code extraction
- **Path operations** - POSIX-optimized path manipulation
- **Collections** - Memory-efficient data structures
- **Filesystem** - Error handling and operations

#### Pattern Matching (`src/lib/patterns/`)
High-performance pattern matching:
- **Glob patterns** - Wildcard matching with ~10ns/match
- **Gitignore** - Compatible with git ignore rules
- **ZON serialization** - Pattern persistence

#### AST Infrastructure (`src/lib/ast/`)
Centralized AST manipulation:
- **Factory pattern** - Programmatic AST construction
- **Builder DSL** - Fluent interface for building ASTs
- **Traversal** - Multiple walking strategies (DFS, BFS)
- **Transformation** - Immutable AST modifications
- **Query** - CSS selector-like AST queries
- **Serialization** - ZON-based persistence

#### Parser System (`src/lib/parser/`)
Three-layer stratified parser:
1. **Lexical** - Fast tokenization
2. **Structural** - Boundary detection
3. **Detailed** - Full AST construction

#### Language Support (`src/lib/languages/`)
Unified language implementations:
- **Registry** - Centralized language dispatch
- **Interface** - Common contracts for all languages
- **Common utilities** - Shared tokens, patterns, formatting
- **JSON** - ✅ 100% complete production implementation
- **ZON** - ✅ 100% complete production implementation
- **Others** - Stub implementations awaiting development

## Key Design Principles

### Performance First
- Early directory skipping for ignored paths
- Memory pool allocators and arena allocation
- String interning for reduced memory usage
- <10ms parsing targets for 1000 lines

### Clean Architecture
- Single source of truth (no duplicate implementations)
- Clear separation between CLI and library layers
- Shared infrastructure reduces code duplication
- Consistent patterns across all modules

### Pure Zig Implementation
- No FFI overhead (tree-sitter eliminated)
- Complete control over the entire stack
- Easier debugging (single language)
- Better compile-time optimizations

### Extensibility
- Plugin-like language modules
- Standardized interfaces
- Reusable components
- Easy to add new languages

## Current Status

### ✅ Completed
- Pure Zig parser infrastructure
- Centralized AST system
- JSON language (100% complete)
- ZON language (100% complete)
- Legacy code cleanup
- Build system streamlined

### 🚧 In Progress
- Remaining 5 language implementations
- Advanced caching features (currently stubbed)
- Benchmarking functionality (currently disabled)

### 📊 Metrics
- **Test Status**: 529/564 tests passing (93.8% success rate)
- **Memory Leaks**: Reduced by 95% (only 6 remaining)
- **Code Reduction**: ~500+ lines of legacy code removed
- **Build Health**: Clean compilation with proper error handling

## Migration Impact

### What Changed
- Import paths updated throughout codebase
- Some advanced features temporarily disabled (caching, benchmarking)
- Test count reduced due to removal of legacy tests
- Cleaner build with no tree-sitter dependencies

### What Remained
- All core functionality intact
- JSON and ZON fully operational
- CLI commands working
- Configuration system functional

### Benefits Achieved
- **Performance**: Removed tree-sitter overhead
- **Maintainability**: Single language, no C boundaries
- **Clarity**: No confusion between old/new systems
- **Extensibility**: Clear path for adding languages

## Future Roadmap

### Short Term
1. Restore benchmarking functionality
2. Re-implement caching if needed
3. Address remaining test failures

### Medium Term
1. Implement CSS language support
2. Implement HTML language support
3. Add TypeScript parser

### Long Term
1. Full Zig language support
2. Svelte multi-language handling
3. Language Server Protocol (LSP)
4. Custom language plugins

The module architecture now provides a solid foundation for building a comprehensive language tooling library in pure Zig, with excellent performance, maintainability, and extensibility.