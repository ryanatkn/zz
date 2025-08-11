# zz - CLI Utilities

Fast command-line utilities written in Zig with zero dependencies for POSIX systems. Features high-performance directory visualization and LLM prompt generation.

**Platform Support:** Linux, macOS, BSD, and other POSIX-compliant systems. Windows is not supported.

## Quick Start

```bash
# Check requirements
zig version  # Requires 0.14.1+

# Build and run
./zz         # Show current directory tree
./zz help    # Show available commands
./zz tree    # Display directory structure
./zz prompt  # Generate LLM prompts from files
```

## Features

### Tree Visualization
- High-performance directory traversal
- Multiple output formats (tree and list)
- Smart filtering (hides build artifacts, cache directories)
- Clean tree-style output formatting
- Configurable depth limits
- .gitignore-style pattern matching

### Prompt Generation
- Build LLM-optimized prompts from multiple files
- Glob pattern support (`*.zig`, `**/*.zig`, `*.{zig,md}`)
  - Note: Nested braces like `*.{zig,{md,txt}}` are not supported yet
- Smart code fence detection (handles nested backticks)
- Automatic file deduplication
- Markdown output with semantic XML tags
- Configurable ignore patterns
- Hidden file handling (use `.*` to explicitly match hidden files)

## Commands

```bash
./zz tree [directory] [depth] [--format=FORMAT]  # Show directory tree
./zz prompt [files...] [options]                # Generate LLM prompt
./zz help                                        # Display help

# Tree format options:
#   --format=tree  (default) - Tree with box characters
#   --format=list            - Flat list with ./path prefixes

# Prompt options:
#   --prepend=TEXT           - Add text before files
#   --append=TEXT            - Add text after files
#   --allow-empty-glob       - Warn instead of error for empty globs
#   --allow-missing          - Warn instead of error for all missing files
#   Supports glob patterns   - *.zig, **/*.zig, *.{zig,md}
```

## Examples

```bash
# Show current directory structure (tree format)
./zz tree

# Show as flat list instead of tree
./zz tree --format=list

# Show current directory, 2 levels deep
./zz tree . 2

# Show src directory with default depth  
./zz tree src/

# Generate prompt from all Zig files
./zz prompt "src/**/*.zig" > prompt.md

# Add text before/after files
./zz prompt --prepend="Context:" --append="Question?" src/*.zig

# Multiple file types
./zz prompt "*.{zig,md,txt}"

# Error if no files provided (won't default to *.zig)
./zz prompt  # Error: No input files specified
```

## Architecture

- **`src/cli/`** - Command parsing and execution
- **`src/tree/`** - Directory traversal and visualization
- **`src/prompt/`** - LLM prompt generation with glob support

### Design Principles
- Single binary with no external dependencies
- Direct function calls (no shell process spawning)
- Clean separation of concerns across modules
- Pure Zig implementation

## Development

```bash
# Build only
zig build

# Run directly  
./zig-out/bin/zz [command]

# Development build with debug info
zig build -Doptimize=Debug
```

### Testing

```bash
# Run all tests
zig test src/test.zig

# Run tree module tests only
zig test src/tree/test.zig

# Run prompt module tests only
zig test src/prompt/test.zig
```

## Requirements

- Zig 0.14.1+
- POSIX-compliant OS (Linux, macOS, BSD)
- Not supported: Windows

## Technical Documentation

For detailed architecture documentation, development guidelines, and implementation details, see **[CLAUDE.md](CLAUDE.md)**.

## License

See individual component licenses in their respective directories.