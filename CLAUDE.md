# zz - Experimental Software Tools

CLI utilities and games in Zig. Filesystem tree visualization + Hex 2D action RPG (SDL3).

## Environment

```bash
$ zig version
0.14.1
```

Dependencies: SDL3 (auto-fetched)

## Project Structure

```
└── .
    ├── .claude [...]                  # Claude Code configuration directory
    ├── .git [...]                     # Git repository metadata
    ├── .zig-cache [...]               # Zig build cache (filtered from tree output)
    ├── src                            # Source code (modular architecture)
    │   ├── cli                        # CLI interface module (command-line concerns)
    │   │   ├── command.zig            # Command enumeration and parsing
    │   │   ├── help.zig               # Help text and usage documentation
    │   │   ├── main.zig               # CLI entry point and argument processing
    │   │   └── runner.zig             # Command execution and orchestration
    │   ├── hex                        # Hex game module (2D action RPG)
    │   │   ├── CLAUDE.md              # Game-specific documentation and SDL3 concepts  
    │   │   ├── borders.zig            # Screen border system (iris wipe, status borders)
    │   │   ├── game.zig               # SDL3 game implementation with complete game systems
    │   │   ├── game_data.zon          # Data-driven level/scene configuration
    │   │   ├── hud.zig                # HUD system (FPS counter, bitmap font, toggleable)
    │   │   ├── main.zig               # SDL3 application entry point
    │   │   ├── types.zig              # Shared game types (Vec2, Color)
    │   │   └── visuals.zig            # Visual effects system (player spawn, portals)
    │   ├── tree                       # Tree visualization module (directory traversal)
    │   │   ├── config.zig             # Configuration parsing and options
    │   │   ├── entry.zig              # File/directory entry representation
    │   │   ├── filter.zig             # Directory filtering rules and patterns
    │   │   ├── formatter.zig          # Tree output formatting and display
    │   │   ├── main.zig               # Tree command entry point
    │   │   └── walker.zig             # Recursive directory traversal logic
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

## Commands

```bash
$ ./zz tree [dir] [depth]    # Directory tree
$ ./zz hex                   # 2D action RPG
$ ./zz help                  # Command list
```

## Hex Game

**Controls:** Left click = move, Right click = shoot, WASD = alt movement  
**Reset levels:** R = resurrect, T = scene reset, Y = full restart  
**HUD:** ` (backtick) = toggle FPS counter and other HUD elements

- 7 interconnected scenes (overworld + 6 dungeons)
- Orange portals for scene transitions (shapes indicate destination)
- Aggro system: enemies chase player, return home when dead
- Scene-based scaling: smaller sprites in overworld for "outdoor" feel

## Performance Tips

**Hot Paths (game loop, rendering, collision):**
- Replace `sqrt(dx² + dy²) < r` with `dx² + dy² < r²` (eliminates sqrt)
- Cache array pointers: `const enemies = &scene.enemies;`
- Pre-compute repeated values: `const r_sq = r * r;`
- Batch by color/type to minimize SDL state changes

**Memory:**
- Arena allocators for frame-scoped data
- Pre-allocate buffers, zero game loop allocations
- Pack structs, align for cache lines

**SDL3 Specifics:**
- Cache last `SDL_SetRenderDrawColor` call to avoid redundant state changes
- Use integer math in loops, convert to float only for SDL calls
- Batch similar draw operations together

## Module Structure

- **CLI Module:** `src/cli/` - command parsing and orchestration
- **Tree Module:** `src/tree/` - directory traversal and visualization  
- **Hex Module:** `src/hex/` - complete SDL3 game with modular architecture:
  - `game.zig` - core game logic and SDL integration
  - `borders.zig` - screen border effects (iris wipe, status indicators)
  - `hud.zig` - heads-up display (FPS counter, bitmap font system)
  - `visuals.zig` - visual effects (particle systems, ambient effects)
  - `types.zig` - shared data structures

**Adding Commands:**
1. Add to `Command` enum in `src/cli/command.zig`
2. Update `fromString()` and help text
3. Add handler in `src/cli/runner.zig`
4. Complex features get dedicated module with `run(allocator, args)`

## Notes to LLMs

- Don't run tests, user handles testing
- Prefer editing existing files over creating new ones
- Use concrete performance wins over generalized advice
- Less is more