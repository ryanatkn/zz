# zz

A modular CLI utility toolkit for common development tasks, starting with directory tree visualization.

## Quick Start

```bash
./zz tree [directory] [max_depth]
```

## Commands

- `tree [directory] [max_depth]` - Display directory tree structure (defaults to current directory)
- `help` - Show available commands

## Examples

```bash
# Current directory tree
./zz tree

# Basic directory tree
./zz tree src/

# Limit depth to 2 levels
./zz tree . 2

# Show help
./zz help
```

## Tree Command Features

- 🌳 Clean tree visualization with Unicode box-drawing characters
- 🚫 Smart filtering (ignores `.git`, `node_modules`, etc.)
- 📏 Configurable depth limiting
- 🎨 Syntax highlighting for ignored/elided content
- ⚡ Fast traversal with robust error handling

## Development

The `./zz` script handles building and running:

```bash
# Development workflow
./zz tree .           # Run tree command
./zz help             # Show help

# Manual build (if needed)
zig build
./zig-out/bin/zz tree <directory>
```

## Architecture

`zz` is designed as a modular CLI toolkit with:
- Command-based architecture for easy extension
- Reusable components (formatters, filters, walkers)
- Clean separation of concerns
- Type-safe configuration handling

Future commands could include file operations, project scaffolding, text processing, and more.

## Building

Requires Zig 0.14+:

```bash
zig build
```