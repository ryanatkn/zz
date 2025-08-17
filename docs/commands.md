# Commands Reference

This document provides a comprehensive reference for all `zz` commands and build options.

## Build Commands

```bash
# Build commands (default is Debug mode)
$ zig build                         # Debug build (default)
$ zig build -Doptimize=ReleaseFast  # ReleaseFast | ReleaseSafeFast | ReleaseSmall
$ zig build --use-llvm              # Use LLVM backend

# Development workflow
$ zig build run -- tree [args]          # Run tree command in development
$ zig build run -- prompt [args]        # Run prompt command in development
$ zig build run -- benchmark [args]     # Run benchmarks
$ zig build run -- format [args]        # Run formatter in development
$ zig build run -- demo [args]          # Run demo in development
$ zig build run -- deps [args]          # Run dependency management
```

## Tree Command

Visualizes directory structures with high performance.

```bash
$ zz tree                    # Show current directory tree
$ zz tree /path/to/dir       # Show specific directory
$ zz tree --format=list      # Use list format instead of tree
$ zz tree --hidden           # Include hidden files
$ zz tree --max-depth=3      # Limit depth
```

See [tree-features.md](tree-features.md) for detailed features and options.

## Prompt Command

Generates LLM-optimized prompts from codebases with AST-based extraction.

```bash
$ zz prompt "*.zig"                  # Generate prompt from Zig files
$ zz prompt src/                     # Recursively process directory
$ zz prompt --signatures "*.ts"      # Extract only function signatures
$ zz prompt --types --docs "*.zig"   # Extract types and documentation
$ zz prompt --prepend "Context: " file.txt  # Add context before files
```

Extraction flags:
- `--signatures`: Function/method signatures
- `--types`: Type definitions (structs, enums, unions)
- `--docs`: Documentation comments
- `--imports`: Import statements
- `--errors`: Error handling patterns
- `--tests`: Test blocks
- `--full`: Complete source (default)

See [prompt-features.md](prompt-features.md) for detailed features and glob patterns.

## Format Command

Language-aware code formatting with AST support.

```bash
$ zz format config.json                    # Output formatted JSON to stdout
$ zz format config.json --write            # Format file in-place
$ zz format "src/**/*.json" --check        # Check if files are formatted
$ echo '{"a":1}' | zz format --stdin       # Format from stdin
$ zz format "*.css" --indent-size=2        # Custom indentation
$ zz format --indent-style=tab "*.ts"      # Use tabs for indentation
```

Options:
- `--write`: Format files in-place
- `--check`: Check if files are formatted (exit 1 if not)
- `--stdin`: Read from stdin, write to stdout
- `--indent-size=N`: Configurable indentation (default: 4)
- `--indent-style=space|tab`: Choose indentation style
- `--line-width=N`: Maximum line width (default: 100)

See [format-features.md](format-features.md) for language-specific details.

## Dependency Management

Manage vendored dependencies with type-safe Zig implementation.

```bash
# Show dependency status
$ zz deps --list
╔══════════════════════════════════════════════════════╗
║                   Dependencies                        ║
╠════════════════╦═════════════╦═══════════════════════╣
║ tree-sitter    ║ v0.25.0     ║ Up to date            ║
║ tree-sitter-zig║ main        ║ Needs update          ║
╚════════════════╩═════════════╩═══════════════════════╝

# Check if updates needed (CI-friendly)
$ zz deps --check || echo "Updates needed!"

# Preview changes
$ zz deps --dry-run

# Update operations
$ zz deps --update                  # Update all dependencies
$ zz deps --force                   # Force update all dependencies
$ zz deps --force-dep tree-sitter   # Force update specific dependency

# Build system integration
$ zig build deps-list               # Same as zz deps --list
$ zig build deps-check              # Same as zz deps --check
```

See [deps.md](deps.md) for architecture and configuration details.

## Benchmark Command

Performance benchmarking with multiple output formats.

```bash
$ zz benchmark                      # Run all benchmarks
$ zz benchmark --format=pretty      # Color terminal output
$ zz benchmark --format=json        # JSON output for tooling
$ zz benchmark --format=csv         # CSV for spreadsheets
$ zz benchmark --baseline           # Compare against baseline
$ zig build benchmark               # Save to latest.md, compare baseline
```

See [benchmarking.md](benchmarking.md) for detailed benchmark guide.

## Testing

```bash
$ zig build test                            # Run all tests
$ zig build test -Dtest-filter="pattern"    # Filter tests by pattern
$ TEST_VERBOSE=1 zig build test             # Verbose test output
```

See [testing.md](testing.md) for comprehensive testing guide.

## Help Commands

```bash
$ zz -h                          # Brief help overview
$ zz --help                      # Detailed help with all options
$ zz help                        # Same as --help
$ zz <command> --help            # Command-specific help
```

## Common Workflows

### Format All Code

```bash
# Format all Zig files in src/
$ zz format "src/**/*.zig" --write

# Check formatting in CI
$ zz format "src/**/*.{zig,json}" --check || exit 1
```

### Generate Documentation Prompt

```bash
# Extract signatures and types for documentation
$ zz prompt --signatures --types --docs "src/**/*.zig" > docs.md
```

### Benchmark After Changes

```bash
# Run benchmarks and compare with baseline
$ zz benchmark --baseline --format=pretty
```

### Update Dependencies

```bash
# Check and update if needed
$ zz deps --check && zz deps --update
```

## Environment Variables

- `TEST_VERBOSE=1`: Enable verbose test output
- `DEBUG=1`: Enable debug logging (development builds)

## Exit Codes

- `0`: Success
- `1`: General error or check failure
- `2`: Invalid arguments
- `3`: File not found
- `4`: Permission denied