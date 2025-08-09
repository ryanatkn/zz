# Hex

A vibrant 2D topdown action RPG in Zig and SDL3.

## Module Structure

```
$ ./zz tree src/hex
└── hex
    ├── CLAUDE.md             # Game-specific documentation and concepts
    ├── borders.zig           # Screen border effects system
    ├── game.zig              # SDL3 game implementation
    ├── game_data.zon         # Data-driven scene/level configuration
    ├── hud.zig               # HUD system (FPS counter, bitmap fonts)
    ├── main.zig              # SDL3 entry point and application lifecycle
    ├── types.zig             # Shared game types (Vec2, Color)
    └── visuals.zig           # Visual effects system
```

## Architecture Overview

**Separation of Concerns**
- `main.zig`: SDL3 application lifecycle, window management, and main event loop entry
- `game.zig`: Core game logic, state management, and SDL3 integration
- `borders.zig`: Screen border system (iris wipe effects, game status indicators)  
- `hud.zig`: Heads-up display (FPS counter, bitmap font rendering, toggleable UI)
- `visuals.zig`: Visual effects system (particle effects, ambient animations)
- `types.zig`: Shared data structures (Vec2, Color, common game types)
- `game_data.zon`: Data-driven configuration for scenes, enemies, obstacles, and portals

**SDL3 Integration**
- Uses SDL3's modern application model with `SDL_RunApp` and callbacks
- Implements custom circle and shape drawing using SDL3 primitives
- Handles input through SDL3 event system
- Manages rendering through SDL3 renderer API

**Modular Architecture**
- `borders.zig`: Declarative border stack system with animated effects
  - BorderSpec/BorderStack for layered borders with different widths and colors
  - Iris wipe effect for resurrection transitions
  - Game state borders (paused = gold pulse, dead = red pulse)
- `hud.zig`: Self-contained heads-up display system
  - 5x7 bitmap font for pixel-perfect text rendering
  - FPS counter with proper timing using SDL performance counters
  - Toggleable visibility with backtick key
- `visuals.zig`: Particle and ambient effect system
  - Player spawn/transition effects with multiple animated rings
  - Portal ambient effects with slow pulsing fields
  - Lifestone effects (dormant vs attuned states)

## Core Game Concepts

**Player**
- Blue circle that moves via mouse (left-click) or WASD/arrows  
- Shoots yellow bullets toward mouse cursor (right-click)
- Dies on contact with enemies or deadly obstacles
- Can resurrect in place or perform full restart

**Enemies** 
- Red circles using aggro/targeting system
- Chase player when `aggroTarget` is set (full speed)
- Return to spawn when no aggro target (1/3 speed, post-death)
- Navigate around obstacles with collision detection

**Obstacles**
- Green rectangles: blocking (stop movement)
- Purple rectangles: deadly (kill on contact)
- Both affect enemy pathfinding

**Portals**
- Orange shapes (circle/triangle/square) for scene transitions
- Shape indicates destination scene type
- Player teleports to center of destination scene

**Scenes**
- Multiple areas with unique layouts, backgrounds, and entity scaling
- Enemies respawn when entering scene via portal
- Current scene tracks all active entities

## SDL3 API Translation

**Performance Considerations**
- Custom circle rendering using line strips for efficiency
- Batched color changes to minimize SDL state switches  
- Event-driven input handling instead of polling
- Frame-rate independent timing using SDL ticks

## Game States

- **Normal**: Player alive, enemies chase (`aggroTarget = player.position`)
- **Game Over**: Player dead, enemies wander home (`aggroTarget = null`)  
- **Paused**: Game time stops, visual pause indicators
- **Victory**: All enemies defeated in current scene

## Controls (SDL3 Input Mapping)

- **Mouse**: Left = move target, Right = shoot bullets
- **WASD/Arrows**: Alternative keyboard movement
- **Space**: Pause toggle
- **R**: Resurrect (when dead) / Full restart (when alive)
- **T**: Reset current scene only
- **Y**: Full game restart
- **` (backtick)**: Toggle HUD visibility (FPS counter, etc.)
- **Escape**: Quit to CLI

## Implementation Status

**✅ Completed**
- Basic SDL3 application structure
- Player movement and basic rendering
- Bullet firing system
- Event handling framework
- Game state structure
- Modular architecture (borders.zig, hud.zig, visuals.zig)
- HUD system with bitmap fonts and FPS counter
- Screen border effects (iris wipe, status indicators)

**🚧 In Progress**
- Scene management and transitions
- Enemy AI and pathfinding
- Collision detection
- Visual effects integration

**📋 TODO**
- ZON data loading integration
- Complete rendering system (enemies, obstacles, portals)
- Camera system for scene scaling
- Audio system (if desired)
- Performance optimizations

## Development Notes

**SDL3 Specific Challenges**
- No built-in circle/ellipse primitives - requires custom implementation
- Camera transforms need manual implementation

**Memory Management**  
- Arena allocators for frame-scoped data
- ZON parsing handled by Zig's standard library
- SDL resources properly cleaned up in callbacks

**Future Enhancements**
- Hardware-accelerated circle rendering with shaders
- SDL3 audio integration for sound effects
- Gamepad support through SDL3 input system
- Multi-window support for debugging views