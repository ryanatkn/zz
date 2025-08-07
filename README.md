# zz

CLI utility toolkit with tree visualization and 2D game featuring modular architecture.

## Usage

```bash
./zz <command> [args...]
```

**Commands:**
- `tree [dir] [depth]` - Directory tree (filters common build/cache dirs)
- `yar` - 2D top-down shooter game with vibrant colors and smooth gameplay
- `help` - Show commands

**Examples:**
```bash
./zz tree          # Current directory
./zz tree src/ 2   # src/ limited to 2 levels
./zz yar           # Play game (mouse + WASD controls)
```

## YAR Game Features

- **Mouse + Keyboard Controls**: Left click to move, right click to shoot, WASD for keyboard movement
- **Vibrant Color Palette**: Non-pastel colors for better visual clarity
- **Obstacle System**: Green blocking obstacles and purple deadly obstacles
- **Smart Enemy AI**: Enemies navigate around obstacles to reach the player
- **Collision Detection**: Precise circle-rectangle and circle-circle collision
- **Modular Architecture**: ECS-ready design with focused, single-responsibility modules

## Architecture

The project uses a modular architecture designed for maintainability and future ECS patterns:

### YAR Game Modules
- **`types.zig`** - Core data structures, constants, and configuration
- **`physics.zig`** - Collision detection, vector math, and spatial utilities  
- **`input.zig`** - Input state management and control abstraction
- **`world.zig`** - World generation, obstacles, and safe spawn positioning
- **`units.zig`** - Unit behavior and management (player, enemies, bullets)
- **`render.zig`** - All drawing operations and visual output
- **`game.zig`** - Core game loop, state management, and system coordination
- **`main.zig`** - Entry point and initialization

### Design Benefits
- **Single Responsibility**: Each module focuses on one clear purpose
- **Flat Hierarchy**: No nested directories to avoid complex dependencies
- **ECS-Ready**: Uses "units" terminology and SOA-friendly patterns
- **Testable**: Input abstraction enables easy unit testing
- **Reusable**: Physics and utility modules work across different games

## Building

```bash
zig build          # Builds to zig-out/bin/zz
./zz help          # Wrapper script auto-builds
```

The `zz` script automatically builds and runs the binary. Game requires Raylib static library in `src/raylib/lib/`.