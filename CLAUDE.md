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
    ├── benchmarks                     # Benchmark results storage
    │   ├── README.md                  # Benchmark documentation
    │   ├── baseline.md                # Performance baseline for comparison
    │   └── latest.md                  # Most recent benchmark results
    ├── docs                           # Documentation
    │   ├── slop [...]                 # Generated documentation (ignored in tree output)
    │   └── glob-patterns.md           # Glob pattern documentation
    ├── src                            # Source code (modular architecture)
    │   ├── benchmark                  # Performance benchmarking module
    │   │   └── main.zig               # Benchmark command entry point
    │   ├── cli                        # CLI interface module (command parsing & execution)
    │   │   ├── test [...]             # CLI tests
    │   │   ├── args.zig               # Argument parsing utilities
    │   │   ├── command.zig            # Command enumeration and string parsing
    │   │   ├── help.zig               # Usage documentation and help text
    │   │   ├── main.zig               # CLI entry point and argument processing
    │   │   ├── runner.zig             # Command dispatch and orchestration
    │   │   └── test.zig               # Test runner for CLI module
    │   ├── config                     # Configuration system (modular ZON parsing & pattern resolution)
    │   │   ├── resolver.zig           # Pattern resolution with defaults and custom patterns
    │   │   ├── shared.zig             # Core types and SharedConfig structure
    │   │   └── zon.zig                # ZON file loading with filesystem abstraction
    │   ├── filesystem                 # Filesystem abstraction layer (parameterized for testing)
    │   │   ├── interface.zig          # Abstract filesystem interfaces (FilesystemInterface, DirHandle, FileHandle)
    │   │   ├── mock.zig               # Mock filesystem implementation for testing
    │   │   └── real.zig               # Real filesystem implementation for production
    │   ├── lib                        # Shared utilities and infrastructure (POSIX-optimized with performance focus)
    │   │   ├── benchmark.zig          # Performance measurement with markdown output
    │   │   ├── filesystem.zig         # Consolidated filesystem error handling patterns
    │   │   ├── path.zig               # Optimized POSIX-only path utilities (20-30% faster than fmt.allocPrint)
    │   │   ├── pools.zig              # Specialized memory pools for ArrayList and string reuse
    │   │   ├── string_pool.zig        # Production-ready string interning with stdlib HashMapUnmanaged
    │   │   └── traversal.zig          # Unified directory traversal with filesystem abstraction
    │   ├── patterns                   # Pattern matching engine (high-performance unified system)
    │   │   ├── test [...]             # Pattern matching tests
    │   │   ├── gitignore.zig          # Gitignore-specific pattern logic with filesystem abstraction
    │   │   ├── glob.zig               # Complete glob pattern matching implementation
    │   │   ├── matcher.zig            # Unified pattern matcher with optimized fast/slow paths
    │   │   └── test.zig               # Test runner for patterns module
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
    │   ├── filesystem.zig             # Filesystem error handling (deprecated, use lib/filesystem.zig)
    │   ├── main.zig                   # Minimal application entry point
    │   ├── test.zig                   # Main test runner for entire project
    │   └── test_helpers.zig           # Shared test utilities
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
$ zig build test              # Run all tests (shows summary)
$ zig test src/test.zig       # Run all tests (shows detailed output)
$ zig build test-tree         # Run tree module tests only
$ zig build test-prompt       # Run prompt module tests only
$ zig test src/test.zig --test-filter "directory"    # Run specific tests by name pattern
```

Comprehensive test suite covers configuration parsing, directory filtering, performance optimization, edge cases, and security patterns. The test runner provides clean output with 190+ tests and enhanced resource management patterns.

## Benchmarking

Performance benchmarking is critical for maintaining and improving the efficiency of zz. The benchmark system follows Unix philosophy: the CLI outputs to stdout, and users control file management.

### Design Philosophy
- **CLI is pure**: `zz benchmark` always outputs to stdout
- **Multiple formats**: markdown (default), json, csv, pretty
- **Build commands add convenience**: Handle file management for common workflows
- **Composable**: Works with Unix pipes and redirects

### CLI Usage (outputs to stdout)
```bash
# Default: markdown format to stdout (2 seconds per benchmark)
$ zz benchmark

# Different output formats
$ zz benchmark --format=pretty             # Color terminal output with progress bars
$ zz benchmark --format=json               # Machine-readable JSON
$ zz benchmark --format=csv                # Spreadsheet-compatible CSV

# Control timing and what runs
$ zz benchmark --duration=1s               # Run each benchmark for 1 second
$ zz benchmark --duration=500ms            # Run each benchmark for 500 milliseconds
$ zz benchmark --only=path,string          # Run specific benchmarks
$ zz benchmark --skip=glob                 # Skip specific benchmarks

# Duration control for more stable results
$ zz benchmark --duration-multiplier=2.0   # 2x longer for all benchmarks
$ zz benchmark --duration-multiplier=3.0   # 3x longer for all benchmarks

# Save results via shell redirect
$ zz benchmark > results.md                # Save to any file
$ zz benchmark | grep "Path"               # Pipe to other tools
$ zz benchmark --format=json | jq '.results[]'  # Process JSON output

# Baseline comparison (auto-loads if exists)
$ zz benchmark --baseline=old.md           # Compare with specific baseline
$ zz benchmark --no-compare                # Disable auto-comparison
```

### Build Commands (project workflow)
```bash
# Common workflow with file management
$ zig build benchmark                      # Save to latest.md, compare, show pretty output
$ zig build benchmark-baseline             # Create/update baseline.md
$ zig build benchmark-stdout               # Pretty output without saving

# Release mode benchmarking (longer duration for more stable results)
$ zig build -Doptimize=ReleaseFast
$ ./zig-out/bin/zz benchmark --duration=5s
```

**Benchmark Features:**
- Multiple output formats for different use cases
- Automatic baseline comparison (when benchmarks/baseline.md exists)
- Regression detection with exit code 1 (20% threshold)
- Clean separation: CLI for data, build commands for workflow
- Color-enhanced terminal output with progress bars
- Human-readable time units (ns, μs, ms, s)
- **Duration multiplier system** - Allows extending benchmark duration for more stable results

**Performance Baselines (Debug build):**
- Path operations: ~47μs per operation (20-30% faster than stdlib)
- String pooling: ~145ns per operation (95-100% cache efficiency)
- Memory pools: ~50μs per allocation/release cycle
- Glob patterns: ~25ns per operation (75% fast-path hit ratio)
- Benchmark execution: ~8 seconds total (each benchmark targets ~2 seconds)
- Regression threshold: 20% (to account for Debug mode variance)
- Time-based execution: Each benchmark runs for a configurable duration (default: 2 seconds)

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
- **`benchmark.zig`** - Performance measurement with color output, multiple formats, and baseline comparison

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

## Claude Code Configuration

The project is configured for optimal Claude Code usage:

**Tool Preferences (`.claude/config.json`):**
- `rg:*` - Prefer ripgrep (`rg`) over `grep`/`find`/`cat`
- `zz:*` - Full access to project CLI for testing and development and feature usage

**Best Practices:**
- Always use `rg` for text search instead of `grep` or `find`
- Use `zz` commands for benchmarking and testing
- Leverage Claude Code's native Grep tool which uses ripgrep internally

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
- Never use `sed` or write Bash loops to edit files, prefer direct editing instead
- Claude Code is configured to prefer `rg` via `.claude/config.json` allowedCommands
- Always update docs at ./CLAUDE.md and ./README.md
- Always include tests for new functionality and newly handled edge cases
    (and please don't cheat on tests lol,
    identify root causes and leave `// TODO` if you're stumped)
- Less is more - avoid over-engineering, and when in doubt, ask me or choose the simple option

**Current Status:** ✓ **Production ready with comprehensive performance optimizations** - All 190+ tests passing (100% success rate). Full feature set with significant performance improvements and enhanced developer experience.

**✅ Recent Improvements:**
- **Color-enhanced benchmark output** - Progress bars, human-readable units, visual hierarchy
- **Comprehensive documentation** - Architecture, performance, and contribution guides added
- **20-30% faster path operations** - Direct buffer manipulation in joinPath
- **15-25% memory reduction** - String interning with PathCache integration  
- **40-60% glob speedup** - Fast-path optimization for common patterns
- **Reduced allocation overhead** - Memory pools for ArrayList and string reuse
- **Better cache locality** - Stdlib HashMapUnmanaged integration

**Architecture:** Complete filesystem abstraction with parameterized dependencies, unified pattern matching engine, comprehensive benchmarking suite, and modular command structure. See [docs/slop/ARCHITECTURE.md](docs/slop/ARCHITECTURE.md) for detailed system design.

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

## Related Documentation

Core documentation is organized in `docs/slop/` for additional reference:

- [docs/slop/ARCHITECTURE.md](docs/slop/ARCHITECTURE.md) - System design and module relationships
- [docs/slop/PERFORMANCE.md](docs/slop/PERFORMANCE.md) - Optimization guide and benchmarks
- [docs/slop/CONTRIBUTING.md](docs/slop/CONTRIBUTING.md) - How to contribute effectively
- [docs/slop/PATTERNS.md](docs/slop/PATTERNS.md) - Pattern matching implementation details
- [docs/slop/TESTING.md](docs/slop/TESTING.md) - Testing strategy and coverage
- [docs/slop/TROUBLESHOOTING.md](docs/slop/TROUBLESHOOTING.md) - Common issues and solutions

**Note:** The `docs/slop/` directory is excluded from `zz tree` output via `zz.zon` configuration to keep tree views clean.