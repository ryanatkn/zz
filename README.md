# zz - CLI Utilities

High-performance command-line utilities written in Zig with zero dependencies for POSIX systems. Features optimized directory visualization and LLM prompt generation with aggressive performance improvements.

**Platform Support:** Linux, macOS, BSD, and other POSIX-compliant systems. Windows is not supported.

**Architecture:** Clean modular design with consolidated utilities, unified error handling, and POSIX-optimized implementations for lean builds.

## Installation

```bash
# Install to ~/.zz/bin (recommended)
zig build install-user

# Install to custom location
zig build install-user -Dprefix=~/my-tools

# Production install (optimized)
zig build install-user -Doptimize=ReleaseFast
```

Then add `~/.zz/bin` to your PATH:
```bash
echo 'export PATH="$PATH:~/.zz/bin"' >> ~/.bashrc
source ~/.bashrc
```

## Quick Start

```bash
# Check requirements
zig version  # Requires 0.14.1+

# After installation
zz tree                        # Show directory tree
zz prompt "src/**/*.zig"       # Generate LLM prompt
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
zz benchmark [options]                          # Run performance benchmarks
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

# Benchmark options:
#   --iterations=N           - Number of iterations (default: 10000)
#   --output=FILE            - Write results to markdown file
#   --compare=FILE           - Compare with baseline file
#   --save-baseline          - Save as benchmarks/baseline.md
#   --verbose                - Show detailed output and performance tips
#   --path                   - Run only path joining benchmarks
#   --string-pool            - Run only string pool benchmarks
#   --memory-pools           - Run only memory pool benchmarks
#   --glob                   - Run only glob pattern benchmarks
```

## Examples

```bash
# Tree visualization
zz tree                          # Current directory
zz tree src/ 2                   # src directory, 2 levels deep
zz tree --format=list            # Flat list format

# LLM prompt generation
zz prompt "src/**/*.zig"         # All Zig files recursively
zz prompt src/ docs/             # Multiple directories  
zz prompt "*.{zig,md}" --prepend="Context:" # Multiple types with prefix

# Performance benchmarks
zz benchmark                                     # Run all benchmarks
zz benchmark --output=benchmarks/latest.md       # Save to file
zz benchmark --compare=benchmarks/baseline.md    # Compare with baseline
zig build benchmark-save                         # Quick save to latest.md
zig build benchmark-compare                      # Quick compare (fails on regression)
zig build benchmark-baseline                     # Update baseline
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

## Development

See **[CLAUDE.md](CLAUDE.md)** for detailed development documentation, architecture details, and performance guidelines.

## Requirements

- Zig 0.14.1+
- POSIX-compliant OS (Linux, macOS, BSD)  
- Not supported: Windows

## Technical Documentation

For detailed architecture documentation, development guidelines, and implementation details, see **[CLAUDE.md](CLAUDE.md)**.

## License

See individual component licenses in their respective directories.