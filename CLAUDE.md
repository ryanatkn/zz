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
    │   ├── filesystem                 # Filesystem abstraction layer (parameterized for testing)
    │   │   ├── interface.zig          # Abstract filesystem interfaces (FilesystemInterface, DirHandle, FileHandle)
    │   │   ├── mock.zig               # Mock filesystem implementation for testing
    │   │   └── real.zig               # Real filesystem implementation for production
    │   ├── lib                        # Shared utilities and infrastructure (POSIX-optimized with performance focus)
    │   │   ├── benchmark.zig          # Performance measurement with markdown output
    │   │   ├── c.zig                  # Centralized C imports for language grammars
    │   │   ├── filesystem.zig         # Consolidated filesystem error handling patterns
    │   │   ├── parser.zig             # AST-based code extraction with tree-sitter
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
    │   ├── filesystem.zig             # Filesystem abstraction API entry point
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

# Help commands
$ zz -h                          # Brief help overview
$ zz --help                      # Detailed help with all options
$ zz help                        # Same as --help
```

## Testing

```bash
$ zig build test                                       # Run all tests with output

# Note: Direct `zig test src/test.zig` will NOT work due to tree-sitter module dependencies
# Always use `zig build test` which properly configures modules and links libraries
```

Comprehensive test suite covers configuration parsing, directory filtering, performance optimization, edge cases, security patterns, and AST-based extraction. 

**Current test status:** ✅ **All 302 tests passing (100% pass rate)**
- Fixed mock filesystem directory iteration for "." paths
- Fixed traversal to not skip initial directory in recursive operations
- All tree-sitter integration and core features working correctly
- Added comprehensive parser tests for all supported languages
- TypeScript parser has a version compatibility issue (marked as TODO)

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
$ zz benchmark --format=pretty             # Clean color terminal output with status indicators
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
- Clean color-enhanced terminal output with status indicators
- Human-readable time units (ns, μs, ms, s)
- **Duration multiplier system** - Allows extending benchmark duration for more stable results

**Performance Baselines (Release build, 2025-08-13):**
- Path operations: ~11μs per operation (78% improvement, 20-30% faster than stdlib)
- String pooling: ~11ns per operation (100% cache efficiency)
- Memory pools: ~11μs per allocation/release cycle
- Glob patterns: ~4ns per operation (75% fast-path hit ratio)
- Code extraction: ~21μs per extraction (4 modes: full, signatures, types, combined)
- Benchmark execution: ~10 seconds total (5 benchmarks with varied durations based on multipliers)
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

## Language Support

**Supported Languages with Complete AST Integration:**
- **Zig** - Full AST support for functions, types, tests, docs
- **CSS** - Selectors, properties, variables, media queries  
- **HTML** - Elements, attributes, semantic structure, event handlers
- **JSON** - Structure validation, key extraction, schema analysis
- **TypeScript** - Functions, interfaces, types (.ts files only, no .tsx)
- **Svelte** - Multi-section components (script/style/template) with section-aware parsing

## AST Integration Framework

**Unified NodeVisitor Pattern:**
All language parsers implement a consistent `walkNode()` interface using the NodeVisitor pattern for extensible AST traversal:

```zig
// Example: CSS AST extraction
pub fn walkNode(allocator: std.mem.Allocator, root: *const AstNode, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
    var extraction_context = ExtractionContext{
        .allocator = allocator,
        .result = result,
        .flags = flags,
        .source = source,
    };
    
    var visitor = NodeVisitor.init(allocator, cssExtractionVisitor, &extraction_context);
    try visitor.traverse(root, source);
}
```

**Language-Specific Implementations:**
- **HTML Parser**: Element detection, structure analysis, event handler extraction
- **JSON Parser**: Structural nodes, key extraction, schema analysis, type detection
- **Svelte Parser**: Section-aware parsing (script/style/template), reactive statements, props extraction
- **CSS Parser**: Selector matching, rule extraction, variable detection, media queries
- **TypeScript Parser**: Enhanced with dependency analysis and import extraction
- **Zig Parser**: Maintains existing tree-sitter integration while conforming to unified interface

**Mock AST Framework:**
- Complete AST abstraction layer using `AstNode` structure
- Generic pointer support for future tree-sitter integration
- Mock implementations for testing without external dependencies
- Visitor pattern supports both real and mock AST traversal

## Incremental Processing with AST Cache

**AST Cache Integration:**
The incremental processing system now includes sophisticated AST cache management:

```zig
// FileTracker with AST cache support
pub const FileTracker = struct {
    allocator: std.mem.Allocator,
    files: std.HashMap([]const u8, FileState, std.hash_map.StringContext, 80),
    dependency_graph: DependencyGraph,
    change_detector: ChangeDetector,
    ast_cache: ?*AstCache, // Optional AST cache for invalidation
};
```

**Smart Cache Invalidation:**
- **File Hash-based Keys**: AST cache entries keyed by file hash + extraction flags
- **Selective Invalidation**: `invalidateByFileHash()` removes only entries for changed files
- **Cascade Invalidation**: Automatically invalidates dependent files when imports change
- **Dependency Tracking**: Uses dependency graph to identify affected files

**Cache Key Generation:**
```zig
// Generate cache key for file with extraction flags
pub fn getAstCacheKey(self: *FileTracker, file_path: []const u8, extraction_flags_hash: u64) ?AstCacheKey {
    if (self.files.get(file_path)) |file_state| {
        return AstCacheKey.init(
            file_state.hash,
            1, // parser version
            extraction_flags_hash
        );
    }
    return null;
}
```

**Performance Benefits:**
- **Incremental Parsing**: Only re-parse files that have actually changed
- **Cache Efficiency**: ~95% cache hit rate for unchanged files with different extraction flags
- **Memory Management**: LRU eviction with configurable memory limits
- **Dependency Optimization**: Cascade invalidation prevents stale cache entries

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
- **Extensible:** Architecture ready for TypeScript, Rust, Go, Python grammars

**Glob Pattern Support with Performance Optimizations:**
- Basic wildcards: `*.zig`, `test?.zig`
- Recursive patterns: `src/**/*.zig`
- **Optimized alternatives:** `*.{zig,md,txt}` with fast-path expansion
- **Fast-path common patterns:** `*.{zig,c,h}`, `*.{js,ts}`, `*.{md,txt}` pre-optimized (40-60% faster)
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

## Development Workflow

**Managing Vendored Dependencies:**

The project uses vendored dependencies for tree-sitter libraries to ensure reliable, reproducible builds without network access.

```bash
# Check current state (idempotent - safe to run anytime)
./scripts/update-deps.sh

# Force update all dependencies
./scripts/update-deps.sh --force

# Force update specific dependency
./scripts/update-deps.sh --force-dep tree-sitter

# View help and available dependencies
./scripts/update-deps.sh --help
```

**Script Features:**
- **Idempotent:** Only updates when versions change or files are missing
- **Efficient:** Skips up-to-date dependencies, uses shallow git clones
- **Clean:** Removes `.git` directories and incompatible build files
- **Versioned:** Creates `.version` files for tracking

**After updating dependencies:**
```bash
zig build test           # Verify everything works
git add deps/            # Commit vendored code
git commit -m "Update vendored dependencies"
```

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

**Task Documentation Workflow:**
- **Active task documentation** should be placed in root directory with `TASK_*.md` prefix for high visibility
- **Permanent documentation** (README.md, CLAUDE.md) remains unprefixed in root
- **Completed task documentation** should be moved to `docs/archive/` with meaningful names (e.g., `2025_01_parser_improvements.md`)
- **Always commit task documentation** to git both during work and when archiving
- This workflow ensures active work is visible while maintaining a historical record of completed tasks

**Current Status:** ✓ **Production ready with complete DRY architecture** - All 302 tests passing (100% success rate). Complete AST-based code extraction with unified NodeVisitor pattern and aggressive code sharing through helper modules.

**✓ Recent Improvements:**
- **DRY Architecture Refactoring** - Eliminated ~500 lines of duplicate code through 6 new helper modules
- **Advanced Code Analysis Features** - Call graph generation, dependency analysis, and semantic code summarization
- **Collection Helpers** - Memory-managed ArrayLists with RAII cleanup eliminating 30+ duplicate patterns
- **File Helpers** - Consolidated file operations eliminating 15+ duplicate file reading patterns
- **Error Helpers** - Standardized error handling eliminating 20+ switch statement patterns
- **AST Walker** - Unified AST traversal consolidating 5+ identical walkNode implementations
- **Conditional Tree-sitter Import** - Fixed test compatibility with dynamic module loading
- **Complete AST Integration** - All languages (HTML, JSON, Svelte, CSS, TypeScript, Zig) now support walkNode() implementations
- **Unified NodeVisitor Pattern** - Consistent AST traversal across all parsers with extensible visitor interface
- **AST Cache Integration** - Incremental processing with AST cache invalidation for changed files
- **Cascade Invalidation** - Smart dependency tracking automatically invalidates dependent files
- **Enhanced Parser Interface** - Both simple and AST-based extraction through unified API
- **Comprehensive Testing** - 302 tests including complete coverage of all helper modules
- **Mock AST Framework** - Complete AST abstraction layer for testing without tree-sitter dependencies
- **Fixed mock filesystem** - Proper path normalization and "." directory handling
- **Fixed directory traversal** - Initial directory no longer skipped by ignore patterns
- **Tree-sitter AST integration** - Real syntax tree parsing for precise extraction
- **Vendored dependencies** - All tree-sitter libraries in `deps/` for reliability
- **AST node traversal** - Extract functions, types, docs, tests via syntax tree
- **Graceful fallback** - Falls back to text extraction on parse errors
- **Color-enhanced benchmark output** - Progress bars, human-readable units
- **20-30% faster path operations** - Direct buffer manipulation in joinPath
- **15-25% memory reduction** - String interning with PathCache integration  
- **40-60% glob speedup** - Fast-path optimization for common patterns

**Architecture:** Complete filesystem abstraction with parameterized dependencies, unified pattern matching engine, comprehensive benchmarking suite, and modular command structure. See [docs/archive/ARCHITECTURE.md](docs/archive/ARCHITECTURE.md) for detailed system design.

## Test Coverage

The project has comprehensive test coverage including:
- **AST Integration**: Complete coverage of walkNode() implementations for all languages
- **Mock AST Framework**: Testing AST-based extraction without external dependencies
- **Incremental Processing**: AST cache invalidation, dependency tracking, cascade updates
- **Edge cases**: Empty inputs, special characters, Unicode, long filenames
- **Security**: Path traversal, permission handling
- **Performance**: Large files, deep recursion, memory stress tests
- **Integration**: End-to-end command testing, format combinations
- **Glob patterns**: Wildcards, braces, recursive patterns, hidden files
- **Pattern matching**: Unified pattern engine with performance-critical optimizations
- **Filesystem abstraction**: Mock filesystem testing for complete test isolation
- **Parameterized dependencies**: All modules testable with mock filesystems

**Current test status:** ✅ **All 302 tests passing (100% pass rate)**
- Complete DRY architecture testing with all helper modules
- Complete AST integration testing with mock framework
- Comprehensive incremental processing and cache validation
- Language-specific parser testing with unified interface
- End-to-end extraction verification for all supported languages
- Full coverage of collection helpers, file helpers, error helpers, and AST walker

## Related Documentation

Core documentation is organized in `docs/archive/` for additional reference:

- [docs/archive/ARCHITECTURE.md](docs/archive/ARCHITECTURE.md) - System design and module relationships
- [docs/archive/PERFORMANCE.md](docs/archive/PERFORMANCE.md) - Optimization guide and benchmarks
- [docs/archive/CONTRIBUTING.md](docs/archive/CONTRIBUTING.md) - How to contribute effectively
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

Remember: Performance is a feature, every cycle counts.