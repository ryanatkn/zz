# zz - CLI Utilities

Fast command-line utilities written in Zig for POSIX systems. Currently features high-performance filesystem tree visualization and LLM prompt generation.

Performance is a top priority, and we dont care about backwards compat -
always try to get to the final best code. 

## Platform Support

- **Supported:** Linux, macOS, BSD, and other POSIX-compliant systems
- **Not Supported:** Windows (no plans for Windows support)
- All tests and features assume POSIX environment

## Environment

```bash
$ zig version
0.14.1
```

No external dependencies - pure Zig implementation.

## Project Structure

```bash
./zig-out/bin/zz tree
```

```
└── .
    ├── .claude [...]                  # Claude Code configuration directory
    ├── .git [...]                     # Git repository metadata  
    ├── .zig-cache [...]               # Zig build cache (filtered from tree output)
    ├── docs                           # Documentation
    │   └── glob-patterns.md           # Glob pattern documentation
    ├── src                            # Source code (modular architecture)
    │   ├── cli                        # CLI interface module (command parsing & execution)
    │   │   ├── args.zig               # Argument parsing utilities
    │   │   ├── command.zig            # Command enumeration and string parsing
    │   │   ├── help.zig               # Usage documentation and help text
    │   │   ├── main.zig               # CLI entry point and argument processing
    │   │   └── runner.zig             # Command dispatch and orchestration
    │   ├── config                     # Configuration system (modular ZON parsing & pattern resolution)
    │   │   ├── resolver.zig           # Pattern resolution with defaults and custom patterns
    │   │   ├── shared.zig             # Core types and SharedConfig structure
    │   │   └── zon.zig                # ZON file loading with filesystem abstraction
    │   ├── filesystem                 # Filesystem abstraction layer (parameterized for testing)
    │   │   ├── interface.zig          # Abstract filesystem interfaces (FilesystemInterface, DirHandle, FileHandle)
    │   │   ├── mock.zig               # Mock filesystem implementation for testing
    │   │   └── real.zig               # Real filesystem implementation for production
    │   ├── lib                        # Shared utilities and infrastructure (POSIX-optimized with performance focus)
    │   │   ├── benchmark.zig          # Performance measurement and validation utilities
    │   │   ├── filesystem.zig         # Consolidated filesystem error handling patterns
    │   │   ├── path.zig               # Optimized POSIX-only path utilities (20-30% faster than fmt.allocPrint)
    │   │   ├── pools.zig              # Specialized memory pools for ArrayList and string reuse
    │   │   ├── string_pool.zig        # Production-ready string interning with stdlib HashMapUnmanaged
    │   │   └── traversal.zig          # Unified directory traversal with filesystem abstraction
    │   ├── patterns                   # Pattern matching engine (high-performance unified system)
    │   │   ├── gitignore.zig          # Gitignore-specific pattern logic with filesystem abstraction
    │   │   ├── glob.zig               # Complete glob pattern matching implementation
    │   │   └── matcher.zig            # Unified pattern matcher with optimized fast/slow paths
    │   ├── prompt                     # Prompt generation module (LLM-optimized file aggregation)
    │   │   ├── test [...]             # Comprehensive test suite
    │   │   ├── builder.zig            # Core prompt building with filesystem abstraction
    │   │   ├── config.zig             # Prompt-specific configuration
    │   │   ├── fence.zig              # Smart fence detection for code blocks
    │   │   ├── glob.zig               # Glob pattern expansion with filesystem abstraction
    │   │   ├── main.zig               # Prompt command entry point
    │   │   └── test.zig               # Test runner for prompt module
    │   ├── benchmark                  # Performance benchmarking module
    │   │   └── main.zig               # Benchmark command entry point
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
    │   ├── main.zig                   # Minimal application entry point
    │   └── test.zig                   # Main test runner for entire project
    ├── zig-out [...]                  # Build output directory (auto-generated)
    ├── .gitignore                     # Git ignore patterns
    ├── CLAUDE.md                      # AI assistant development documentation
    ├── README.md                      # User-facing documentation and usage guide
    ├── REFACTORING_CONFIG.md          # Configuration system refactoring documentation
    ├── build.zig                      # Zig build system configuration
    ├── build.zig.zon                  # Package manifest
    └── zz.zon                         # CLI configuration (tree filtering patterns)
```

## Installation

See [README.md](README.md#installation) for installation instructions.

## Commands

```bash
# Build commands (default is Debug mode)
$ zig build                      # Debug build (default)
$ zig build -Doptimize=ReleaseFast  # Fast release build
$ zig build -Doptimize=ReleaseSafe  # Safe release (with runtime checks)
$ zig build -Doptimize=ReleaseSmall # Smallest binary size
$ zig build --use-llvm           # Use LLVM backend

# Development workflow
$ zig build run -- tree [args]          # Run tree command in development
$ zig build run -- prompt [args]        # Run prompt command in development
$ zig build run -- benchmark [args]     # Run benchmarks
```

## Testing

```bash
$ zig build test              # Run all tests (recommended)
$ zig build test-tree         # Run tree module tests only
$ zig build test-prompt       # Run prompt module tests only
$ zig test src/test.zig --test-filter "directory"    # Run specific tests by name pattern
```

Comprehensive test suite covers configuration parsing, directory filtering, performance optimization, edge cases, and security patterns.

## Benchmarking

Performance benchmarking is critical for maintaining and improving the efficiency of zz. The benchmark module provides detailed performance metrics for all optimization areas.

```bash
# Run all benchmarks with default iterations (10,000)
$ zig build benchmark

# Run with custom iterations for more accurate results
$ zig build run -- benchmark --iterations=50000

# Verbose mode shows performance tips and detailed metrics
$ zig build run -- benchmark --verbose

# Run specific benchmarks
$ zig build run -- benchmark --path               # Path joining operations
$ zig build run -- benchmark --string-pool        # String interning efficiency
$ zig build run -- benchmark --memory-pools       # Memory pool allocations
$ zig build run -- benchmark --glob               # Glob pattern matching

# Benchmark in release mode for realistic performance metrics
$ zig build -Doptimize=ReleaseFast
$ ./zig-out/bin/zz benchmark --iterations=100000

# Save benchmark results to markdown
$ zig build benchmark-save                        # Save to benchmarks/latest.md
$ zig build benchmark-baseline                    # Save as benchmarks/baseline.md
$ zig build benchmark-compare                     # Compare with baseline (exits 1 on regression)

# Manual benchmark file operations
$ zz benchmark --output=benchmarks/latest.md
$ zz benchmark --output=benchmarks/latest.md --compare=benchmarks/baseline.md
$ zz benchmark --save-baseline --output=benchmarks/baseline.md
```

**Benchmark Output:**
- Results saved as markdown tables in `benchmarks/` directory
- Tracked in git for performance history
- Automatic comparison with baseline showing percentage changes
- Regression detection with configurable thresholds (default: 10%)

**Performance Baselines (Debug build, 10k iterations):**
- Path operations: ~50μs per operation (20-30% faster than stdlib)
- String pooling: 99%+ cache efficiency on repeated paths
- Memory pools: ~50μs per allocation/release cycle
- Glob patterns: 75% fast-path hit ratio for common patterns

**When to Run Benchmarks:**
- Before and after implementing optimizations
- When modifying core infrastructure (`src/lib/`)
- To verify performance improvements are maintained
- During development of new features that impact performance
- In CI/CD to catch performance regressions

## Module Structure

**Core Architecture:**
- **CLI Module:** `src/cli/` - Command parsing, validation, and dispatch system
- **Tree Module:** `src/tree/` - High-performance directory traversal with configurable filtering and multiple output formats
- **Prompt Module:** `src/prompt/` - LLM prompt generation with glob support, smart fencing, and deduplication
- **Lib Module:** `src/lib/` - Shared utilities and infrastructure for all commands

**Key Components:**
- **Shared Configuration:** Root-level `zz.zon` with cross-cutting concerns (ignore patterns, hidden files, symlink behavior)
- **Performance Optimizations:** Early directory skip, memory management, efficient traversal, arena allocators
- **Modular Design:** Clean interfaces with shared utilities and consolidated implementations
- **POSIX-Only Utilities:** Custom path operations optimized for POSIX systems (leaner than std.fs.path)

**Shared Infrastructure (`src/lib/`):**
- **`path.zig`** - POSIX-only path utilities with optimized direct buffer manipulation (20-30% faster than fmt.allocPrint)
- **`traversal.zig`** - Unified directory traversal with filesystem abstraction support
- **`filesystem.zig`** - Consolidated error handling patterns for filesystem operations
- **`string_pool.zig`** - Production-ready string interning with stdlib-optimized HashMapUnmanaged for better cache locality
- **`pools.zig`** - Specialized memory pools for ArrayList reuse and path string optimization
- **`benchmark.zig`** - Performance measurement utilities for validation and regression detection

**Adding New Commands:**
1. Add to `Command` enum in `src/cli/command.zig`
2. Update parsing and help text
3. Add handler in `src/cli/runner.zig`  
4. Complex features get dedicated module with `run(allocator, args)` interface
5. Use shared utilities from `src/lib/` for common operations

## Filesystem Abstraction Layer

**Architecture:**
- **`src/filesystem/`** - Complete filesystem abstraction with parameterized dependencies for testing
  - `interface.zig` - Abstract interfaces: `FilesystemInterface`, `DirHandle`, `FileHandle`, `DirIterator`
  - `real.zig` - Production implementation using actual filesystem operations
  - `mock.zig` - Test implementation with in-memory filesystem simulation
- **Parameterized Dependencies:** All modules accept `FilesystemInterface` parameter for testability
- **Zero Performance Impact:** Interfaces use vtables with static dispatch where possible

**Usage Example:**
```zig
// Production code uses real filesystem
const filesystem = RealFilesystem.init();
const walker = Walker.initWithOptions(allocator, config, .{ .filesystem = filesystem });

// Tests use mock filesystem
var mock_fs = MockFilesystem.init(allocator);
defer mock_fs.deinit();
try mock_fs.addDirectory("src");
try mock_fs.addFile("src/main.zig", "const std = @import(\"std\");");
const walker = Walker.initWithOptions(allocator, config, .{ .filesystem = mock_fs.interface() });
```

**Benefits:**
- Complete test isolation without real I/O
- Deterministic testing with controlled filesystem state
- Ability to test error conditions (permission denied, disk full, etc.)
- No test artifacts in working directory

## Configuration System

**Modular Configuration Architecture:**
- **Root-level config** in `zz.zon` - Single source of truth for cross-cutting concerns
- **`src/config/`** - Modular configuration system with clean separation of concerns:
  - `shared.zig` - Core types and SharedConfig structure  
  - `zon.zig` - ZON file loading with integrated configuration resolution
  - `resolver.zig` - Pattern resolution with defaults and custom patterns
- **`src/patterns/`** - High-performance unified pattern matching engine:
  - `matcher.zig` - Optimized pattern matching with fast/slow paths (90/10 split)
  - `gitignore.zig` - Stateless gitignore pattern logic
- **`src/config.zig`** - Clean public API facade for backward compatibility
- **Both tree and prompt modules** use the same underlying configuration system

**Configuration Format:**
```zon
.{
    // Base patterns behavior: "extend" (defaults + user) or provide custom array
    .base_patterns = "extend",
    
    // Additional patterns to ignore (added to defaults when base_patterns = "extend")
    .ignored_patterns = .{
        "logs",
        "custom_dir",
    },
    
    // Files to completely hide (not displayed at all)
    .hidden_files = .{
        "custom.hidden",
    },
    
    // Symlink behavior: "skip" (default), "follow", or "show"
    .symlink_behavior = "skip",
    
    // Gitignore support: true (default) respects .gitignore files, false disables
    .respect_gitignore = true,
    
    // Command-specific overrides (optional)
    .tree = .{
        // Tree-specific settings go here if needed in future
    },
    
    .prompt = .{
        // Prompt-specific settings go here if needed in future
    },
}
```

**Pattern Resolution:**
- **"extend" mode:** Combines built-in defaults with your custom patterns
- **Custom array mode:** Use only your specified patterns, no defaults
- **Safe matching:** Exact path component matching prevents leaky substring matches
- **Default ignored patterns:** `.git`, `node_modules`, `.zig-cache`, `zig-out`, build directories, etc.
- **Default hidden files:** `.DS_Store`, `Thumbs.db`
- **Gitignore integration:** Automatically reads and applies `.gitignore` patterns by default
  - Files matching gitignore patterns are completely hidden (like `git ls-files` behavior)  
  - Directories matching gitignore patterns show as `[...]`
  - Use `--no-gitignore` flag to disable gitignore filtering

**Cross-module DRY Helpers:**
- `shouldIgnorePath()` - Shared ignore logic for both tree and prompt
- `shouldHideFile()` - Shared file hiding logic  
- `handleSymlink()` - Shared symlink behavior

## Prompt Module Features

**Glob Pattern Support with Performance Optimizations:**
- Basic wildcards: `*.zig`, `test?.zig`
- Recursive patterns: `src/**/*.zig`
- **Optimized alternatives:** `*.{zig,md,txt}` with fast-path expansion
- **Fast-path common patterns:** `*.{zig,c,h}`, `*.{js,ts}`, `*.{md,txt}` pre-optimized (40-60% faster)
- Nested braces: `*.{zig,{md,txt}}` expands to `*.zig`, `*.md`, `*.txt`
- Character classes: `log[0-9].txt`, `file[a-zA-Z].txt`, `test[!0-9].txt`
- Escape sequences: `file\*.txt` matches literal `file*.txt`
- Hidden files: `.*` explicitly matches hidden files (`*` does not)
- Symlinks: Symlinks to files are followed
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
- **Optimized path operations** - Direct buffer manipulation eliminates expensive fmt.allocPrint calls
- **String interning with PathCache** - 15-25% memory reduction for deep directory traversals
- **Fast-path glob patterns** - Pre-optimized expansion for common patterns like `*.{zig,c,h}` (40-60% speedup)
- **Memory pool allocators** - Specialized pools for ArrayList and path string reuse
- **Stdlib-optimized containers** - HashMapUnmanaged for better cache locality and reduced overhead
- Efficient memory management with arena allocators
- Smart filtering with .gitignore-style patterns

**Configuration:**
- Load from `zz.zon` for persistent settings
- Command-line arguments override config
- Sensible defaults for common use cases

## Notes to LLMs

- We want idiomatic Zig, taking more after C than C++
- Do not support backwards compatibility unless explicitly asked
- Never deprecate or preserve backwards compatibility unless explicitly requested
- Never re-export in modules unless explicitly justified with a comment or requested
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
- Always update docs at ./CLAUDE.md and ./README.md
- Always include tests for new functionality and newly handled edge cases
    (and please don't cheat on tests lol,
    identify root causes and leave `// TODO` if you're stumped)
- Less is more - avoid over-engineering, and when in doubt, ask me or choose the simple option

**Current Status:** ✓ **Production ready with aggressive performance optimizations and stdlib integrations** - All 190 tests passing (100% success rate). Full feature set with significant performance improvements:

**✅ Performance Optimizations Completed:**
- **20-30% faster path operations** - Direct buffer manipulation in joinPath
- **15-25% memory reduction** - String interning with PathCache integration  
- **40-60% glob speedup** - Fast-path optimization for common patterns
- **Reduced allocation overhead** - Memory pools for ArrayList and string reuse
- **Better cache locality** - Stdlib HashMapUnmanaged integration
- **Performance benchmarking** - Measurement infrastructure for validation

**Architecture:** Complete filesystem abstraction with parameterized dependencies, explicit ignore detection, proper exit codes, comprehensive pattern matching, Unix-like hidden file behavior, and aggressive code consolidation eliminating 300+ lines of duplication.

## Test Coverage

The project has comprehensive test coverage including:
- **Edge cases**: Empty inputs, special characters, Unicode, long filenames
- **Security**: Path traversal, permission handling
- **Performance**: Large files, deep recursion, memory stress tests
- **Integration**: End-to-end command testing, format combinations
- **Glob patterns**: Wildcards, braces, recursive patterns, hidden files
- **Pattern matching**: Unified pattern engine with performance-critical optimizations
- **Filesystem abstraction**: Mock filesystem testing for complete test isolation
- **Parameterized dependencies**: All modules testable with mock filesystems

See `REFACTORING_CONFIG.md` for detailed refactoring documentation.