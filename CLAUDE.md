# zz - CLI Utilities

Fast command-line utilities written in Zig for POSIX systems. Currently features high-performance filesystem tree visualization and LLM prompt generation.

Performance is a top priority, and we dont care about backwards compat -
always try to get to the final best code. 

## Platform Support

- **Supported:** Linux, macOS, BSD, and other POSIX-compliant systems
- **Not Supported:** Windows (no plans)

## Environment

```bash
$ zig version
0.14.1
```

**Vendored Dependencies:** 
- All tree-sitter libraries vendored in `deps/` for reliability
- Update with `./scripts/update-deps.sh` (data-driven, declarative)
- See `deps/README.md` for vendoring strategy and rationale

## Project Structure

```bash
./zig-out/bin/zz tree
```

```
└── .
    ├── .claude [...]                  # Claude Code configuration directory
    ├── .git [...]                     # Git repository metadata  
    ├── .zig-cache [...]               # Zig build cache (filtered from tree output)
    ├── benchmarks                     # Benchmark results storage
    │   ├── README.md                  # Benchmark documentation
    │   ├── baseline.md                # Performance baseline for comparison
    │   └── latest.md                  # Most recent benchmark results
    ├── deps                           # Vendored dependencies
    │   ├── tree-sitter                # Core tree-sitter library (v0.25.0)
    │   ├── zig-tree-sitter            # Zig bindings for tree-sitter
    │   ├── tree-sitter-zig            # Zig language grammar
    │   └── zig-spec                   # Zig language specification reference
    ├── docs                           # Documentation
    │   ├── archive [...]              # Archived task documentation (ignored in tree output)
    │   └── glob-patterns.md           # Glob pattern documentation
    ├── src                            # Source code (modular architecture)
    │   ├── benchmark                  # Performance benchmarking module
    │   │   └── main.zig               # Benchmark command entry point
    │   ├── cli                        # CLI interface module (command parsing & execution)
    │   │   ├── test [...]             # CLI tests
    │   │   ├── command.zig            # Command enumeration and string parsing
    │   │   ├── help.zig               # Usage documentation and help text
    │   │   ├── main.zig               # CLI entry point and argument processing
    │   │   ├── runner.zig             # Command dispatch and orchestration
    │   │   └── test.zig               # Test runner for CLI module
    │   ├── config                     # Configuration system (modular ZON parsing & pattern resolution)
    │   │   ├── resolver.zig           # Pattern resolution with defaults and custom patterns
    │   │   ├── shared.zig             # Core types and SharedConfig structure
    │   │   └── zon.zig                # ZON file loading with filesystem abstraction
    │   ├── lib                        # Core infrastructure and utilities (Phase 5 consolidated architecture)
    │   │   ├── analysis               # Code analysis and caching infrastructure
    │   │   │   ├── cache.zig          # AST cache system with LRU eviction
    │   │   │   ├── code.zig           # Code analysis patterns and utilities
    │   │   │   ├── incremental.zig    # Incremental processing with dependency tracking
    │   │   │   └── semantic.zig       # Semantic analysis and code understanding
    │   │   ├── core                   # Core utilities and data structures
    │   │   │   ├── collections.zig    # Memory-managed collections with RAII cleanup
    │   │   │   ├── errors.zig         # Centralized error handling patterns
    │   │   │   ├── filesystem.zig     # Filesystem operation facades
    │   │   │   ├── io.zig             # I/O utilities and file operations
    │   │   │   ├── ownership.zig      # Memory ownership patterns
    │   │   │   ├── path.zig           # POSIX-optimized path operations
    │   │   │   └── traversal.zig      # Unified directory traversal
    │   │   ├── extractors             # Language-specific code extractors
    │   │   │   ├── css.zig            # CSS AST extraction
    │   │   │   ├── html.zig           # HTML AST extraction
    │   │   │   ├── json.zig           # JSON AST extraction
    │   │   │   ├── svelte.zig         # Svelte multi-section extraction
    │   │   │   ├── typescript.zig     # TypeScript AST extraction
    │   │   │   └── zig.zig            # Zig AST extraction
    │   │   ├── filesystem             # Filesystem abstraction layer
    │   │   │   ├── interface.zig      # Abstract interfaces (FilesystemInterface, DirHandle)
    │   │   │   ├── mock.zig           # Mock implementation for testing
    │   │   │   └── real.zig           # Real filesystem for production
    │   │   ├── formatters             # Language-specific formatters
    │   │   │   ├── css.zig            # CSS formatting
    │   │   │   ├── html.zig           # HTML formatting
    │   │   │   ├── json.zig           # JSON formatting with smart indentation
    │   │   │   ├── svelte.zig         # Svelte formatting
    │   │   │   ├── typescript.zig     # TypeScript formatting
    │   │   │   └── zig.zig            # Zig formatting integration
    │   │   ├── language               # Language detection and management
    │   │   │   ├── detection.zig      # File extension to language mapping
    │   │   │   ├── extractor.zig      # Unified extraction interface
    │   │   │   ├── flags.zig          # Extraction flags and options
    │   │   │   └── tree_sitter.zig    # Tree-sitter integration layer
    │   │   ├── memory                 # Memory management utilities
    │   │   │   ├── pools.zig          # ArrayList and memory pool reuse
    │   │   │   ├── scoped.zig         # Scoped allocation patterns
    │   │   │   └── zon.zig            # ZON-specific memory management
    │   │   ├── parsers                # Language parsers with AST support
    │   │   │   ├── css.zig            # CSS parser
    │   │   │   ├── html.zig           # HTML parser
    │   │   │   ├── json.zig           # JSON parser
    │   │   │   ├── svelte.zig         # Svelte parser
    │   │   │   ├── typescript.zig     # TypeScript parser
    │   │   │   └── zig.zig            # Zig parser
    │   │   ├── parsing                # Parsing infrastructure
    │   │   │   ├── ast.zig            # AST node definitions
    │   │   │   ├── ast_formatter.zig  # AST-based formatting
    │   │   │   ├── cached_formatter.zig # Formatter with caching
    │   │   │   ├── formatter.zig      # Core formatting infrastructure
    │   │   │   ├── gitignore.zig      # Gitignore pattern support
    │   │   │   ├── glob.zig           # Glob pattern implementation
    │   │   │   ├── imports.zig        # Import statement extraction
    │   │   │   ├── matcher.zig        # Pattern matching engine
    │   │   │   └── zon_parser.zig     # ZON configuration parsing
    │   │   ├── test                   # Test infrastructure
    │   │   │   ├── fixtures [...]     # Test fixtures for each language
    │   │   │   ├── fixture_loader.zig # Test fixture loading
    │   │   │   ├── fixture_runner.zig # Test fixture execution
    │   │   │   └── helpers.zig        # Test utilities and contexts
    │   │   ├── text                   # Text processing utilities
    │   │   │   ├── builders.zig       # String building utilities
    │   │   │   ├── line_processing.zig # Line-based text processing
    │   │   │   └── patterns.zig       # Text pattern recognition
    │   │   ├── args.zig               # Argument parsing utilities
    │   │   ├── benchmark.zig          # Performance measurement framework
    │   │   ├── c.zig                  # C language bindings
    │   │   ├── config.zig             # Configuration management
    │   │   ├── extractor_base.zig     # Base extractor implementation
    │   │   ├── node_types.zig         # AST node type definitions
    │   │   └── parallel.zig           # Parallel processing utilities
    │   ├── prompt                     # Prompt generation module (LLM-optimized file aggregation)
    │   │   ├── test [...]             # Comprehensive test suite
    │   │   ├── builder.zig            # Core prompt building with filesystem abstraction
    │   │   ├── config.zig             # Prompt-specific configuration
    │   │   ├── fence.zig              # Smart fence detection for code blocks
    │   │   ├── glob.zig               # Glob pattern expansion with filesystem abstraction
    │   │   ├── main.zig               # Prompt command entry point
    │   │   └── test.zig               # Test runner for prompt module
    │   ├── tree                       # Tree visualization module (high-performance directory traversal)
    │   │   ├── test [...]             # Comprehensive test suite
    │   │   ├── CLAUDE.md              # Detailed tree module documentation
    │   │   ├── config.zig             # Tree-specific configuration
    │   │   ├── entry.zig              # File/directory data structures
    │   │   ├── filter.zig             # Pattern matching and ignore logic
    │   │   ├── format.zig             # Output format enumeration (tree, list)
    │   │   ├── formatter.zig          # Multi-format output rendering
    │   │   ├── main.zig               # Tree command entry point
    │   │   ├── path_builder.zig       # Path utilities with filesystem abstraction
    │   │   ├── test.zig               # Test runner for tree functionality
    │   │   └── walker.zig             # Core traversal with filesystem abstraction
    │   ├── config.zig                 # Public API facade for configuration system
    │   ├── filesystem.zig             # Filesystem abstraction API entry point
    │   ├── main.zig                   # Minimal application entry point
    │   └── test.zig                   # Main test runner for entire project
    ├── zig-out [...]                  # Build output directory (auto-generated)
    ├── CLAUDE.md                      # AI assistant development documentation
    ├── README.md                      # User-facing documentation and usage guide
    ├── build.zig                      # Zig build system configuration
    ├── build.zig.zon                  # Package manifest
    └── zz.zon                         # CLI configuration (tree filtering patterns)
```

## Installation

See [README.md](README.md#installation) for installation instructions.

## Commands

```bash
# Build commands (default is Debug mode)
$ zig build                         # Debug build (default)
$ zig build -Doptimize=ReleaseFast  # ReleaseFast | ReleaseSafeFast | ReleaseSmall
$ zig build --use-llvm              # Use LLVM backend

# Development workflow
$ zig build run -- tree [args]          # Run tree command in development
$ zig build run -- prompt [args]        # Run prompt command in development
$ zig build run -- benchmark [args]     # Run benchmarks
$ zig build run -- format [args]        # Run formatter in development
$ zig build run -- demo [args]          # Run demo in development
$ zig build run -- deps [args]          # Run dependency management

# Dependency management commands
$ zz deps --list                    # Show dependency status table
$ zz deps --check                   # Check if updates needed (CI-friendly)
$ zz deps --update                  # Update all dependencies (TODO: git operations)
$ zz deps --dry-run                 # Preview what would be updated
$ zz deps --force                   # Force update all dependencies
$ zz deps --force-dep tree-sitter   # Force update specific dependency
$ zig build deps-list               # Same as zz deps --list via build system
$ zig build deps-check              # Same as zz deps --check via build system

# Help commands
$ zz -h                          # Brief help overview
$ zz --help                      # Detailed help with all options
$ zz help                        # Same as --help
```

## Testing

Run all tests with `zig build test` or filter with `-Dtest-filter="pattern"`. Tests use mock filesystem for isolation.

For comprehensive testing guide, see [docs/testing.md](docs/testing.md).

## Benchmarking

Performance benchmarking follows Unix philosophy: CLI outputs to stdout, users control file management. Multiple formats (markdown, json, csv, pretty), baseline comparison, regression detection.

```bash
$ zz benchmark --format=pretty     # Color terminal output
$ zig build benchmark               # Save to latest.md, compare baseline
```

For detailed benchmarking guide, see [docs/benchmarking.md](docs/benchmarking.md).

## Module Structure

Modular architecture with clean separation: CLI (`src/cli/`), Tree (`src/tree/`), Prompt (`src/prompt/`), Format (`src/format/`), Demo (`src/demo.zig`), Benchmark (`src/benchmark/`), Config (`src/config/`), Deps (`src/lib/deps/` and `src/deps/`), and shared infrastructure in `src/lib/`.

For detailed module architecture, see [docs/module-architecture.md](docs/module-architecture.md).

## Dependency Management System

Pure Zig replacement for shell-based dependency management (`scripts/update-deps.sh`). Provides type-safe, performant vendored dependency management.

**Key Features:**
- **Status checking:** List all 9 dependencies with colored status output
- **Memory safe:** RAII patterns and proper ownership tracking
- **Lock files:** PID-based locks prevent concurrent updates
- **Version tracking:** Semantic version comparison with `.version` files
- **Atomic operations:** Backup and rollback for safe updates
- **CI-friendly:** Exit code 1 when updates needed for automation
- **Filesystem abstraction:** MockFilesystem enables deterministic testing
- **Configuration:** `deps.zon` file with all dependencies (currently hardcoded fallback)

**Architecture:**

```
src/lib/deps/              # Core dependency management library
├── config.zig            # DepsZonConfig, Dependency, VersionInfo structures
├── manager.zig           # DependencyManager orchestration logic
├── versioning.zig        # Semantic version parsing using core/version.zig
├── operations.zig        # Atomic operations using core/io.zig
├── lock.zig              # POSIX-portable lock management
├── git.zig               # Git wrapper (clone, hash, cleanup)
├── utils.zig             # Utilities using core/path.zig
└── test.zig              # MockFilesystem integration tests

src/deps/
└── main.zig              # CLI entry point and argument parsing

deps.zon                  # Dependency configuration (9 dependencies)
```

**Integration with Core Libraries:**
- `core/io.zig` - All file operations (readFile, writeFile, deleteTree)
- `core/path.zig` - Path manipulation (joinPath, basename)
- `core/version.zig` - Semantic version parsing (extracted primitive)
- `terminal/colors.zig` - Colored terminal output
- `filesystem/interface.zig` - Filesystem abstraction for testing
- `memory/zon.zig` - Safe ZON parsing with managed memory

**Testing & Quality:**
- 15+ unit tests across all modules
- MockFilesystem enables deterministic CI/CD testing
- Zero direct filesystem calls - all through core/io.zig
- POSIX portable - uses std.c.getpid() not Linux-specific calls
- Memory safe - proper cleanup with RAII patterns
- Graceful degradation - fallback to hardcoded config on parse errors

**Current Status:**
- ✅ All 9 dependencies recognized and tracked
- ✅ Status checking and reporting working
- ✅ Memory management without leaks
- ✅ CI-friendly exit codes
- 🚧 Git operations (clone/update) not yet connected
- 🚧 ZON parsing uses hardcoded fallback (dynamic parsing TODO)

**Usage Examples:**
```bash
# Check dependency status
$ zz deps --list
╔══════════════════════════════════════════════════════╗
║                   Dependencies                        ║
╠════════════════╦═════════════╦═══════════════════════╣
║ tree-sitter    ║ v0.25.0     ║ Up to date            ║
║ tree-sitter-zig║ main        ║ Needs update          ║
╚════════════════╩═════════════╩═══════════════════════╝

# CI integration
$ zz deps --check || echo "Updates needed!"

# Preview changes
$ zz deps --dry-run
```

**Documentation:**
See [docs/deps.md](docs/deps.md) for comprehensive usage guide, architecture details, and migration instructions from shell scripts.

## Filesystem Abstraction Layer

Complete filesystem abstraction enables deterministic testing without real I/O. Mock and real implementations with zero performance impact.

For implementation details, see [docs/filesystem-abstraction.md](docs/filesystem-abstraction.md).

## Configuration System

Modular ZON-based configuration with pattern matching, gitignore support, and command-specific overrides. Root `zz.zon` provides single source of truth.

For configuration format and options, see [docs/configuration.md](docs/configuration.md).

## Language Support

Complete AST integration for Zig, CSS, HTML, JSON, TypeScript (.ts), and Svelte. Real tree-sitter parsing with extraction flags.

For language features and extraction capabilities, see [docs/language-support.md](docs/language-support.md).

## AST Integration Framework

Unified NodeVisitor pattern for all language parsers. Incremental processing with smart AST cache invalidation and dependency tracking.

For AST architecture and cache details, see [docs/ast-integration.md](docs/ast-integration.md).

## Prompt Module Features

**AST-Based Code Extraction (Production Ready):**
- **Real tree-sitter AST parsing** for all supported languages (not text matching!)
- **Extraction flags** with precise AST node traversal:
  - `--signatures`: Function/method signatures via AST
  - `--types`: Type definitions (structs, enums, unions) via AST
  - `--docs`: Documentation comments via AST nodes
  - `--imports`: Import statements (text-based currently)
  - `--errors`: Error handling patterns (text-based currently)
  - `--tests`: Test blocks via AST
  - `--full`: Complete source (default for backward compatibility)
- **Composable extraction:** Combine flags like `--signatures --types`
- **Language detection:** Automatic based on file extension
- **Graceful fallback:** Falls back to text extraction for unsupported languages
- **Extensible:** Architecture ready for future language grammars

**Glob Pattern Support:**
- Basic wildcards: `*.zig`, `test?.zig`
- Recursive patterns: `src/**/*.zig`
- Brace expansion: `*.{zig,md,txt}`
- Common patterns optimized: `*.{zig,c,h}`, `*.{js,ts}`, `*.{md,txt}`
- Character classes: `log[0-9].txt`, `file[a-zA-Z].txt`, `test[!0-9].txt`
- Automatic deduplication of matched files

**Directory Support:**
- Direct directory arguments: `zz prompt src/` recursively processes all files
- Respects ignore patterns during directory traversal
- Skips hidden directories and common ignore patterns (node_modules, .git, etc.)
- Performance-optimized with early directory skipping
- Integrates seamlessly with glob patterns and explicit files

**Smart Code Fencing:**
- Automatically detects appropriate fence length
- Handles nested code blocks correctly
- Preserves syntax highlighting

**Output Format:**
- Markdown with semantic XML tags for LLM context
- File paths in structured `<File path="...">` tags
- Configurable ignore patterns via `zz.zon`

**Error Handling:**
- No default pattern: errors if no files specified (no auto `*.zig`)
- Strict by default: errors on missing files or empty globs
- Explicit file ignore detection: errors when explicitly requested files are ignored
- `--allow-empty-glob`: Warnings for non-matching glob patterns
- `--allow-missing`: Warnings for all missing files
- Text-only mode: `--prepend` or `--append` without files is valid
- Clear error messages distinguish between glob patterns (silent ignore) and explicit files (error)

## Tree Module Features

**Output Formats:**
- **Tree Format:** Traditional tree visualization with Unicode box characters
- **List Format:** Flat list with `./` path prefixes for easy parsing

**Performance Optimizations:**
- Early directory skip for ignored paths
- Direct buffer manipulation for path operations
- String interning to reduce memory usage
- Fast-path optimization for common glob patterns
- Memory pool allocators for reuse
- Efficient memory management with arena allocators
- Smart filtering with .gitignore-style patterns

**Configuration:**
- Load from `zz.zon` for persistent settings
- Command-line arguments override config
- Sensible defaults for common use cases

## Format Module Features

**Language-Aware Formatting:**
- **JSON:** Smart indentation, line-breaking decisions, optional trailing commas, key sorting
- **CSS:** Selector formatting, property alignment, media query indentation
- **HTML:** Tag indentation, attribute formatting, whitespace preservation
- **Zig:** Integration with external `zig fmt` tool
- **TypeScript/Svelte:** Basic support (placeholders for future enhancement)

**Flexible Options:**
- `--write`: Format files in-place
- `--check`: Check if files are formatted (exit 1 if not)
- `--stdin`: Read from stdin, write to stdout
- `--indent-size=N`: Configurable indentation (default: 4)
- `--indent-style=space|tab`: Choose indentation style
- `--line-width=N`: Maximum line width (default: 100)

**Implementation Details:**
- **Core Infrastructure:** `src/lib/formatter.zig` - Language dispatch and utilities
- **Language Formatters:** `src/lib/formatters/` - Per-language implementations
- **CLI Integration:** `src/format/main.zig` - Command handling and file processing
- **Glob Support:** Uses same GlobExpander as prompt module
- **Memory Management:** LineBuilder utility for efficient string building

**Usage Examples:**
```bash
zz format config.json                    # Output formatted JSON to stdout
zz format config.json --write            # Format file in-place
zz format "src/**/*.json" --check        # Check if files are formatted
echo '{"a":1}' | zz format --stdin       # Format from stdin
zz format "*.css" --indent-size=2        # Custom indentation
```

## Claude Code Configuration

The project is configured for optimal Claude Code usage:

**Tool Preferences (`.claude/config.json`):**
- `rg:*` - Prefer ripgrep (`rg`) over `grep`/`find`/`cat`
- `zz:*` - Full access to project CLI for testing and development and feature usage

**Best Practices:**
- Always use `rg` for text search instead of `grep` or `find`
- Use `zig build test` for testing and `zig build benchmark` for benchmarking
- Use `zz` commands for exploring code with semantic extraction (`zz prompt`, `zz tree`, etc.)
- Leverage Claude Code's native Grep tool which uses ripgrep internally

## Development Workflow

Manage vendored dependencies with `./scripts/update-deps.sh`. Use TODO_*.md workflow for major tasks. Test with `zig build test`.

For comprehensive workflow guide, see [docs/development-workflow.md](docs/development-workflow.md).

## Related Documentation

Core documentation is organized in `docs/archive/` for additional reference:

- [docs/archive/ARCHITECTURE.md](docs/archive/ARCHITECTURE.md) - System design and module relationships
- [docs/archive/PERFORMANCE.md](docs/archive/PERFORMANCE.md) - Optimization guide and benchmarks
- [docs/archive/PATTERNS.md](docs/archive/PATTERNS.md) - Pattern matching implementation details
- [docs/archive/TESTING.md](docs/archive/TESTING.md) - Testing strategy and coverage
- [docs/archive/TROUBLESHOOTING.md](docs/archive/TROUBLESHOOTING.md) - Common issues and solutions

**Note:** The `docs/archive/` directory is excluded from `zz tree` output via `zz.zon` configuration to keep tree views clean.

## Notes for Contributors

When selecting tasks:
1. Start with high impact, low effort items
2. Ensure backward compatibility
3. Add tests for all new features
4. Update documentation immediately
5. Benchmark performance impacts
6. Consider POSIX compatibility
7. Keep the Unix philosophy in mind

## Notes to LLMs from the user

- We want idiomatic Zig, taking more after C than C++
- Do not support backwards compatibility unless explicitly asked
- Never deprecate or preserve legacy code unless explicitly requested, default to deleting old code aggressively
- Never re-export in modules unless explicitly justified with a comment or requested (do not ever use the facade pattern, it's a code smell to us)
- Focus on performance and clean architecture
- This is a CLI utilities project - no graphics or game functionality
- Do not re-export identifiers from modules
- Test frequently with `zig build run` to ensure each step works
- Add and extend benchmarks when appropriate
- Performance is top priority - optimize for speed
- Address duplicated code and antipatterns
- Push back against the developer when you think you are correct
    or have understanding they don't, and when in doubt, ask clarifying questions
- Keep modules self-contained and focused on their specific purpose
- We have `rg` (ripgrep) installed, so always prefer `rg` over `grep` and `find`
- Never use `sed` or write Bash loops to edit files, prefer direct editing instead
- Claude Code is configured to prefer `rg` via `.claude/config.json` allowedCommands
- Always update docs at ./CLAUDE.md and ./README.md
- Always include tests for new functionality and newly handled edge cases
    (and please don't cheat on tests lol,
    identify root causes and leave `// TODO` if you're stumped)
- Remember: Performance is a feature, every cycle counts.
- Leave `// TODO terse explanation` when you encounter unknowns and work that cannot be completed in the current pass
- Less is more - avoid over-engineering, and when in doubt, ask me or choose the simple option

NOTE TO THE MACHINE: see ./WORKFLOW.md for dev sessions