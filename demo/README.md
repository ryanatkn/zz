# zz Terminal Demo

An interactive terminal demonstration of zz's language parsing and visualization capabilities.

## Features

This demo showcases zz's ability to parse and display various programming languages in a pure terminal environment:

- **Tree Visualization**: Directory structure with pattern filtering
- **TypeScript Parsing**: Extract interfaces, types, and functions
- **CSS Parsing**: Extract selectors, variables, and rules
- **HTML Parsing**: Extract document structure
- **Svelte Parsing**: Multi-section component analysis
- **Performance Metrics**: Real-time benchmark visualization
- **Pattern Matching**: Glob pattern demonstrations

## Building and Running

```bash
# Build the demo
cd demo
zig build

# Run the interactive demo
zig build run

# Or run directly
./zig-out/bin/zz-demo
```

## Terminal Interface

The demo uses:
- **ANSI escape codes** for colors and formatting
- **Unicode box-drawing characters** for UI elements
- **Terminal-based animations** for progress bars
- **Keyboard navigation** (j/k or arrow keys)

## Navigation

- **↑/↓** or **j/k**: Navigate menu
- **Enter/Space**: Select option
- **q/ESC**: Exit demo

## Architecture

```
demo/
├── src/
│   ├── main.zig        # Main application and menu system
│   ├── renderer.zig    # Terminal rendering utilities
│   ├── showcase.zig    # Demo scenarios
│   └── samples.zig     # Embedded code samples
└── build.zig          # Build configuration
```

## Key Demonstrations

### 1. Tree Visualization
Shows how zz traverses directories with pattern filtering, displaying ignored directories as `[...]` in gray.

### 2. Language Parsing
Demonstrates extraction of:
- TypeScript: interfaces, types, classes, functions
- CSS: variables, selectors, at-rules
- HTML: structure, elements, attributes
- Svelte: script, style, and template sections

### 3. Performance
Real-time visualization of performance metrics:
- Path operations: ~47μs/op (20-30% faster than stdlib)
- String pooling: ~145ns/op
- Pattern matching: ~25ns/op

## Terminal-Only Design

This demo is 100% terminal-based:
- No web technologies used in the demo itself
- Pure POSIX terminal capabilities
- Shows parsing of web languages in terminal context
- Optimized for terminal performance

## Requirements

- Zig 0.14.1 or later
- POSIX-compliant terminal with ANSI color support
- Unicode support for box-drawing characters