# zz - CLI Utilities

Fast command-line utilities written in Zig with zero dependencies for POSIX systems. Features high-performance directory visualization and LLM prompt generation.

**Platform Support:** Linux, macOS, BSD, and other POSIX-compliant systems. Windows is not supported.

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
- High-performance directory traversal
- Multiple output formats (tree and list)
- Smart filtering (hides build artifacts, cache directories)
- Clean tree-style output formatting
- Configurable depth limits
- .gitignore-style pattern matching

### Prompt Generation
- Build LLM-optimized prompts from multiple files
- Advanced glob pattern support:
  - Basic wildcards: `*.zig`, `test?.zig`
  - Recursive: `**/*.zig`
  - Alternatives: `*.{zig,md}`
  - Nested braces: `*.{zig,{md,txt}}` 
  - Character classes: `log[0-9].txt`, `file[a-z].txt`, `test[!0-9].txt`
  - Escape sequences: `file\*.txt` matches literal `file*.txt`
- Smart code fence detection (handles nested backticks)
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

# Generate prompt from all Zig files
zig build run -- prompt "src/**/*.zig" > prompt.md

# Add text before/after files
zig build run -- prompt --prepend="Context:" --append="Question?" src/*.zig

# Multiple file types
zig build run -- prompt "*.{zig,md,txt}"

# Error if no files provided (won't default to *.zig)
zig build run -- prompt  # Error: No input files specified
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
# Build commands (default is Debug mode)
zig build                       # Debug build (default)
zig build -Doptimize=ReleaseFast # Fast release build  
zig build -Doptimize=ReleaseSafe # Safe release (with runtime checks)
zig build -Doptimize=ReleaseSmall # Smallest binary size
zig build --use-llvm            # Use LLVM backend

# Run directly after building
./zig-out/bin/zz [command]

# Run via build system
zig build run                   # Show help
zig build run -- tree           # Run tree command
zig build run -- prompt "*.zig" # Run prompt command
```

### Testing

```bash
# Run all tests
zig build test

# Run tree module tests only
zig build test-tree

# Run prompt module tests only
zig build test-prompt

# Alternative: run tests directly
zig test src/test.zig           # All tests
zig test src/tree/test.zig      # Tree module only
zig test src/prompt/test.zig    # Prompt module only
```

## Requirements

- Zig 0.14.1+
- POSIX-compliant OS (Linux, macOS, BSD)
- Not supported: Windows

## Technical Documentation

For detailed architecture documentation, development guidelines, and implementation details, see **[CLAUDE.md](CLAUDE.md)**.

## License

See individual component licenses in their respective directories.