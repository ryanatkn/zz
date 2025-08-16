# zz

> ⚠️ AI slop code and docs, may be unstable and bad

zz is a CLI in Zig written by Claude Code and designed by people.
For the companion GUI see [Zzz](https://github.com/ryanatkn/zzz).

> status: vibe-engineered slop level 1

Fast command-line utilities in Zig for POSIX systems. LLM prompt generation with AST-based code extraction, directory trees, and performance benchmarking. **100% terminal-based**.

**Platforms:** Linux, macOS, BSD, POSIX. No Windows.

**Languages:** AST extraction for TypeScript, CSS, HTML, JSON, Zig, Svelte.

**Performance:** Optimized paths, patterns, incremental processing, AST caching.

**Architecture:** Modular `src/lib/` with filesystem abstraction, unified patterns, AST extraction. See [docs/archive/ARCHITECTURE.md](./docs/archive/ARCHITECTURE.md).

## Requirements

- Zig 0.14.1 or later
- POSIX-compliant operating system (Linux, macOS, BSD)
- Git (for cloning the repository)

Dependencies vendored in `deps/`. See [deps/README.md](deps/README.md).

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

Add `~/.zz/bin` to your PATH.

## Quick start

```bash
# Check requirements
zig version  # Requires 0.14.1+

# After installation
zz tree                        # Show directory tree
zz prompt "src/**/*.zig"       # Generate LLM prompt
zz benchmark --format=pretty   # Run performance benchmarks
zz format config.json          # Format code files
zz demo                        # Run interactive terminal demo
```

## Features

### Tree visualization
- Fast directory traversal
- Tree and list formats
- Pattern matching with `.gitignore` support
- Configurable depth limits
- Arena allocators

### Prompt generation
- **AST-based extraction** via NodeVisitor pattern
- **Language support**:
  - TypeScript: Interfaces, types, classes, functions (.ts)
  - CSS: Selectors, variables, media queries
  - HTML: Structure, elements, attributes
  - JSON: Keys, structure, schema
  - Zig: Functions, structs, tests
  - Svelte: Multi-section components
- **Extraction flags**: `--signatures`, `--types`, `--docs`, `--imports`, `--errors`, `--tests`, `--structure`, `--full` (default)
- **Combine flags**: `zz prompt src/ --signatures --types`
- Directory recursion, glob patterns, deduplication
- Smart fence detection, XML-tagged markdown output

### Code formatting
- **Languages**: Zig (`zig fmt`), JSON, HTML, CSS, TypeScript, Svelte
- **Options**: `--write` (in-place), `--check` (verify), `--stdin`, `--indent-size=N`, `--indent-style=space|tab`, `--line-width=N`
- Glob patterns supported

### Performance benchmarking
- Color-coded terminal output
- Formats: markdown, JSON, CSV, pretty
- Baseline comparison, 20% regression threshold
- Configurable duration per benchmark

### Incremental processing & caching
- AST cache with selective invalidation
- Dependency tracking with cascade updates
- xxHash change detection
- 95% cache hit rate
- LRU eviction

## Commands

```bash
zz tree [dir] [depth] [opts]    # Directory tree
zz prompt [files...] [opts]     # LLM prompt
zz benchmark [opts]              # Performance tests
zz format [files...] [opts]      # Format code
zz demo [opts]                   # Interactive demo
zz help, --help, -h              # Help

# Common options:
--format=tree|list|json|csv|pretty|markdown
--no-gitignore, --show-hidden
--write, --check, --stdin
--prepend=TEXT, --append=TEXT
--allow-empty-glob, --allow-missing
--duration=2s, --baseline=FILE
--indent-size=4, --indent-style=space|tab
```

## Examples

```bash
# Tree visualization
zz tree                          # Current directory
zz tree src/ 2                   # src directory, 2 levels deep
zz tree --format=list            # Flat list format
zz tree -f list                  # Same as above using short flag

# Prompt generation
zz prompt "src/**/*.zig"                 # All Zig files
zz prompt src/ docs/                     # Multiple directories  
zz prompt app.ts --signatures --types    # TypeScript interfaces and functions
zz prompt style.css --types              # CSS variables and selectors
zz prompt config.json --structure        # JSON keys and structure

# Code formatting
zz format config.json                    # Format and output to stdout
zz format config.json --write            # Format file in-place
zz format "src/**/*.json" --check        # Check if JSON files are formatted
echo '{"a":1}' | zz format --stdin       # Format from stdin
zz format "*.css" --indent-size=2        # Format CSS with 2-space indent

# Benchmarks
zz benchmark                              # Markdown to stdout
zz benchmark --format=pretty              # Terminal output
zz benchmark > benchmarks/baseline.md     # Save baseline
zig build benchmark                       # Save to latest.md with comparison
```


**Exit codes:** `0` success, `1` error

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

**Features:**
- Root-level config shared by all commands
- Extend mode adds to defaults, custom mode replaces them
- Exact path component matching
- Per-directory configs

**Default ignores:** `.git`, `node_modules`, `.zig-cache`, `zig-out`, `build`, `dist`, `target`, `__pycache__`, `venv`, `tmp`

**Gitignore:**
- Auto-reads `.gitignore` files
- Matched files hidden, directories show as `[...]`
- Disable with `--no-gitignore` or `respect_gitignore = false`
- Supports wildcards, negation, directory patterns


## Documentation

- **[CLAUDE.md](CLAUDE.md)** - Development guide and implementation details

**Archive** (`docs/archive/`):
- [ARCHITECTURE.md](docs/archive/ARCHITECTURE.md) - System design
- [CONTRIBUTING.md](docs/archive/CONTRIBUTING.md) - Contribution guide
- [PERFORMANCE.md](docs/archive/PERFORMANCE.md) - Optimizations
- [PATTERNS.md](docs/archive/PATTERNS.md) - Pattern matching
- [TESTING.md](docs/archive/TESTING.md) - Test strategy
- [TROUBLESHOOTING.md](docs/archive/TROUBLESHOOTING.md) - Common issues


## Technical documentation

See [CLAUDE.md](CLAUDE.md) for architecture and development details.

## Contributing

Issues and discussions are welcome, but reviewing code is time consuming,
so I will likely reject many well-meaning PRs, and re-implement if I agree with the idea.
So if you don't mind the rejection and just care about getting the change in,
PRs are very much encouraged! They are excellent for concrete discussion.
Not every PR needs an issue but it's usually
preferred to reference one or more issues and discussions.
## Demo

zz has an interactive terminal demo:

```bash
# Run the interactive demo
zz demo

# Run in non-interactive mode (for documentation)
zz demo --non-interactive

# Save demo output to file
zz demo --output=demo.md -n
```



## License

Un