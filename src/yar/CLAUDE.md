# YAR - Yet Another RPG

A vibrant 2D top-down action RPG with scene-based exploration and dynamic enemy AI.

## Module Structure

```
$ ./zz tree src/yar
└── yar
    ├── CLAUDE.md             # Game-specific documentation and concepts
    ├── game.zig              # Complete game implementation with all systems
    ├── game_data.zon         # Data-driven scene/level configuration
    ├── raylib_audio.zig      # Sound and music playback bindings
    ├── raylib_core.zig       # Window management, input, timing bindings
    ├── raylib_models.zig     # 3D model loading and rendering bindings
    ├── raylib_shapes.zig     # 2D primitive drawing function bindings
    ├── raylib_text.zig       # Font loading and text rendering bindings
    ├── raylib_textures.zig   # Image/texture loading and manipulation bindings
    └── raylib_types.zig      # Common types and structures
```

## Core Concepts

**Player**
- Blue circle that moves via mouse (left-click) or WASD/arrows
- Shoots yellow bullets toward mouse cursor (right-click)
- Dies on contact with enemies or deadly obstacles
- Can resurrect in place (R when dead) or full restart (R when alive)

**Enemies**
- Red circles that use aggro/targeting system
- Chase player when `aggroTarget` is set (full speed)
- Return to spawn when no aggro target (1/3 speed, post-death)
- Navigate around obstacles using pathfinding
- Turn gray when killed, can be revived by scene reset

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

## Game States

- **Normal**: Player alive, enemies chase (`aggroTarget = player.position`)
- **Game Over**: Player dead, enemies wander home (`aggroTarget = null`)
- **Paused**: Yellow-orange pulsing border, time stops
- **Victory**: Green-teal pulsing border when all enemies dead

## Controls

- **Mouse**: Left = move, Right = shoot
- **WASD/Arrows**: Alternative movement
- **Space**: Pause toggle
- **R**: Resurrect (when dead) / Full restart (when alive)
- **[/]**: Speed control (0.25x - 4x)