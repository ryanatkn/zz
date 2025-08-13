# zz - CLI Utilities

High-performance command-line utilities written in Zig for POSIX systems. Features optimized directory visualization, intelligent LLM prompt generation with **AST-based code extraction via tree-sitter**, and comprehensive performance benchmarking.

**Platform Support:** Linux, macOS, BSD, and other POSIX-compliant systems. Windows is not supported.

**Architecture:** Clean modular design with filesystem abstraction, unified pattern matching, tree-sitter AST integration, and aggressive performance optimizations. See [docs/slop/ARCHITECTURE.md](./docs/slop/ARCHITECTURE.md) for system design details.

## Requirements

- Zig 0.14.1 or later
- POSIX-compliant operating system (Linux, macOS, BSD)
- Git (for cloning the repository)

All dependencies are vendored in the `deps/` directory for reliability and reproducibility. See [deps/README.md](deps/README.md) for details.

## Installation

```bash
# Clone with vendored dependencies
git clone https://github.com/ryanatkn/zz.git
cd zz

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
- **AST-based code extraction** using tree-sitter for precise, language-aware parsing
- **Extraction modes** with real syntax tree traversal (Zig language supported):
  - `--signatures`: Function/method signatures via AST nodes
  - `--types`: Type definitions (structs, enums, unions) via AST
  - `--docs`: Documentation comments via AST parsing
  - `--imports`: Import statements (text-based fallback)
  - `--errors`: Error handling code (text-based fallback)
  - `--tests`: Test blocks via AST nodes
  - `--full`: Complete source (default)
- **Combine flags** for custom extraction: `zz prompt src/ --signatures --types`
- **Graceful fallback** to text-based extraction for unsupported languages
- Directory support: `zz prompt src/` processes all files recursively
- Advanced glob pattern support with 40-60% fast-path optimization
- Smart code fence detection (handles nested backticks)
- Automatic file deduplication
- Markdown output with semantic XML tags

### Performance Benchmarking
- Comprehensive performance measurement suite with color-coded output
- Multiple output formats: markdown, JSON, CSV, and pretty terminal display
- Automatic baseline comparison with regression detection (20% threshold)
- Human-readable time units (ns, μs, ms, s) with progress bars
- **Duration multiplier system** - Allows extending benchmark duration for more stable results
- Time-based execution with configurable duration per benchmark

## Commands

```bash
zz tree [directory] [depth] [options]  # Show directory tree
zz prompt [files...] [options]         # Generate LLM prompt
zz benchmark [options]                  # Run performance benchmarks
zz help                                 # Display detailed help
zz --help                               # Display detailed help
zz -h                                   # Display brief help

# Tree format options:
#   --format=FORMAT, -f FORMAT  - Output format: tree (default) or list
#   --show-hidden               - Show hidden files
#   --no-gitignore              - Disable .gitignore parsing

# Prompt options:
#   --prepend=TEXT           - Add text before files
#   --append=TEXT            - Add text after files
#   --allow-empty-glob       - Warn instead of error for empty globs
#   --allow-missing          - Warn instead of error for all missing files
#   Supports glob patterns   - *.zig, **/*.zig, *.{zig,md}
#   Supports directories     - src/, src/subdir/

# Benchmark options (outputs to stdout):
#   --format=FORMAT          - Output format: markdown (default), json, csv, pretty
#   --duration=TIME          - Duration per benchmark (default: 2s, formats: 1s, 500ms)
#   --duration-multiplier=N  - Extra multiplier for extending benchmark duration (default: 1.0)
#   --baseline=FILE          - Compare with baseline (default: benchmarks/baseline.md)
#   --no-compare             - Disable automatic baseline comparison
#   --only=path,string       - Run only specific benchmarks (comma-separated)
#   --skip=glob,memory       - Skip specific benchmarks
#   --warmup                 - Include warmup phase
```

## Examples

```bash
# Tree visualization
zz tree                          # Current directory
zz tree src/ 2                   # src directory, 2 levels deep
zz tree --format=list            # Flat list format
zz tree -f list                  # Same as above using short flag

# LLM prompt generation with AST extraction
zz prompt "src/**/*.zig"         # All Zig files recursively
zz prompt src/ docs/             # Multiple directories  
zz prompt "*.{zig,md}" --prepend="Context:" # Multiple types with prefix

# Precise AST-based extraction (Zig language)
zz prompt src/*.zig --signatures         # Extract only function signatures
zz prompt src/*.zig --types              # Extract type definitions
zz prompt src/*.zig --signatures --types # Combine extraction modes
zz prompt src/*.zig --tests              # Extract test blocks

# Performance benchmarks (CLI outputs to stdout)
zz benchmark                                     # Markdown to stdout
zz benchmark --format=pretty                     # Pretty terminal output
zz benchmark --format=json                       # JSON output
zz benchmark > benchmarks/baseline.md            # Save baseline via redirect
zz benchmark --only=path,string                  # Run specific benchmarks
zz benchmark --duration-multiplier=2.0           # 2x longer for all benchmarks

# Build commands (handle file management)
zig build benchmark                              # Save to latest.md and show comparison
zig build benchmark-baseline                     # Create new baseline
zig build benchmark-stdout                       # Pretty output without saving
```

See [CLAUDE.md](./CLAUDE.md) for more details.

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

## Documentation

- **[CLAUDE.md](CLAUDE.md)** - Development guide and implementation details

**Additional Documentation** (in `docs/slop/`, excluded from tree views):
- **[docs/slop/ARCHITECTURE.md](docs/slop/ARCHITECTURE.md)** - System design and module relationships
- **[docs/slop/CONTRIBUTING.md](docs/slop/CONTRIBUTING.md)** - How to contribute to the project
- **[docs/slop/PERFORMANCE.md](docs/slop/PERFORMANCE.md)** - Performance characteristics and optimization guide
- **[docs/slop/PATTERNS.md](docs/slop/PATTERNS.md)** - Pattern matching implementation details
- **[docs/slop/TESTING.md](docs/slop/TESTING.md)** - Testing strategy and coverage
- **[docs/slop/TROUBLESHOOTING.md](docs/slop/TROUBLESHOOTING.md)** - Common issues and solutions

## Requirements

- Zig 0.14.1+
- POSIX-compliant OS (Linux, macOS, BSD)  
- Not supported: Windows

## Dependencies

`zz` uses minimal, strategic dependencies:
- **Tree-sitter** - Industry-standard parsing library for language-aware code extraction
  - Enables intelligent code analysis across 100+ languages
  - Managed automatically via Zig package manager

## Technical Documentation

For detailed architecture documentation, development guidelines, and implementation details, see **[CLAUDE.md](CLAUDE.md)**.

## License

See individual component licenses in their respective directories.