# zz - Experimental Software Tools

A Zig project featuring CLI utilities and games with clean modular architecture.

## Quick Start

```bash
# Install dependencies
zig version  # Requires 0.14.1+

# Build and run
./zz help    # Show available commands
./zz tree    # Display directory structure  
./zz hex     # Play the 2D action RPG
```

## Features

### Tree Visualization
- Recursive directory traversal with customizable depth
- Smart filtering (hides build artifacts, cache directories)
- Clean tree-style output formatting

### Hex Game
- **Hex** - GPU-accelerated 2D top-down action RPG built with SDL3 GPU API
- **Graphics**: Procedural rendering with HLSL shaders, distance field anti-aliasing
- **Performance**: Vulkan/D3D12 backend with procedural vertex generation
- **Rendering**: No texture assets - pure algorithmic shape generation
- **Controls**: Mouse hold-to-move + WASD for direct movement
- **Architecture**: Complete SDL3 GPU pipeline with uniform buffers
- **World**: Multiple entity types (enemies, obstacles, portals, lifestones)
- **Development**: Debug mode for GPU shader testing

## Commands

```bash
./zz tree [directory] [depth]    # Show directory tree
./zz hex                         # Launch 2D action RPG
./zz help                        # Display help
```

## Examples

```bash
# Show current directory structure, 2 levels deep
./zz tree . 2

# Show src directory with default depth  
./zz tree src/

# Play the Hex action RPG
./zz hex
```

## Architecture

- **`src/cli/`** - Command parsing and execution
- **`src/tree/`** - Directory traversal and visualization  
- **`src/hex/`** - GPU-accelerated 2D action RPG with HLSL shaders

### Design Principles
- Single binary with no external runtime dependencies
- Direct function calls (no shell process spawning)
- Clean separation of concerns across modules
- Static linking with bundled libraries

## Game Controls

### Movement
- **Hold Left Mouse**: Move player toward cursor continuously
- **WASD**: Direct movement controls
- **ESC**: Quit game

### Game Elements
- **Blue Circle**: Player character
- **Red Circles**: Enemy entities
- **Green Rectangles**: Blocking obstacles
- **Orange Rectangles**: Deadly hazards
- **Purple Circles**: Portal locations
- **Cyan Circles**: Lifestone pickups

### Development
- Set `DEBUG_MODE = true` in `src/hex/main.zig` for GPU shader testing
- Debug mode shows animated circle test with orbital motion

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
- Linux (X11 libraries for graphics)
- Vulkan or D3D12 support (SDL3 GPU API)
- SDL_shadercross for HLSL shader compilation

## Technical Documentation

For detailed architecture documentation, development guidelines, and implementation details, see **[CLAUDE.md](CLAUDE.md)**.

## License

See individual component licenses in their respective directories.