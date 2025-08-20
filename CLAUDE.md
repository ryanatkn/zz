# zz - Language Tooling Library & CLI

Fast command-line utilities and **reusable language tooling library** written in pure Zig for POSIX systems. Features native AST parsing, code formatting, and semantic analysis without external dependencies.

Performance is a top priority, and this is a greenfield project so we dont care about backwards compat -- always search for the final best code.

## Major Architecture Decision: Pure Zig Grammar System

We are replacing tree-sitter with a **Pure Zig grammar and parser system**. This transforms zz from a CLI tool into a comprehensive language tooling library with reusable modules for building parsers, formatters, linters, and more.

**Key Benefits:**
- **No FFI overhead** - Pure Zig throughout
- **Complete control** - We own the entire stack
- **Library-first design** - Every component is reusable
- **Better performance** - Compile-time optimizations, zero allocations
- **Easier debugging** - Single language, no C boundaries

See [TODO_PURE_ZIG_ROADMAP.md](TODO_PURE_ZIG_ROADMAP.md) for implementation details.

## Platform Support

- **Supported:** Linux, macOS, BSD, and other POSIX-compliant systems
- **Not Supported:** Windows (no plans)

## Environment

```bash
$ zig version
0.14.1
```

**Architecture:** Pure Zig Stratified Parser with **Rule ID System** - tree-sitter removal complete. Three-layer system (Lexical, Structural, Detailed) with efficient 16-bit rule identification.

### 🔬 Stratified Parser Architecture
**Fact-based intermediate representation** with three-layer parsing for <10ms editor operations:
- **Layer 0 (Lexical)**: StreamingLexer with <0.1ms viewport tokenization
- **Layer 1 (Structural)**: Boundary detection with <1ms full file analysis  
- **Layer 2 (Detailed)**: Viewport-aware parsing with LRU caching
- **Fact System**: Immutable facts with multi-index storage (by_id, by_span, by_predicate)
- **Performance**: 16-bit rule IDs, zero-allocation core ops, 2MB memory per 1000-line file

See [docs/stratified-parser-architecture.md](docs/stratified-parser-architecture.md) for complete details.

### 🚀 Recent Major Achievement: Rule ID Migration **COMPLETE** (August 2025)
**Successfully completed comprehensive architectural overhaul** replacing all string-based rule names with 16-bit rule IDs:
- **10-100x performance improvement** for rule lookups via switch statements  
- **~90% memory reduction** (2 bytes vs 16+ bytes per rule)
- **50+ modules fully migrated** to rule ID system across entire codebase
- **Zero-allocation parsing** for core operations
- **Type-safe rule handling** with compile-time validation
- **Anti-patterns eliminated** - No string comparisons in performance-critical code
- **Memory leaks fixed** in grammar builder with proper cleanup

This fundamental improvement eliminates performance bottlenecks and provides a clean foundation for multi-language scaling. **All 73+ rule_name references have been eliminated** from the codebase.

## Project Structure (After Major Refactoring)

```
src/
├── cli/                 # Command parsing & execution
├── config/              # Configuration system (ZON-based)
├── lib/                 # Reusable library modules (the heart of zz)
│   ├── char/            # Character utilities (single source of truth)
│   │   ├── predicates.zig   # Character classification (isDigit, isAlpha, etc.)
│   │   ├── consumers.zig    # Text consumption (skipWhitespace, consumeString, etc.)
│   │   └── mod.zig          # Module exports
│   ├── core/            # Fundamental utilities
│   │   ├── language.zig     # Language detection & enumeration
│   │   ├── extraction.zig   # Code extraction configuration
│   │   ├── path.zig         # POSIX path operations
│   │   └── collections.zig  # Memory-efficient data structures
│   ├── patterns/        # Pattern matching utilities
│   │   ├── glob.zig         # Glob pattern matching
│   │   └── gitignore.zig    # Gitignore pattern handling
│   ├── text/            # Text processing utilities  
│   │   ├── delimiters.zig   # Delimiter tracking and balanced parsing
│   │   ├── processing.zig   # Line processing and text utilities
│   │   ├── builders.zig     # StringBuilder utilities
│   │   ├── formatting.zig   # Format utilities (ANSI stripping, etc.)
│   │   └── line_processing.zig # Line-based operations
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
│   ├── languages/       # Language implementations
│   │   ├── mod.zig      # Language registry and dispatch
│   │   ├── interface.zig # Language support contracts
│   │   ├── common/      # Shared utilities
│   │   │   ├── analysis.zig # AST analysis utilities
│   │   │   ├── tokens.zig   # Common token types
│   │   │   └── formatting.zig # Format builders
│   │   ├── json/        # JSON complete implementation
│   │   ├── zon/         # ZON complete implementation
│   │   ├── typescript/  # TypeScript with patterns.zig
│   │   ├── zig/         # Zig with patterns.zig
│   │   ├── css/         # CSS with patterns.zig
│   │   ├── html/        # HTML with patterns.zig
│   │   └── svelte/      # Svelte stub
│   ├── grammar/         # Grammar definition DSL
│   ├── memory/          # Memory management utilities
│   ├── filesystem/      # Filesystem abstraction layer
│   └── test/            # Test framework & fixtures
├── prompt/              # LLM prompt generation (uses lib/ast)
├── tree/                # Directory visualization
├── format/              # CLI formatting commands (uses lib/formatting)
├── benchmark/           # Performance benchmarking
└── deps/                # Dependency management CLI
```

For detailed architecture, see [docs/module-architecture.md](docs/module-architecture.md).

## Quick Start

```bash
# Install (User)
$ git clone https://github.com/user/zz
$ cd zz
$ zig build install-user             # Install to ~/.zz/bin/
$ export PATH="$PATH:$HOME/.zz/bin"  # Add to PATH

# Install (System-wide, alternative)
$ zig build -Doptimize=ReleaseFast
$ sudo cp zig-out/bin/zz /usr/local/bin/

# Basic usage
$ zz tree                           # Show directory tree
$ zz prompt "src/**/*.zig"          # Generate LLM prompt
$ zz format config.json --write     # Format file in-place
$ zz deps --list                    # Check dependency status
$ zz benchmark --format pretty      # Run performance benchmarks
```

## Commands Overview

### Tree - Directory Visualization
```bash
$ zz tree --format=list             # List format for parsing
$ zz tree --hidden                  # Include hidden files
$ zz tree --max-depth=3             # Limit depth
```
See [docs/tree-features.md](docs/tree-features.md) for details.

### Prompt - LLM Code Extraction
```bash
$ zz prompt --signatures "*.zig"    # Extract function signatures
$ zz prompt --types --docs "*.ts"   # Extract types and docs
$ zz prompt src/                    # Process entire directory
```
See [docs/prompt-features.md](docs/prompt-features.md) for AST extraction features.

### Format - Code Formatting
```bash
$ zz format "**/*.json" --write     # Format all JSON files
$ zz format "src/**/*.ts" --check   # Check formatting (CI)
$ echo '{"a":1}' | zz format --stdin # Format from stdin
```
See [docs/format-features.md](docs/format-features.md) for language support.

### Benchmark - Performance Testing
```bash
$ zz benchmark --format pretty      # Terminal output with confidence symbols
$ zz benchmark --only path,memory   # Run specific suites
$ zz benchmark --duration 500ms     # Custom duration (default: 200ms)
```
See [docs/benchmarking.md](docs/benchmarking.md) for details.

### Deps - Dependency Management
```bash
$ zz deps --check                   # Check if updates needed
$ zz deps --update                  # Update dependencies
$ zz deps --generate-manifest       # Generate manifest.json (smart detection)
```
See [docs/deps.md](docs/deps.md) for architecture details.

### Complete Command Reference
See [docs/commands.md](docs/commands.md) for all commands and options.

## Testing & Quality

```bash
$ zig build test                    # Run all tests
$ zig build test -Dtest-filter="pattern"  # Filter tests
$ zig build test --summary all      # Show detailed test summary (useful for debugging)
$ zig build benchmark               # Run benchmarks with statistical confidence
$ zig build benchmark-baseline      # Save current performance as baseline
$ zig build benchmark-stdout        # Show pretty benchmark output
```

- Tests use mock filesystem for isolation
- See [docs/testing.md](docs/testing.md) for testing guide
- See [docs/benchmarking.md](docs/benchmarking.md) for performance testing

## Key Features

### Unified Language Support
- **7 Languages:** Zig, TypeScript, CSS, HTML, JSON, ZON, Svelte
- **Pure Zig Stratified Parser:** Three-layer architecture (lexical, structural, detailed)
- **Unified Interface:** All languages implement common LanguageSupport contract
- **Shared Infrastructure:** Common utilities for tokens, patterns, formatting, analysis
- **Performance Optimized:** Registry caching, shared patterns, <10ms parsing targets
- **Extensible:** Easy to add new languages via interface implementation
- See [TODO_PARSER_NEXT.md](TODO_PARSER_NEXT.md) for implementation details

### Transform Pipeline Architecture (Planned)
- **Bidirectional Transforms:** Encode ↔ Decode operations with symmetry
- **Pipeline Composition:** Chain transforms like Unix pipes
- **AST Preservation:** Format-aware operations beyond std library
- **Encoding Primitives:** Language-specific escaping, smart indentation
- See [TODO_SERIALIZATION.md](TODO_SERIALIZATION.md) for architecture details

### Performance Optimizations
- Early directory skipping for ignored paths
- Memory pool allocators and arena allocation
- String interning for reduced memory usage
- AST caching with LRU eviction
- Parallel processing where beneficial

### Configuration
- ZON-based configuration (`zz.zon`)
- Gitignore-style pattern support
- Command-specific overrides
- See [docs/configuration.md](docs/configuration.md)

## Development

### Build Options
```bash
$ zig build                         # Debug build
$ zig build -Doptimize=ReleaseFast  # Production build
$ zig build run -- tree             # Development workflow
```

### Tool Preferences
- Always use `rg` (ripgrep) over `grep`/`find`
- Claude Code configured to prefer `rg`
- See `.claude/config.json` for tool configuration

### Contributing Guidelines
1. **Performance first** - optimize for speed
2. **No backwards compatibility** - delete old code aggressively
3. **Test thoroughly** - include edge cases
4. **Document changes** - update CLAUDE.md and README.md
5. **Follow Zig idioms** - more C than C++, no re-exports

See [docs/llm-guidelines.md](docs/llm-guidelines.md) for detailed development philosophy.

## Documentation

### Core Documentation
- [README.md](README.md) - User-facing documentation
- [docs/commands.md](docs/commands.md) - Complete command reference
- [docs/module-architecture.md](docs/module-architecture.md) - System design

### Stratified Parser Documentation
- [docs/stratified-parser-architecture.md](docs/stratified-parser-architecture.md) - Current implementation overview
- [docs/stratified-parser-primitives.md](docs/stratified-parser-primitives.md) - Core types (Fact, Span, Predicate)
- [docs/stratified-parser-roadmap.md](docs/stratified-parser-roadmap.md) - Implementation status and roadmap
- [docs/stratified-parser-performance.md](docs/stratified-parser-performance.md) - Performance analysis and optimizations

### Feature Documentation
- [docs/prompt-features.md](docs/prompt-features.md) - Prompt module details
- [docs/tree-features.md](docs/tree-features.md) - Tree module details
- [docs/format-features.md](docs/format-features.md) - Format module details
- [docs/language-support.md](docs/language-support.md) - Language implementations

### Development Documentation
- [docs/llm-guidelines.md](docs/llm-guidelines.md) - LLM development guidelines
- [docs/development-workflow.md](docs/development-workflow.md) - Development process
- [docs/filesystem-abstraction.md](docs/filesystem-abstraction.md) - FS abstraction

### Implementation Details
- [docs/deps.md](docs/deps.md) - Dependency management system
- [docs/ast-integration.md](docs/ast-integration.md) - AST framework
- [docs/benchmarking.md](docs/benchmarking.md) - Performance testing
- [docs/testing.md](docs/testing.md) - Testing strategy
- [TODO_PARSER_NEXT.md](TODO_PARSER_NEXT.md) - Language implementation roadmap
- [TODO_SERIALIZATION.md](TODO_SERIALIZATION.md) - Transform pipeline architecture

## Notes

_Remember: Performance is the top priority -- every cycle and byte count
but context is everything and the big picture UX matters most._

### For LLMs
See [docs/llm-guidelines.md](docs/llm-guidelines.md) for complete guidelines. Key points:
- Performance is a feature
- Delete old code aggressively, no deprecation, refactor without hesitation
- Test frequently with `zig build run`
- Always update documentation, be concise but thorough 
- We prioritize maintainable code and want to give users max power
- Leave `// TODO` comments for unknowns
