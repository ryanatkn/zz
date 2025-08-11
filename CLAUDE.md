# zz - CLI Utilities

Fast command-line utilities written in Zig. Currently features high-performance filesystem tree visualization and LLM prompt generation.

Performance is a top priority, and we dont care about backwards compat -
always try to get to the final best code. 

## Environment

```bash
$ zig version
0.14.1
```

No external dependencies - pure Zig implementation.

## Project Structure

```
└── .
    ├── .claude [...]                  # Claude Code configuration directory
    ├── .git [...]                     # Git repository metadata  
    ├── .zig-cache [...]               # Zig build cache (filtered from tree output)
    ├── src                            # Source code (modular architecture)
    │   ├── cli                        # CLI interface module (command parsing & execution)
    │   │   ├── args.zig               # Argument parsing utilities
    │   │   ├── command.zig            # Command enumeration and string parsing
    │   │   ├── help.zig               # Usage documentation and help text
    │   │   ├── main.zig               # CLI entry point and argument processing
    │   │   └── runner.zig             # Command dispatch and orchestration
    │   ├── prompt                     # Prompt generation module (LLM-optimized file aggregation)
    │   │   ├── builder.zig            # Core prompt building with smart fencing
    │   │   ├── config.zig             # Configuration and ignore patterns
    │   │   ├── error_test.zig         # Error handling and flag parsing tests
    │   │   ├── fence.zig              # Smart fence detection for code blocks
    │   │   ├── glob.zig               # Glob pattern expansion and matching
    │   │   ├── main.zig               # Prompt command entry point
    │   │   ├── prompt_test.zig        # Core functionality tests
    │   │   └── test.zig               # Test runner for prompt module
    │   ├── tree                       # Tree visualization module (high-performance directory traversal)
    │   │   ├── test                   # Comprehensive test suite
    │   │   │   ├── concurrency_test.zig    # Multi-instance and config lifecycle tests
    │   │   │   ├── config_test.zig         # Configuration parsing and memory management
    │   │   │   ├── edge_cases_test.zig     # Unicode, symlinks, encoding edge cases
    │   │   │   ├── filter_test.zig         # Pattern matching comprehensive tests
    │   │   │   ├── formatter_test.zig      # Output formatting tests
    │   │   │   ├── integration_test.zig    # End-to-end workflow tests
    │   │   │   ├── path_builder_test.zig   # Path manipulation utility tests
    │   │   │   ├── performance_test.zig    # Performance and scalability tests
    │   │   │   └── walker_test.zig         # Core traversal algorithm tests
    │   │   ├── CLAUDE.md              # Detailed tree module documentation
    │   │   ├── config.zig             # Configuration loading and argument parsing
    │   │   ├── entry.zig              # File/directory data structures
    │   │   ├── filter.zig             # Pattern matching and ignore logic
    │   │   ├── format.zig             # Output format enumeration (tree, list)
    │   │   ├── formatter.zig          # Multi-format output rendering
    │   │   ├── main.zig               # Tree command entry point
    │   │   ├── path_builder.zig       # Path manipulation utilities
    │   │   ├── test.zig               # Test runner for basic functionality
    │   │   └── walker.zig             # Core traversal algorithm with optimizations
    │   ├── main.zig                   # Minimal application entry point
    │   └── test.zig                   # Main test runner for entire project
    ├── zig-out [...]                  # Build output directory (auto-generated)
    ├── .gitignore                     # Git ignore patterns
    ├── CLAUDE.md                      # AI assistant development documentation
    ├── README.md                      # User-facing documentation and usage guide
    ├── build.zig                      # Zig build system configuration
    ├── build.zig.zon                  # Package manifest
    ├── zz                             # Build wrapper script (auto-builds and runs)
    └── zz.zon                         # CLI configuration (tree filtering patterns)
```

## Commands

```bash
$ ./zz tree [dir] [depth] [--format=FORMAT]  # Directory tree visualization
$ ./zz prompt [files...] [options]           # Build LLM prompts from files
$ ./zz help                                  # Show available commands

# Tree format options
$ ./zz tree --format=tree    # Tree format with box characters (default)
$ ./zz tree --format=list    # List format with ./path prefixes

# Prompt examples
$ ./zz prompt src/*.zig                           # Add all .zig files in src/
$ ./zz prompt "src/**/*.zig"                      # Recursive glob (quotes needed)
$ ./zz prompt --prepend="Context:" --append="Request:" src/*.zig # Add text before/after
$ ./zz prompt "*.{zig,md}" > prompt.md            # Multiple extensions, output to file
$ ./zz prompt --allow-empty-glob "*.rs" "*.zig"  # Warn if *.rs matches nothing
$ ./zz prompt --allow-missing file1.zig file2.zig # Warn if files don't exist

# Development workflow - use ./zz instead of zig build for auto-rebuild
$ ./zz                       # Auto-builds and runs with default args (tree .)
$ ./zz tree src/             # Show source directory tree
$ zig build                  # Manual build only (outputs to zig-out/bin/zz)
```

## Testing

```bash
$ zig test src/test.zig        # Run all tests (recommended)
$ zig test src/tree/test.zig   # Run tree module tests only
$ zig test src/prompt/test.zig # Run prompt module tests only
```

Comprehensive test suite covers configuration parsing, directory filtering, performance optimization, edge cases, and security patterns.

## Module Structure

**Core Architecture:**
- **CLI Module:** `src/cli/` - Command parsing, validation, and dispatch system
- **Tree Module:** `src/tree/` - High-performance directory traversal with configurable filtering and multiple output formats
- **Prompt Module:** `src/prompt/` - LLM prompt generation with glob support, smart fencing, and deduplication

**Key Components:**
- **Configuration System:** `zz.zon` + fallback defaults for CLI behavior
- **Performance Optimizations:** Early directory skip, memory management, efficient traversal
- **Modular Design:** Each module is self-contained with clean interfaces

**Adding New Commands:**
1. Add to `Command` enum in `src/cli/command.zig`
2. Update parsing and help text
3. Add handler in `src/cli/runner.zig`  
4. Complex features get dedicated module with `run(allocator, args)` interface

## Prompt Module Features

**Glob Pattern Support:**
- Basic wildcards: `*.zig`, `test?.zig`
- Recursive patterns: `src/**/*.zig`
- Alternatives: `*.{zig,md,txt}`
- Automatic deduplication of matched files

**Smart Code Fencing:**
- Automatically detects appropriate fence length
- Handles nested code blocks correctly
- Preserves syntax highlighting

**Output Format:**
- Markdown with semantic XML tags for LLM context
- File paths in structured `<File path="...">` tags
- Configurable ignore patterns via `zz.zon`

**Error Handling:**
- Strict by default: errors on missing files or empty globs
- `--allow-empty-glob`: Warnings for non-matching glob patterns
- `--allow-missing`: Warnings for all missing files

## Tree Module Features

**Output Formats:**
- **Tree Format:** Traditional tree visualization with Unicode box characters
- **List Format:** Flat list with `./` path prefixes for easy parsing

**Performance Optimizations:**
- Early directory skip for ignored paths
- Efficient memory management with arena allocators
- Parallel directory traversal capability
- Smart filtering with .gitignore-style patterns

**Configuration:**
- Load from `zz.zon` for persistent settings
- Command-line arguments override config
- Sensible defaults for common use cases

## Code Style

- We want idiomatic Zig, taking more after C than C++
- Do not support backwards compatibility unless explicitly asked
- Never re-export in modules

## Notes to LLMs

- Focus on performance and clean architecture
- This is a CLI utilities project - no graphics or game functionality
- Test frequently with `./zz` to ensure each step works
- Less is more - avoid over-engineering
- Performance is top priority - optimize for speed
- Keep modules self-contained and focused on their specific purpose