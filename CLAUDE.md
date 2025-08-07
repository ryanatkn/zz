# zz - Experimental Software Tools

A Zig project for building experimental CLI for experimental tools and games.
Uses command-based architecture for easy extension.

## Environment

```bash
$ zig version
0.14.1
```

## Structure

```
$ ./zz tree
└── .
    ├── .git [...]                      # Git repository metadata
    ├── .zig-cache [...]                # Zig build cache
    ├── src
    │   ├── raylib                      # Raylib library files
    │   │   ├── include                 # C header files
    │   │   │   ├── raylib.h           # Main raylib graphics API
    │   │   │   ├── raymath.h          # Math utilities
    │   │   │   └── rlgl.h             # OpenGL abstraction layer
    │   │   ├── lib                    # Compiled library binaries
    │   │   │   ├── libraylib.a        # Static library
    │   │   │   ├── libraylib.so       # Shared library symlink
    │   │   │   ├── libraylib.so.5.5.0 # Versioned shared library
    │   │   │   └── libraylib.so.550   # Version symlink
    │   │   ├── CHANGELOG              # Raylib version history
    │   │   ├── LICENSE                # Raylib license
    │   │   ├── README.md              # Raylib documentation
    │   │   ├── raylib_cheatsheet.txt  # Quick reference guide
    │   │   └── raymath_cheatsheet.txt # Math functions reference
    │   ├── yar                        # 2D game module
    │   │   ├── main.zig              # Game logic and rendering
    │   │   └── raylib.zig            # Raylib FFI bindings
    │   └── main.zig                   # Main CLI entry point with command routing
    ├── zig-out                        # Build output directory
    │   ├── bin                        # Executable binaries
    │   │   └── zz                     # Main CLI executable
    │   └── lib                        # Compiled libraries
    │       └── libzz.a                # Static library output
    ├── .gitignore [...]               # Git ignore patterns
    ├── CLAUDE.md                      # AI assistant documentation
    ├── README.md                      # User documentation
    ├── build.zig                      # Build configuration
    ├── build.zig.zon                  # Package manifest
    └── zz                             # Build wrapper script
```

## Usage

The `./zz` wrapper script provides convenient access to all commands:

```bash
# Display project tree structure
$ ./zz tree

# Run the 2D shooter game (YAR - Yet Another RPG)
$ ./zz yar

# Build the project
$ ./zz build

# Clean build artifacts
$ ./zz clean
```

## Development Guidelines

- Commands are enum-based with string parsing
- Use allocators for dynamic memory (prefer arena for short-lived data)
- External libraries via static linking (see Raylib integration)
- Error handling with Zig's error unions
- Build via `./zz` wrapper script for convenience

## Adding New Commands

1. Add enum variant to `Command` in `main.zig`
2. Update `fromString()` parser
3. Add case to main switch statement
4. Implement command logic (consider separate modules for complex features)