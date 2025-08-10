# zz - CLI Utilities

Fast command-line utilities written in Zig with zero dependencies.

## Quick Start

```bash
# Check requirements
zig version  # Requires 0.14.1+

# Build and run
./zz         # Show current directory tree
./zz help    # Show available commands
./zz tree    # Display directory structure
```

## Features

### Tree Visualization
- High-performance directory traversal
- Smart filtering (hides build artifacts, cache directories)
- Clean tree-style output formatting
- Configurable depth limits
- .gitignore-style pattern matching

## Commands

```bash
./zz tree [directory] [depth]    # Show directory tree
./zz help                        # Display help
```

## Examples

```bash
# Show current directory structure
./zz tree

# Show current directory, 2 levels deep
./zz tree . 2

# Show src directory with default depth  
./zz tree src/
```

## Architecture

- **`src/cli/`** - Command parsing and execution
- **`src/tree/`** - Directory traversal and visualization

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
# Run tree module tests
zig test src/tree/test.zig
```

## Requirements

- Zig 0.14.1+
- Any OS (Linux, macOS, Windows)

## Technical Documentation

For detailed architecture documentation, development guidelines, and implementation details, see **[CLAUDE.md](CLAUDE.md)**.

## License

See individual component licenses in their respective directories.