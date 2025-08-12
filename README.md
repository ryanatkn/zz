# zz - CLI Utilities

High-performance command-line utilities written in Zig with zero dependencies for POSIX systems. Features optimized directory visualization and LLM prompt generation with aggressive performance improvements.

**Platform Support:** Linux, macOS, BSD, and other POSIX-compliant systems. Windows is not supported.

**Architecture:** Clean modular design with consolidated utilities, unified error handling, and POSIX-optimized implementations for lean builds.

## Quick Start

```bash
# Check requirements
zig version  # Requires 0.14.1+

# Build (defaults to Debug mode)
zig build                      # Debug build (default)
zig build -Doptimize=ReleaseFast  # Fast release build
zig build -Doptimize=ReleaseSmall # Small binary size
zig build --use-llvm           # Use LLVM backend

# Run
zig build run                  # Show help
zig build run -- tree          # Show current directory tree
zig build run -- help          # Show available commands
zig build run -- prompt        # Generate LLM prompts

# Or build and run directly
zig build && ./zig-out/bin/zz tree
```

## Features

### Tree Visualization
- High-performance directory traversal with consolidated error handling
- Multiple output formats (tree and list)
- Modular configuration system with unified pattern matching engine
- Clean tree-style output formatting with optimized rendering
- Configurable depth limits with intelligent defaults
- Safe pattern matching (no leaky substring matches)
- Arena allocators for improved memory performance

### Prompt Generation
- Build LLM-optimized prompts from multiple files with shared traversal utilities
- Directory support: `zz prompt src/` processes all files recursively
- Advanced glob pattern support with consolidated pattern matching:
  - Basic wildcards: `*.zig`, `test?.zig`
  - Recursive: `**/*.zig`
  - Alternatives: `*.{zig,md}`
  - Nested braces: `*.{zig,{md,txt}}` 
  - Character classes: `log[0-9].txt`, `file[a-z].txt`, `test[!0-9].txt`
  - Escape sequences: `file\*.txt` matches literal `file*.txt`
- Explicit file ignore detection: Errors when explicitly requested files are ignored
- Smart code fence detection (handles nested backticks)
- Arena allocators for efficient memory usage during glob expansion
- Automatic file deduplication
- Markdown output with semantic XML tags
- Configurable ignore patterns
- Hidden file handling (use `.*` to explicitly match hidden files)

## Commands

```bash
zz tree [directory] [depth] [--format=FORMAT]  # Show directory tree
zz prompt [files...] [options]                 # Generate LLM prompt
zz help                                         # Display help

# Tree format options:
#   --format=tree  (default) - Tree with box characters
#   --format=list            - Flat list with ./path prefixes

# Prompt options:
#   --prepend=TEXT           - Add text before files
#   --append=TEXT            - Add text after files
#   --allow-empty-glob       - Warn instead of error for empty globs
#   --allow-missing          - Warn instead of error for all missing files
#   Supports glob patterns   - *.zig, **/*.zig, *.{zig,md}
#   Supports directories     - src/, src/subdir/
```

## Examples

```bash
# Build and install
zig build

# Show current directory structure (tree format)
zig build run -- tree
# Or after building:
./zig-out/bin/zz tree

# Show as flat list instead of tree
zig build run -- tree --format=list

# Show current directory, 2 levels deep
zig build run -- tree . 2

# Show src directory with default depth  
zig build run -- tree src/

# Gitignore support (respects .gitignore by default)
zig build run -- tree              # Hides files matching .gitignore patterns
zig build run -- tree --no-gitignore  # Shows all files including gitignored ones

# Generate prompt from all Zig files
zig build run -- prompt "src/**/*.zig" > prompt.md

# Process entire directory
zig build run -- prompt src/
zig build run -- prompt src/cli/ docs/

# Add text before/after files
zig build run -- prompt --prepend="Context:" --append="Question?" src/*.zig

# Multiple file types
zig build run -- prompt "*.{zig,md,txt}"

# Mix directories and files
zig build run -- prompt README.md src/ docs/*.md

# Prompt with gitignore support
zig build run -- prompt "src/**/*.zig"  # Excludes gitignored files by default
zig build run -- prompt "src/**/*.zig" --no-gitignore  # Includes all matching files

# Error if no files provided (won't default to *.zig)
zig build run -- prompt  # Error: No input files specified

# Explicit ignore detection (exits with code 1)
zig build run -- prompt .gitignore  # Error: Explicitly requested file was ignored: .gitignore
```

**Exit Codes:**
- `0` - Success
- `1` - Error (missing files, ignored files, empty globs, etc.)

## Configuration

Create a `zz.zon` file in any directory to customize behavior:

```zon
.{
    // Base patterns: "extend" (defaults + custom) or custom array
    .base_patterns = "extend",
    
    // Additional ignore patterns (tree and prompt)
    .ignored_patterns = .{
        "logs",
        "custom_build_dir",
    },
    
    // Files to completely hide 
    .hidden_files = .{
        "secret.key",
    },
    
    // Symlink behavior: "skip", "follow", or "show"
    .symlink_behavior = "skip",
    
    // Gitignore support: true (default) or false
    .respect_gitignore = true,
}
```

**Key Features:**
- **Root-level config** - Single source of truth shared by all commands
- **Extend mode** - Add your patterns to sensible defaults
- **Custom mode** - Use only your patterns (no defaults)
- **Safe matching** - Exact path components only (no leaky substring matches)
- **Per-directory** - Config is respected from current working directory

**Default ignore patterns:** `.git`, `node_modules`, `.zig-cache`, `zig-out`, `build`, `dist`, `target`, `__pycache__`, `venv`, `tmp`, etc.

**Gitignore Integration:**
- Automatically reads `.gitignore` files from the current directory
- Files matching gitignore patterns are completely hidden (like `git ls-files` behavior)
- Directories matching gitignore patterns show as `[...]` 
- Use `--no-gitignore` flag or set `respect_gitignore = false` to disable
- Supports basic gitignore syntax: wildcards (`*.tmp`), negation (`!important.tmp`), directory patterns (`build/`)

## Architecture

- **`src/cli/`** - Command parsing and execution
- **`src/config/`** - Configuration system with pattern resolution
- **`src/filesystem/`** - Filesystem abstraction layer for testing
- **`src/patterns/`** - High-performance pattern matching engine  
- **`src/tree/`** - Directory traversal and visualization  
- **`src/prompt/`** - LLM prompt generation with glob support

**Design:** Single binary, no dependencies, pure Zig implementation.

## Development

```bash
$ zig build                      # Debug build (default)
$ zig build -Doptimize=ReleaseFast  # Fast release build
$ zig build run -- tree         # Run tree command  
$ zig build run -- prompt "*.zig"  # Run prompt command
```

### Testing

```bash
$ zig build test              # Run all tests (recommended)
$ zig build test-tree         # Run tree module tests only
$ zig build test-prompt       # Run prompt module tests only
$ zig test src/test.zig --test-filter "directory"    # Run specific tests by name pattern
```

Comprehensive test suite with 190 tests covering edge cases, security, performance, and integration testing.

## Architecture

**High-Performance Design:**
- **Shared Infrastructure** (`src/lib/`): Consolidated utilities eliminate 300+ lines of duplicate code
- **POSIX-Optimized**: Custom path utilities optimized for POSIX systems (leaner than std.fs.path)
- **Unified Error Handling**: Consistent filesystem error patterns across all operations
- **Memory Optimization**: Arena allocators and efficient traversal reduce allocation overhead
- **Zero Dependencies**: Pure Zig implementation with no external dependencies

**Modular Structure:**
- **CLI Module** - Command parsing and dispatch
- **Tree Module** - Directory visualization with multiple output formats  
- **Prompt Module** - LLM prompt generation with advanced glob support
- **Lib Module** - Shared utilities (path, traversal, filesystem, string_pool)
- **Patterns Module** - Unified pattern matching engine
- **Config Module** - Modular ZON-based configuration system

## Requirements

- Zig 0.14.1+
- POSIX-compliant OS (Linux, macOS, BSD)  
- Not supported: Windows

## Technical Documentation

For detailed architecture documentation, development guidelines, and implementation details, see **[CLAUDE.md](CLAUDE.md)**.

## License

See individual component licenses in their respective directories.