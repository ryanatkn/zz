# Hex Module Architecture

## Overview
Simple entity pool architecture with explicit types and direct function calls. No abstractions, just arrays and functions.

## Module Structure

```
entities.zig    - Entity storage (explicit pools per type)
behaviors.zig   - Update functions (player, enemy, bullet movement)
physics.zig     - Collision detection (circle-circle, circle-rect)
renderer.zig    - GPU rendering wrapper
loader.zig      - ZON data loading
main.zig        - Game loop orchestration
```

## Entity Storage

### Explicit Pools
```zig
World
├── player: Player                    // Single player entity
├── bullets: [MAX_BULLETS]Bullet      // Global bullet pool
└── zones: [7]Zone                  // Zone array
    ├── enemies: [MAX_ENEMIES]Enemy
    ├── obstacles: [MAX_OBSTACLES]Obstacle
    ├── portals: [MAX_PORTALS]Portal
    └── lifestones: [MAX_LIFESTONES]Lifestone
```

### Key Design Choices
- **No abstraction** - Each entity type has its own struct
- **Fixed arrays** - No dynamic allocation during gameplay
- **Parallel arrays** - Entity data stored contiguously per type
- **Explicit counts** - `enemy_count`, `obstacle_count`, etc.

## Update Pattern

```zig
// Direct function calls, no systems
updatePlayer(&world.player, velocity, dt);
updateEnemy(&enemy, player_pos, player_alive, dt);
updateBullet(&bullet, dt);
```

## Collision Detection

```zig
// Simple shape-based checks
checkCircleCollision(pos1, radius1, pos2, radius2);
checkCircleRectCollision(circle_pos, radius, rect_pos, size);
```

## Rendering

```zig
// Batch by shape for GPU efficiency
renderObstacles();  // All rectangles
renderCircles();    // All circles (player, enemies, bullets)
```

## Data Loading

ZON file → Entity pools
- Loads from `game_data.zon` at compile time
- Maps directly to entity structs
- Fallback to hardcoded data if load fails

## Benefits

1. **Cache-friendly** - Contiguous arrays per entity type
2. **Simple** - No component lookups or entity IDs
3. **Fast** - Direct array iteration, no indirection
4. **Clear** - Each entity type is explicit
5. **LLM-friendly** - No abstractions to navigate

## Performance Optimizations

### Short-Circuit Patterns
- Check entity state (active/alive/attuned) before expensive operations
- Order: `if (!enemy.alive) continue;` before collision checks
- Use squared distances to avoid sqrt until necessary

### Memory Management
- ZON data uses arena allocator - persists for game lifetime
- Fixed-size pools prevent runtime allocations
- Contiguous arrays for cache-friendly iteration

## Known Limitations

- Zone names must be static strings (no dynamic allocation)
- Entity counts are fixed at compile time
- Some behaviors may differ from original (to be fixed as needed)

## Future Extensions

To add new entity types:
1. Add struct to `entities.zig`
2. Add update function to `behaviors.zig`
3. Add collision check to `physics.zig`
4. Add render call to `renderer.zig`
5. Update ZON loader if data-driven

This is NOT a full ECS - it's a simple, explicit entity pool system optimized for clarity and performance.