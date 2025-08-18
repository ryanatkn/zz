# zz - Language Tooling Library & CLI

Fast command-line utilities and **reusable language tooling library** written in pure Zig for POSIX systems. Features native AST parsing, code formatting, and semantic analysis without external dependencies.

**Performance is the top priority** - we don't care about backwards compat, always aim for the final best code.

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

**Architecture:** Pure Zig Stratified Parser - tree-sitter removal complete. Three-layer system (Lexical, Structural, Detailed) with fact-based intermediate representation.

## Project Structure (After Major Refactoring)

```
src/
├── cli/                 # Command parsing & execution
├── config/              # Configuration system (ZON-based)
├── lib/                 # Reusable library modules (the heart of zz)
│   ├── core/            # Fundamental utilities (NEW LOCATION)
│   │   ├── language.zig     # Language detection & enumeration
│   │   ├── extraction.zig   # Code extraction configuration
│   │   ├── path.zig         # POSIX path operations
│   │   ├── collections.zig  # Memory-efficient data structures
│   │   └── filesystem.zig   # Filesystem utilities
│   ├── patterns/        # Pattern matching utilities (NEW)
│   │   ├── glob.zig         # Glob pattern matching
│   │   └── gitignore.zig    # Gitignore pattern handling
│   ├── ast/             # Enhanced AST infrastructure (EXPANDED)
│   │   ├── mod.zig          # AST type definition
│   │   ├── node.zig         # Core Node types
│   │   ├── factory.zig      # Programmatic construction
│   │   ├── builder.zig      # Fluent DSL
│   │   ├── utils.zig        # Manipulation utilities
│   │   ├── test_helpers.zig # Test infrastructure
│   │   ├── traversal.zig    # Tree walking strategies (NEW)
│   │   ├── transformation.zig # Immutable transformations (NEW)
│   │   ├── query.zig        # CSS-like queries (NEW)
│   │   └── serialization.zig # ZON persistence (NEW)
│   ├── parser/          # Pure Zig Stratified Parser
│   │   ├── foundation/  # Foundation types (Span, Fact, Token)
│   │   ├── lexical/     # Layer 0: Streaming tokenizer
│   │   ├── structural/  # Layer 1: Boundary detection
│   │   └── detailed/    # Layer 2: Detailed parsing
│   ├── languages/       # Unified language implementations
│   │   ├── mod.zig      # Language registry and dispatch
│   │   ├── interface.zig # Language support contracts
│   │   ├── common/      # Shared utilities with real implementations
│   │   │   └── analysis.zig # NOW WITH REAL AST TRAVERSAL!
│   │   ├── json/        # JSON complete implementation
│   │   ├── zon/         # ZON complete implementation
│   │   └── [others]/    # Other language stubs
│   ├── grammar/         # Grammar definition DSL
│   ├── analysis/        # Semantic analysis & linting
│   ├── deps/            # Dependency management system
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
$ zz deps --generate-manifest       # Generate dependency manifest.json
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

### Deps - Dependency Management
```bash
$ zz deps --check                   # Check if updates needed
$ zz deps --update                  # Update dependencies
$ zz deps --force-dep tree-sitter   # Force update specific dep
$ zz deps --generate-manifest       # Generate manifest.json (smart detection)
```
See [docs/deps.md](docs/deps.md) for architecture details.

### Complete Command Reference
See [docs/commands.md](docs/commands.md) for all commands and options.

## Testing & Quality

```bash
$ zig build test                    # Run all tests
$ zig build test -Dtest-filter="pattern"  # Filter tests
$ zig build benchmark               # Run performance benchmarks
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

## Notes

### For LLMs
See [docs/llm-guidelines.md](docs/llm-guidelines.md) for complete guidelines. Key points:
- Performance is a feature
- Delete old code aggressively, no deprecation, refactor without hesitation
- Test frequently with `zig build run`
- Always update documentation
- Leave `// TODO` comments for unknowns

---

_Remember: Performance is the top priority -- every cycle and byte count
but context is everything and the big picture UX matters most._