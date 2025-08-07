# zz - Experimental Software Tools

A Zig project building experimental CLI utilities and 2D games with modular architecture. Features a tree visualization tool and YAR (Yet Another RPG), a vibrant top-down shooter.

## Environment & Dependencies

```bash
$ zig version
0.14.1
```

**Dependencies:**
- Raylib 5.5.0 (static/shared libraries included in `src/raylib/`)
- Linux development environment
- Fish shell (build scripts optimized for fish)

## Project Structure

```
$ ./zz tree
└── .
    ├── .git [...]                      # Git repository metadata
    ├── .zig-cache [...]                # Zig build cache (filtered from tree output)
    ├── src/                            # Source code
    │   ├── raylib/                     # Raylib 5.5.0 library bundle
    │   │   ├── include/                # C header files for FFI
    │   │   │   ├── raylib.h           # Main graphics/window API
    │   │   │   ├── raymath.h          # Vector math and utilities  
    │   │   │   └── rlgl.h             # Low-level OpenGL abstraction
    │   │   ├── lib/                   # Pre-compiled library binaries
    │   │   │   ├── libraylib.a        # Static library (primary)
    │   │   │   ├── libraylib.so       # Shared library symlink
    │   │   │   ├── libraylib.so.5.5.0 # Versioned shared library
    │   │   │   └── libraylib.so.550   # Alternative version symlink
    │   │   ├── CHANGELOG              # Raylib release notes
    │   │   ├── LICENSE                # zlib/libpng license
    │   │   ├── README.md              # Raylib documentation
    │   │   ├── raylib_cheatsheet.txt  # API quick reference
    │   │   └── raymath_cheatsheet.txt # Math functions reference
    │   ├── yar/                       # YAR game module (modular architecture)
    │   │   ├── game.zig              # Core game loop, state management, system coordination
    │   │   ├── input.zig             # Input state management and control abstraction
    │   │   ├── main.zig              # Game entry point and Raylib initialization
    │   │   ├── physics.zig           # Collision detection, vector math, spatial queries
    │   │   ├── raylib.zig            # Raylib FFI bindings and C interop
    │   │   ├── render.zig            # All drawing operations and visual output
    │   │   ├── types.zig             # Core data structures, constants, color palette
    │   │   ├── units.zig             # Unit management and behavior (ECS-ready design)
    │   │   └── world.zig             # World generation, obstacles, safe spawn positioning
    │   └── main.zig                   # CLI entry point with command routing
    ├── zig-out/                       # Build output directory (auto-generated)
    │   ├── bin/                       # Executable binaries
    │   │   └── zz                     # Main CLI executable
    │   └── lib/                       # Compiled libraries
    │       └── libzz.a                # Project static library
    ├── .gitignore [...]               # Git ignore patterns (filtered from tree)
    ├── CLAUDE.md                      # AI assistant development documentation
    ├── README.md                      # User-facing documentation and usage guide
    ├── build.zig                      # Zig build system configuration
    ├── build.zig.zon                  # Package manifest and dependencies
    └── zz                             # Build wrapper script (auto-builds and runs)
```

## Commands & Usage

The `./zz` wrapper script provides convenient access to all commands:

```bash
# Display project tree structure (filters build/cache directories)
$ ./zz tree [directory] [depth]
$ ./zz tree            # Current directory, default depth
$ ./zz tree src/ 2     # src/ directory, max 2 levels deep

# Run the 2D shooter game YAR with mouse + keyboard controls
$ ./zz yar

# Show help and available commands
$ ./zz help

# Direct build commands
$ zig build             # Standard build
$ zig build run         # Build and run
```

## YAR Game Overview

**YAR** (Yet Another RPG) is a vibrant 2D top-down shooter featuring:
- **Dual Control Schemes**: Mouse (left click move, right click shoot) + WASD keyboard movement
- **Vibrant Color Palette**: Non-pastel colors for clear visual distinction
- **Dynamic Obstacle System**: Green blocking obstacles and purple deadly hazards
- **Intelligent Enemy AI**: Pathfinding around obstacles with collision avoidance
- **Precise Collision Detection**: Circle-rectangle and circle-circle collision systems
- **60 FPS Gameplay**: Smooth movement and responsive controls

## Development Guidelines & Architecture

### Core Principles
- **Command-based CLI**: Enum-driven command parsing with extensible architecture
- **Memory Management**: Arena allocators for short-lived data, careful lifetime management
- **Static Linking**: External libraries bundled (see Raylib integration pattern)
- **Error Handling**: Zig error unions for robust error propagation
- **Build Automation**: `./zz` wrapper script handles build + run workflow

### YAR Modular Architecture

YAR uses a **flat, modular design** optimized for maintainability and future ECS/SOA patterns:

#### Module Responsibilities
- **`types.zig`**: Core data structures, game constants, vibrant color palette
- **`physics.zig`**: Collision detection algorithms, vector math, spatial utilities
- **`input.zig`**: Input state management, control abstraction, dual input schemes
- **`world.zig`**: Procedural world generation, obstacle placement, safe spawn logic
- **`units.zig`**: Entity behavior, lifecycle management, enemy AI pathfinding
- **`render.zig`**: Drawing pipeline, visual effects, UI rendering
- **`game.zig`**: Game loop coordination, state transitions, system orchestration
- **`raylib.zig`**: C FFI bindings, memory layout compatibility, API wrappers
- **`main.zig`**: Initialization, window setup, main entry point

#### Design Benefits
- **Single Responsibility**: Each module owns one clear domain
- **Flat Hierarchy**: No nested dependencies, import any module from any other
- **ECS-Ready**: "Units" terminology and SOA-friendly data structures
- **Testable**: Input abstraction enables pure function testing and mocking
- **Reusable**: Physics and math modules work across different game projects
- **Performance**: Minimal indirection, cache-friendly data layouts

### Technical Highlights
- **Collision System**: Circle-rectangle and circle-circle detection with early exits
- **AI Pathfinding**: Vector-based obstacle avoidance with smooth movement
- **Color Design**: Non-pastel palette for accessibility and visual clarity
- **Input Flexibility**: Mouse precision + WASD keyboard alternative controls
- **60 FPS Target**: Frame-rate independent game logic with delta time

## Extending the CLI

### Adding New Commands
1. **Define Command**: Add enum variant to `Command` in `src/main.zig`
2. **Parser Integration**: Update `fromString()` method for command recognition
3. **Implementation**: Add case to main switch statement with command logic
4. **Documentation**: Update help text and command descriptions
5. **Complex Features**: Consider separate modules following YAR architecture patterns

### Example Command Structure
```zig
const Command = enum {
    tree,
    yar,
    help,
    your_new_command, // Add here

    pub fn fromString(str: []const u8) ?Command {
        // Add string matching logic
    }
};
```

## Future Roadmap

- **ECS Migration**: Refactor YAR to full Entity-Component-System architecture
- **Additional Games**: Leverage modular physics/input for new game types  
- **Tree Enhancements**: Add file filtering, size display, git status integration
- **Performance Tools**: Memory profiling, build time analysis
- **Cross-Platform**: Windows and macOS support with platform-specific optimizations