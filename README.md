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
- **Hex** - Vibrant 2D top-down action RPG built with SDL3
- **World**: Interconnected locations with portal system
- **Graphics**: SDL3 rendering with custom circle drawing and primitives
- **Controls**: Mouse (move/shoot) + WASD, Space (pause), R/T/Y (resets)
- **Gameplay**: Green obstacles (blocking), purple hazards (deadly), orange portals (transitions)
- **Enemy AI**: Intelligent aggro-based targeting with pathfinding
- **Reset System**: Multiple reset levels (resurrect, scene reset, full restart)
- **Data**: Uses `game_data.zon` configuration for scenes and game objects
- **Performance**: Optimized for SDL3's rendering pipeline

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
- **`src/hex/`** - Simple SDL3-based puzzle game

### Design Principles
- Single binary with no external runtime dependencies
- Direct function calls (no shell process spawning)
- Clean separation of concerns across modules
- Static linking with bundled libraries

## Game Controls

### Movement & Combat
- **Left Click**: Move player toward mouse cursor
- **Right Click**: Shoot toward mouse cursor  
- **WASD/Arrow Keys**: Alternative movement controls

### Game Management
- **R Key**: Resurrect player (preserve world state)
- **T Key**: Reset current scene (respawn enemies in current location)
- **Y Key**: Full restart (reset entire game world)
- **Space**: Pause/unpause game
- **[/] Keys**: Speed control (0.25x - 4x)
- **ESC**: Quit game

### Visual Indicators
- **Orange Portals**: Transitions between locations (shape indicates destination type)
- **Border Colors**: Yellow/orange (paused), green/teal (victory), red (death)

## Development

```bash
# Build only
zig build

# Run directly  
./zig-out/bin/zz [command]

# Development build with debug info
zig build -Doptimize=Debug
```

## Requirements

- Zig 0.14.1+
- Linux (X11 libraries for graphics)
- OpenGL support

## Technical Documentation

For detailed architecture documentation, development guidelines, and implementation details, see **[CLAUDE.md](CLAUDE.md)**.

## License

See individual component licenses in their respective directories.