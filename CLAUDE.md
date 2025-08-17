# zz - CLI Utilities

Fast command-line utilities written in Zig for POSIX systems. High-performance filesystem tree visualization, LLM prompt generation, and code formatting.

**Performance is the top priority** - we don't care about backwards compat, always aim for the final best code.

## Platform Support

- **Supported:** Linux, macOS, BSD, and other POSIX-compliant systems
- **Not Supported:** Windows (no plans)

## Environment

```bash
$ zig version
0.14.1
```

**Vendored Dependencies:** All tree-sitter libraries vendored in `deps/` for reliability. See `deps/README.md` for details.

## Project Structure

```
src/
├── cli/                 # Command parsing & execution
├── config/              # Configuration system (ZON-based)
├── lib/                 # Core infrastructure
│   ├── analysis/        # Code analysis & AST caching
│   ├── core/            # Core utilities (io, path, collections)
│   ├── deps/            # Dependency management system
│   ├── filesystem/      # Filesystem abstraction layer
│   ├── languages/       # Language implementations (C-style format_*.zig)
│   │   ├── css/         # CSS support
│   │   ├── html/        # HTML support
│   │   ├── json/        # JSON support
│   │   ├── svelte/      # Svelte support
│   │   ├── typescript/  # TypeScript (modular formatters)
│   │   └── zig/         # Zig (modular formatters)
│   ├── parsing/         # Parser infrastructure
│   └── test/            # Test framework & fixtures
├── prompt/              # LLM prompt generation (AST-based extraction)
├── tree/                # Directory visualization (high-performance)
├── format/              # Code formatting module
├── benchmark/           # Performance benchmarking
└── deps/                # Dependency management CLI
```

For detailed architecture, see [docs/module-architecture.md](docs/module-architecture.md).

## Quick Start

```bash
# Install (User)
$ git clone https://github.com/user/zz
$ cd zz
$ zig build install-user             # Install to ~/.zz/bin/
$ export PATH="$PATH:$HOME/.zz/bin"  # Add to PATH

# Install (System-wide, alternative)
$ zig build -Doptimize=ReleaseFast
$ sudo cp zig-out/bin/zz /usr/local/bin/

# Basic usage
$ zz tree                           # Show directory tree
$ zz prompt "src/**/*.zig"          # Generate LLM prompt
$ zz format config.json --write     # Format file in-place
$ zz deps --list                    # Check dependency status
$ zz deps --generate-docs           # Generate dependency documentation
```

## Commands Overview

### Tree - Directory Visualization
```bash
$ zz tree --format=list             # List format for parsing
$ zz tree --hidden                  # Include hidden files
$ zz tree --max-depth=3             # Limit depth
```
See [docs/tree-features.md](docs/tree-features.md) for details.

### Prompt - LLM Code Extraction
```bash
$ zz prompt --signatures "*.zig"    # Extract function signatures
$ zz prompt --types --docs "*.ts"   # Extract types and docs
$ zz prompt src/                    # Process entire directory
```
See [docs/prompt-features.md](docs/prompt-features.md) for AST extraction features.

### Format - Code Formatting
```bash
$ zz format "**/*.json" --write     # Format all JSON files
$ zz format "src/**/*.ts" --check   # Check formatting (CI)
$ echo '{"a":1}' | zz format --stdin # Format from stdin
```
See [docs/format-features.md](docs/format-features.md) for language support.

### Deps - Dependency Management
```bash
$ zz deps --check                   # Check if updates needed
$ zz deps --update                  # Update dependencies
$ zz deps --force-dep tree-sitter   # Force update specific dep
```
See [docs/deps.md](docs/deps.md) for architecture details.

### Complete Command Reference
See [docs/commands.md](docs/commands.md) for all commands and options.

## Testing & Quality

```bash
$ zig build test                    # Run all tests
$ zig build test -Dtest-filter="pattern"  # Filter tests
$ zig build benchmark               # Run performance benchmarks
```

- Tests use mock filesystem for isolation
- See [docs/testing.md](docs/testing.md) for testing guide
- See [docs/benchmarking.md](docs/benchmarking.md) for performance testing

## Key Features

### Language Support
- **Full AST Support:** Zig, TypeScript, JavaScript, CSS, HTML, JSON, Svelte
- **Real tree-sitter parsing** for semantic code understanding
- **C-style modular formatters** (`format_*.zig` pattern)
- See [docs/language-support.md](docs/language-support.md)

### Performance Optimizations
- Early directory skipping for ignored paths
- Memory pool allocators and arena allocation
- String interning for reduced memory usage
- AST caching with LRU eviction
- Parallel processing where beneficial

### Configuration
- ZON-based configuration (`zz.zon`)
- Gitignore-style pattern support
- Command-specific overrides
- See [docs/configuration.md](docs/configuration.md)

## Development

### Build Options
```bash
$ zig build                         # Debug build
$ zig build -Doptimize=ReleaseFast  # Production build
$ zig build run -- tree             # Development workflow
```

### Tool Preferences
- Always use `rg` (ripgrep) over `grep`/`find`
- Claude Code configured to prefer `rg`
- See `.claude/config.json` for tool configuration

### Contributing Guidelines
1. **Performance first** - optimize for speed
2. **No backwards compatibility** - delete old code aggressively
3. **Test thoroughly** - include edge cases
4. **Document changes** - update CLAUDE.md and README.md
5. **Follow Zig idioms** - more C than C++, no re-exports

See [docs/llm-guidelines.md](docs/llm-guidelines.md) for detailed development philosophy.

## Documentation

### Core Documentation
- [README.md](README.md) - User-facing documentation
- [docs/commands.md](docs/commands.md) - Complete command reference
- [docs/module-architecture.md](docs/module-architecture.md) - System design

### Feature Documentation
- [docs/prompt-features.md](docs/prompt-features.md) - Prompt module details
- [docs/tree-features.md](docs/tree-features.md) - Tree module details
- [docs/format-features.md](docs/format-features.md) - Format module details
- [docs/language-support.md](docs/language-support.md) - Language implementations

### Development Documentation
- [docs/llm-guidelines.md](docs/llm-guidelines.md) - LLM development guidelines
- [docs/development-workflow.md](docs/development-workflow.md) - Development process
- [docs/filesystem-abstraction.md](docs/filesystem-abstraction.md) - FS abstraction

### Implementation Details
- [docs/deps.md](docs/deps.md) - Dependency management system
- [docs/ast-integration.md](docs/ast-integration.md) - AST framework
- [docs/benchmarking.md](docs/benchmarking.md) - Performance testing
- [docs/testing.md](docs/testing.md) - Testing strategy

## Notes

### For Contributors
- Start with high impact, low effort items
- Add tests for all new features
- Benchmark performance impacts
- Keep the Unix philosophy in mind

### For LLMs
See [docs/llm-guidelines.md](docs/llm-guidelines.md) for complete guidelines. Key points:
- Performance is a feature
- Delete old code aggressively, no deprecation, refactor without hesitation
- Test frequently with `zig build run`
- Always update documentation
- Leave `// TODO` comments for unknowns

### Important Files
- `TODO_LANGUAGES.md` - Formatter refactoring history
- `WORKFLOW.md` - Development session notes
- `.claude/config.json` - Claude Code tool preferences

## Current Status

- **378/383 tests passing** (98.7%)
- **C-style formatter architecture** implemented for Zig/TypeScript
- **Production ready** for tree, prompt, and basic formatting
- Active development on advanced formatting features

---

*Remember: Performance is the top priority. Every cycle and byte count.*