# zz - Experimental Software Tools

A Zig project building CLI utilities and a 2D action RPG with modular architecture. Features a tree visualization tool and YAR (Yet Another RPG), a vibrant top-down action game.

## Environment & Dependencies

```bash
$ zig version
0.14.1
```

**Dependencies:**
- Raylib 5.5.0 (static/shared libraries included in `src/raylib/`)
- Linux development environment

## Project Structure

```
$ ./zz tree
└── .
    ├── .claude [...]                  # Claude Code configuration directory
    ├── .git [...]                     # Git repository metadata
    ├── .zig-cache [...]               # Zig build cache (filtered from tree output)
    ├── src                            # Source code (modular architecture)
    │   ├── cli                        # CLI interface module (command-line concerns)
    │   │   ├── command.zig           # Command enumeration and parsing
    │   │   ├── help.zig              # Help text and usage documentation
    │   │   ├── main.zig              # CLI entry point and argument processing
    │   │   └── runner.zig            # Command execution and orchestration
    │   ├── raylib                     # Raylib 5.5.0 library bundle
    │   │   ├── include               # C header files for FFI
    │   │   │   ├── raylib.h          # Main graphics/window API
    │   │   │   ├── raymath.h         # Vector math and utilities  
    │   │   │   └── rlgl.h            # Low-level OpenGL abstraction
    │   │   ├── lib                   # Pre-compiled library binaries
    │   │   │   ├── libraylib.a       # Static library (primary)
    │   │   │   ├── libraylib.so      # Shared library symlink
    │   │   │   ├── libraylib.so.5.5.0 # Versioned shared library
    │   │   │   └── libraylib.so.550  # Alternative version symlink
    │   │   ├── LICENSE               # zlib/libpng license
    │   │   ├── README.md             # Raylib documentation
    │   │   ├── raylib_cheatsheet.txt # API quick reference
    │   │   └── raymath_cheatsheet.txt # Math functions reference
    │   ├── tree                       # Tree visualization module (directory traversal)
    │   │   ├── config.zig            # Configuration parsing and options
    │   │   ├── entry.zig             # File/directory entry representation
    │   │   ├── filter.zig            # Directory filtering rules and patterns
    │   │   ├── formatter.zig         # Tree output formatting and display
    │   │   ├── main.zig              # Tree command entry point
    │   │   └── walker.zig            # Recursive directory traversal logic
    │   ├── yar                        # YAR game module (modular raylib bindings)
    │   │   ├── CLAUDE.md             # Game-specific documentation and concepts
    │   │   ├── game.zig              # Complete game implementation with aggro/targeting systems
    │   │   ├── game_data.zon         # Data-driven level/scene configuration
    │   │   ├── raylib_audio.zig      # Audio system bindings
    │   │   ├── raylib_core.zig       # Core window/input bindings
    │   │   ├── raylib_models.zig     # 3D model bindings
    │   │   ├── raylib_shapes.zig     # 2D shape drawing bindings
    │   │   ├── raylib_text.zig       # Text rendering bindings
    │   │   ├── raylib_textures.zig   # Texture loading bindings
    │   │   └── raylib_types.zig      # Common type definitions
    │   └── main.zig                   # Minimal application entry point
    ├── zig-out                        # Build output directory (auto-generated)
    │   ├── bin                        # Executable binaries
    │   │   └── zz                     # Main CLI executable
    │   └── lib                        # Compiled libraries
    │       └── libzz.a                # Project static library
    ├── .gitignore                     # Git ignore patterns
    ├── CLAUDE.md                      # AI assistant development documentation
    ├── README.md                      # User-facing documentation and usage guide
    ├── build.zig                      # Zig build system configuration
    ├── build.zig.zon                  # Package manifest and dependencies
    └── zz                             # Build wrapper script (auto-builds and runs)
```

## Commands & Usage

The `./zz` wrapper script auto-builds and provides convenient access to the `zig-out/bin/zz` binary:

```bash
# Display project tree structure (filters build/cache directories)
$ ./zz tree [directory] [depth]
$ ./zz tree            # Current directory, default depth
$ ./zz tree src/ 2     # src/ directory, max 2 levels deep

# Run the 2D action RPG YAR with intelligent enemy AI
$ ./zz yar

# Show help and available commands  
$ ./zz help

# Direct build commands (without wrapper script)
$ zig build             # Standard build
$ ./zig-out/bin/zz      # Run binary directly after build
```

## Notes to LLMs

- don't run tests, I'll do that myself

## YAR Game Overview

**YAR** (Yet Another RPG) is a vibrant 2D top-down action RPG featuring:
- **Interconnected World**: Multiple locations with unique layouts and enemy spawns
- **Portal System**: Orange portals (circle/triangle/square shapes) for scene transitions
- **Intelligent Enemy AI**: Aggro-based targeting system with pathfinding and collision avoidance
- **Flexible Reset System**: Multiple reset levels (resurrect, scene reset, full restart)
- **Dynamic Visual Effects**: Color-cycling borders for different game states (pause, victory, death)
- **Dual Control Schemes**: Mouse (left click move, right click shoot) + WASD keyboard movement
- **Vibrant Color Palette**: Non-pastel colors for clear visual distinction
- **Obstacle Systems**: Green blocking obstacles and purple deadly hazards
- **Integrated Runtime**: No shell process spawning - runs directly within CLI binary

## Development Guidelines & Architecture

### Core Principles
- **Modular Architecture**: Clean separation of concerns into domain-specific modules
- **CLI Module**: Command parsing, help text, and execution orchestration
- **Tree Module**: Directory traversal, filtering, and visualization logic
- **YAR Module**: Consolidated game implementation with aggro/targeting system and scene management
- **Memory Management**: Arena allocators for short-lived data, careful lifetime management
- **Static Linking**: External libraries bundled with build system integration
- **Error Handling**: Zig error unions for robust error propagation
- **No Shell Dependencies**: All components run within single binary process

### Architecture Benefits
- **Single Responsibility**: Each module owns one clear domain
- **Runtime Integration**: Game runs as library function, not separate process
- **Consolidated Logic**: YAR combines all systems in single, maintainable module with data-driven configuration
- **Performance**: No process spawning overhead, minimal indirection

## YAR Game Systems

### Aggro/Targeting System
- **`aggroTarget`**: When set, enemies chase this position at full speed
- **`friendlyTarget`**: Reserved for future healing/support mechanics  
- **Dynamic Behavior**: Enemies switch between chasing player and returning home based on game state

### Scene Management
- **Multi-Scene World**: 7 interconnected scenes (Overworld + 6 dungeons) loaded from `game_data.zon`
- **Portal System**: Scene transitions via colored shape-coded portals  
- **Per-Scene Scaling**: Player and enemy sizes adjust based on scene configuration
- **State Persistence**: Enemy states preserved across scene transitions

### Reset System Hierarchy
1. **Resurrect (R key/Mouse click)**: Player respawns at original location, world state preserved
2. **Scene Reset (T key)**: Current scene enemies respawn, other scenes unchanged  
3. **Full Restart (Y key)**: Complete world reset, all scenes restored to initial state

### Visual Feedback
- **Pause State**: Yellow-orange cycling border (60°-30° hue range)
- **Victory State**: Green-teal cycling border (120°-180° hue range)  
- **Death State**: Red pulsing border with dynamic intensity

## Extending the CLI

### Adding New Commands
1. Add enum variant to `Command` in `src/cli/command.zig`
2. Update `fromString()` method for command recognition  
3. Update help text in `src/cli/help.zig`
4. Add case to switch statement in `src/cli/runner.zig`
5. Create module directory following `src/tree/` or `src/yar/` patterns

### Module Guidelines
- Simple commands: implement in `src/cli/runner.zig`
- Complex features: dedicated module with `run(allocator, args)` function
- Prefer direct function calls over shell processes

## Coding Philosophy & Performance Goals

### Core Principles

- **Idiomatic Zig**: Leverage comptime, explicit memory management, zero-cost abstractions
- **Frame Budget First**: Optimize for consistent 144+ FPS - every microsecond counts
- **Memory for Speed**: Trade RAM for CPU cycles - precompute, cache, batch
- **Predictable Performance**: No hot path allocations, compile-time over runtime
- **Fail Fast**: Debug assertions, explicit error handling, no silent failures
- **One Best Way**: Don't have two ways to do the same thing unless
    there are meaningful differences for performance
    or clear DX wins without downsides,
    so for example don't re-export modules for convenience

### Performance Guidelines

- **Hot Path Priority**: Game loop, rendering, input processing get optimization focus
- **Data-Oriented Design**: Cache-efficient layouts, minimize pointer chasing
- **Batch Operations**: Group work to reduce overhead, improve cache locality
- **Arena Allocation**: Frame-scoped arenas, minimize general allocator pressure
- **Static Over Dynamic**: Compile-time sizes, avoid dispatch in critical sections
- **Measure First**: Profile before optimizing, validate assumptions with benchmarks

### Real-Time Constraints

- **No Game Loop Allocations**: All memory from init/loading
- **Bounded Operations**: Predictable worst-case performance
- **Cache-Friendly Layouts**: Pack data, align for SIMD
- **Minimal Indirection**: Direct access over pointer traversals
- **Lock-Free**: Avoid synchronization primitives in hot paths

### Zig-Specific Optimizations

- **Comptime Everything**: Type generation, configuration, data processing
- **Tagged Unions Over Vtables**: Enums with payloads instead of polymorphism
- **Packed Structs**: Tight layouts for C interop and cache optimization
- **Error Unions**: Avoid error paths in performance-critical code
- **SIMD**: Vector types for parallel math
- **Zero Runtime Cost**: `@bitCast`, `@intCast`, `@ptrCast` for type punning

## Future Roadmap

- **Module Expansion**: Consider extracting reusable components (collision, math) from YAR
- **Additional Games**: Leverage consolidated game patterns for new game types  
- **Tree Enhancements**: Add file filtering, size display, git status integration
- **Performance Tools**: Memory profiling, build time analysis
- **Cross-Platform**: Windows and macOS support with platform-specific optimizations
- **Build System**: Further integrate raylib dependencies for smoother development