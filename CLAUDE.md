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

## Project Structure

```
$ ./zz tree
└── .
    ├── .git [...]                      # Git repository metadata
    ├── .zig-cache [...]                # Zig build cache (filtered from tree output)
    ├── src/                            # Source code (modular architecture)
    │   ├── cli/                        # CLI interface module (command-line concerns)
    │   │   ├── command.zig            # Command enumeration and parsing
    │   │   ├── help.zig               # Help text and usage documentation
    │   │   ├── main.zig               # CLI entry point and argument processing
    │   │   └── runner.zig             # Command execution and orchestration
    │   ├── tree/                       # Tree visualization module (directory traversal)
    │   │   ├── config.zig             # Configuration parsing and options
    │   │   ├── entry.zig              # File/directory entry representation
    │   │   ├── filter.zig             # Directory filtering rules and patterns
    │   │   ├── formatter.zig          # Tree output formatting and display
    │   │   ├── main.zig               # Tree command entry point
    │   │   └── walker.zig             # Recursive directory traversal logic
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
    │   │   ├── LICENSE                # zlib/libpng license
    │   │   ├── README.md              # Raylib documentation
    │   │   ├── raylib_cheatsheet.txt  # API quick reference
    │   │   └── raymath_cheatsheet.txt # Math functions reference
    │   ├── yar/                       # YAR game module (clean, consolidated architecture)
    │   │   ├── game.zig              # Complete game implementation with integrated systems
    │   │   └── raylib.zig            # Raylib FFI bindings and C interop
    │   └── main.zig                   # Minimal application entry point
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

The `./zz` wrapper script auto-builds and provides convenient access to the `zig-out/bin/zz` binary:

```bash
# Display project tree structure (filters build/cache directories)
$ ./zz tree [directory] [depth]
$ ./zz tree            # Current directory, default depth
$ ./zz tree src/ 2     # src/ directory, max 2 levels deep

# Run the 2D shooter game YAR with mouse + keyboard controls
$ ./zz yar

# Show help and available commands
$ ./zz help

# Direct build commands (without wrapper script)
$ zig build             # Standard build
$ ./zig-out/bin/zz      # Run binary directly after build
```

## YAR Game Overview

**YAR** (Yet Another RPG) is a vibrant 2D top-down shooter featuring:
- **Dual Control Schemes**: Mouse (left click move, right click shoot) + WASD keyboard movement
- **Vibrant Color Palette**: Non-pastel colors for clear visual distinction
- **Dynamic Obstacle System**: Green blocking obstacles (4x larger) and purple deadly hazards
- **Intelligent Enemy AI**: Pathfinding around obstacles with collision avoidance
- **Precise Collision Detection**: Circle-rectangle and circle-circle collision systems
- **Dynamic Restart**: R key regenerates entire world with new obstacle layouts
- **Integrated Runtime**: No shell process spawning - runs directly within CLI binary

## Development Guidelines & Architecture

### Core Principles
- **Modular Architecture**: Clean separation of concerns into domain-specific modules
- **CLI Module**: Command parsing, help text, and execution orchestration
- **Tree Module**: Directory traversal, filtering, and visualization logic
- **YAR Module**: Consolidated game implementation with runtime integration
- **Memory Management**: Arena allocators for short-lived data, careful lifetime management
- **Static Linking**: External libraries bundled with build system integration
- **Error Handling**: Zig error unions for robust error propagation
- **No Shell Dependencies**: All components run within single binary process

### Architecture Benefits
- **Single Responsibility**: Each module owns one clear domain
- **Runtime Integration**: Game runs as library function, not separate process
- **Consolidated Logic**: YAR combines all systems in single, maintainable module
- **Performance**: No process spawning overhead, minimal indirection

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

## Future Roadmap

- **Module Expansion**: Consider extracting reusable components (collision, math) from YAR
- **Additional Games**: Leverage consolidated game patterns for new game types  
- **Tree Enhancements**: Add file filtering, size display, git status integration
- **Performance Tools**: Memory profiling, build time analysis
- **Cross-Platform**: Windows and macOS support with platform-specific optimizations
- **Build System**: Further integrate raylib dependencies for smoother development