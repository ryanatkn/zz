# zz

> ⚠️ AI slop code and docs, is unstable and full of lies

zz is a CLI in Zig written by Claude Code and designed by people.
For the companion GUI see [Zzz](https://github.com/ryanatkn/zzz).

> **status**: [vibe-engineered](./docs/vibe-engineering.md) slop level 1

Fast command-line utilities for exploring and understanding codebases. Built on a **Pure Zig language tooling library** featuring native AST parsing, code formatting, and semantic analysis.

**🚀 Architecture Evolution**: We're replacing tree-sitter with a Pure Zig grammar system. See [TODO_PURE_ZIG_ROADMAP.md](TODO_PURE_ZIG_ROADMAP.md) for details.

**Key Features:**
- 🔍 **Semantic code extraction** - Extract functions, types, and docs using pure Zig AST parsing
- 🌳 **Smart directory trees** - Fast traversal with gitignore support
- 📝 **LLM prompt generation** - Create context-aware prompts from your codebase
- 🎨 **Code formatting** - AST-based formatting for multiple languages
- 💬 **Modern echo** - Fast text output with JSON escaping and colors
- 📚 **Language tooling library** - Reusable Zig modules for parsers, ASTs, and analysis
- ⚡ **High performance** - Pure Zig, no FFI overhead

## Quick Start

```bash
# Explore a codebase
zz tree                                  # Visualize project structure
zz prompt "src/**/*.ts" --signatures     # Extract TypeScript function signatures
zz prompt src/ --types --docs            # Extract types and documentation

# Format code
zz format config.json --write            # Format JSON in-place
zz format "*.css" --check                # Check CSS formatting

# Text output
zz echo --json 'Path: C:\file'          # JSON-escaped output
zz echo --color=red --bold "Error!"     # Colored terminal output
zz echo --repeat=1000 "test" | wc -l    # Generate test data

# Manage dependencies
zz deps --list                           # Check dependency status
zz deps --check                          # CI-friendly update check

# Interactive demo
zz demo                                  # See zz in action
```

## Installation

Requires [Zig](https://ziglang.org/) 0.14.1 or later.

```bash
# Clone and build
git clone https://github.com/ryanatkn/zz.git
cd zz

# Install to ~/.zz/bin (recommended)
zig build install-user -Doptimize=ReleaseFast

# Add to PATH
echo 'export PATH="$HOME/.zz/bin:$PATH"' >> ~/.bashrc  # or ~/.zshrc
```

## Commands

### `zz prompt` - Generate LLM prompts from code

Extract specific code elements using AST parsing:

```bash
zz prompt "src/**/*.ts" --signatures     # Function signatures only
zz prompt src/ --types --docs            # Types and documentation
zz prompt app.ts --imports --errors      # Dependencies and error handling
zz prompt . --full                       # Everything (default)
```

**Supported languages:** TypeScript, CSS, HTML, JSON, Zig, Svelte

**Extraction flags:**
- `--signatures` - Functions and methods
- `--types` - Type definitions, interfaces, structs
- `--docs` - Documentation comments
- `--imports` - Import statements
- `--errors` - Error handling patterns
- `--tests` - Test blocks
- `--structure` - Code structure outline
- `--full` - Complete source (default)

### `zz tree` - Visualize directory structure

```bash
zz tree                    # Current directory
zz tree src/ 2             # Specific directory, max depth 2
zz tree --format=list      # Flat list instead of tree
zz tree --no-gitignore     # Include gitignored files
```

### `zz format` - Format code files

```bash
zz format config.json                    # Output formatted to stdout
zz format config.json --write            # Format in-place
zz format "src/**/*.json" --check        # Check if formatted
echo '{"a":1}' | zz format --stdin       # Format from stdin
```

**Supported:** JSON, CSS, HTML, Zig (via `zig fmt`)

### `zz benchmark` - Performance testing

```bash
zz benchmark --format=pretty              # Colored terminal output
zz benchmark --format=json                # Machine-readable results
zz benchmark --baseline=old.md            # Compare with baseline
```

### `zz demo` - Interactive demonstration

```bash
zz demo                      # Interactive terminal demo
zz demo --non-interactive    # Script-friendly output
```

### `zz deps` - Manage vendored dependencies

```bash
zz deps --list               # Show all dependencies and their status
zz deps --check              # Check if updates needed (CI-friendly)
zz deps --dry-run            # Preview what would be updated
zz deps --help               # Show detailed help
```

**Features:**
- Track 9 vendored tree-sitter dependencies
- Version checking with semantic versioning
- CI-friendly exit codes (1 if updates needed)
- Colored status output
- Lock file support for concurrent safety

## Configuration

### `zz.zon` - General configuration

Create `zz.zon` in your project root:

```zon
.{
    // Extend or replace default ignore patterns
    .base_patterns = "extend",
    
    // Additional patterns to ignore
    .ignored_patterns = .{
        "vendor",
        "*.log",
    },
    
    // Files to completely hide
    .hidden_files = .{
        ".env",
    },
    
    // Gitignore support (default: true)
    .respect_gitignore = true,
}
```

### `deps.zon` - Dependency configuration

Manage vendored dependencies:

```zon
.{
    .dependencies = .{
        .@"tree-sitter" = .{
            .url = "https://github.com/tree-sitter/tree-sitter.git",
            .version = "v0.25.0",
            .remove_files = &.{ "build.zig", "build.zig.zon" },
        },
        // ... more dependencies
    },
    .settings = .{
        .deps_dir = "deps",
        .backup_enabled = true,
    },
}
```

## Examples

### Generate focused prompts for LLMs

```bash
# Extract TypeScript interfaces and function signatures
zz prompt "src/**/*.ts" --signatures --types

# Get CSS structure for refactoring
zz prompt "styles/*.css" --structure

# Create comprehensive documentation prompt
zz prompt src/ docs/ --docs --types
```

### Explore project structure

```bash
# Quick overview
zz tree --format=tree

# Find all test files
zz tree --format=list | grep test

# See everything including hidden files
zz tree --no-gitignore --show-hidden
```

### Format code consistently

```bash
# Check all JSON files
zz format "**/*.json" --check

# Format with custom settings
zz format style.css --indent-size=2 --write
```

## Documentation

- [**Development Guide**](CLAUDE.md) - Architecture and contributing
- [**Module Architecture**](docs/module-architecture.md) - System design
- [**Language Support**](docs/language-support.md) - AST extraction details
- [**Configuration**](docs/configuration.md) - Full configuration options
- [**Dependency Management**](docs/deps.md) - Managing vendored dependencies
- [**Testing**](docs/testing.md) - Running tests
- [**Benchmarking**](docs/benchmarking.md) - Performance testing

## Development

```bash
# Run tests
zig build test
zig build test -Dtest-filter="tree"

# Run benchmarks
zig build benchmark                      # Run and save results
zig build benchmark-baseline             # Create baseline

# Development commands
zig build run -- tree                    # Run tree command
zig build run -- prompt src/             # Run prompt command
```

## Platform Support

- ✅ Linux, macOS, BSD (all POSIX systems)
- ❌ Windows (no plans for support)

## Performance

- Optimized path operations for POSIX
- AST caching with incremental updates
- Memory pooling and arena allocators
- Fast pattern matching with gitignore support

## Contributing

Issues and discussions and **deleted code** are all very welcome!
PRs are encouraged for concrete discussion, 
but I will probably re-implement rather than merge
most code additions for various reasons (including security).

See [CLAUDE.md](CLAUDE.md) for development guidelines.

## Related Projects

- [Zzz](https://github.com/ryanatkn/zzz) - GUI companion for zz

## License

[Unlicense](./license) (public domain)

## Credits

Built with:
- [Zig](https://ziglang.org/) - Systems programming language
- [Claude Code](https://claude.ai/code) - AI-assisted development
- Pure Zig grammar system (replacing tree-sitter)