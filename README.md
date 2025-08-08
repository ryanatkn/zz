# zz - Experimental Software Tools

A Zig project featuring CLI utilities and a 2D action RPG with clean modular architecture.

## Quick Start

```bash
# Install dependencies
zig version  # Requires 0.14.1+

# Build and run
./zz help    # Show available commands
./zz tree    # Display directory structure  
./zz yar     # Play the 2D shooter game
```

## Features

### Tree Visualization
- Recursive directory traversal with customizable depth
- Smart filtering (hides build artifacts, cache directories)
- Clean tree-style output formatting

### YAR Game
- **YAR** (Yet Another RPG) - Vibrant 2D top-down action RPG
- **World**: Interconnected locations with portal system
- **Controls**: Mouse (move + shoot) or WASD + mouse
- **Gameplay**: Green obstacles (blocking), purple hazards (deadly), orange portals (transitions)
- **Enemy AI**: Intelligent aggro-based targeting with pathfinding
- **Reset System**: Multiple reset levels (resurrect, scene reset, full restart)
- **Performance**: 144 FPS target with smooth gameplay

## Commands

```bash
./zz tree [directory] [depth]    # Show directory tree
./zz yar                         # Launch 2D shooter
./zz help                        # Display help
```

## Examples

```bash
# Show current directory structure, 2 levels deep
./zz tree . 2

# Show src directory with default depth  
./zz tree src/

# Play the game
./zz yar
```

## Architecture

- **`src/cli/`** - Command parsing and execution
- **`src/tree/`** - Directory traversal and visualization  
- **`src/yar/`** - Consolidated 2D game implementation
- **`src/raylib/`** - Graphics library (bundled)

### Design Principles
- Single binary with no external runtime dependencies
- Direct function calls (no shell process spawning)
- Clean separation of concerns across modules
- Static linking with bundled libraries

## Game Controls (YAR)

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