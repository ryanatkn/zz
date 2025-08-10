# Hex - GPU-Accelerated 2D Action RPG

A procedurally-rendered 2D top-down action RPG built with Zig, SDL3 GPU API, and HLSL shaders. Pure algorithmic graphics with no texture assets.

## Quick Start

```bash
# Install dependencies
zig version  # Requires 0.14.1+

# Build and run
zig build run    # Build and launch game
./zig-out/bin/hex  # Run directly after build

# Shader compilation (automatic with build)
./shaders/compile_shaders.sh  # Manual recompile if needed
```

## Features

### Core Gameplay
- **Movement**: Mouse hold-to-move + WASD direct control
- **Combat**: Right-click projectile firing with collision detection  
- **World**: Zone-based travel system with portals between areas
- **Respawn**: Lifestone checkpoints and R key instant respawn
- **Camera**: Fixed (overworld) and follow (dungeon) modes

### Technical Highlights
- **GPU-First**: SDL3 GPU API with Vulkan/D3D12 backends
- **Procedural Rendering**: No textures - pure algorithmic shape generation
- **Distance Fields**: Anti-aliased primitives via shader mathematics
- **Data-Driven**: Zone configuration through ZON files
- **Cross-Platform**: SPIRV for Vulkan, DXIL for D3D12, MoltenVK for Metal

## Game Controls

### Movement & Actions
- **Hold Left Mouse**: Move toward cursor
- **WASD**: Direct movement
- **Right Click**: Fire projectile
- **Space**: Pause game
- **R**: Respawn at lifestone
- **ESC**: Quit

### Visual Elements
- **Blue Circle**: Player character
- **Red Circles**: Enemy units
- **Green Rectangles**: Solid obstacles
- **Orange Rectangles**: Deadly hazards
- **Purple Circles**: Zone portals
- **Cyan Circles**: Lifestone checkpoints

## Architecture

### Module Structure

```
hex/
├── docs/                      # Technical documentation
│   ├── ecs.md                # Entity system architecture
│   ├── gpu.md                # SDL3 GPU API reference
│   └── shader_compilation.md # HLSL compilation guide
├── shaders/
│   ├── source/               # HLSL shader sources
│   │   ├── simple_circle.hlsl    # Distance field circles
│   │   ├── simple_rectangle.hlsl # Basic rectangles
│   │   └── [other shaders]       # Effects and debug
│   ├── compiled/             # Platform-specific bytecode
│   │   ├── vulkan/          # SPIRV for Linux/Android/macOS
│   │   └── d3d12/           # DXIL for Windows
│   └── compile_shaders.sh   # Build script
├── game_data.zon            # Zone configuration data
├── main.zig                 # SDL3 entry point
├── game.zig                 # Core game loop
├── entities.zig             # Entity storage system
├── behaviors.zig            # Update logic
├── physics.zig              # Collision detection
├── renderer.zig             # GPU rendering pipeline
├── camera.zig               # Viewport management
└── types.zig                # Shared data structures
```

### Design Philosophy

**Procedural-First Approach:**
- All visuals generated algorithmically
- Shapes and effects defined in code and shaders
- Mathematical beauty over static content
- No sprite or texture dependencies

**Performance-Focused:**
- Minimal draw calls via batching
- Procedural vertex generation (no buffers)
- GPU-aligned data structures
- Camera-aware culling

**Clean Architecture:**
- Explicit entity pools (no ECS abstractions)
- Direct function calls (no dynamic dispatch)
- Fixed-size arrays (no runtime allocation)
- Zone-based world organization

## Development

### Building from Source

```bash
# Standard build
zig build

# Debug build with symbols
zig build -Doptimize=Debug

# Release build (optimized)
zig build -Doptimize=ReleaseFast
```

### Shader Development

Shaders are written in HLSL and compiled to platform-specific formats:

```bash
# Incremental build (only changed shaders)
./shaders/compile_shaders.sh

# Clean rebuild (all shaders)
./shaders/compile_shaders.sh --clean
```

**Platform Support:**
- **Windows**: DXIL via D3D12
- **Linux/Steam Deck**: SPIRV via Vulkan
- **macOS/iOS**: SPIRV via Vulkan + MoltenVK
- **Android**: SPIRV via Vulkan

### Debug Mode

Enable GPU debug visualizations:

```zig
// In main.zig
const DEBUG_MODE = true;  // Shows shader test patterns
```

## Technical Details

### GPU Rendering Pipeline

**Shader Requirements:**
- Vertex shaders: `register(b[n], space1)` for uniforms
- Fragment shaders: `register(b[n], space0)`
- Avoid `float4` arrays in cbuffers (use individual floats)
- Procedural vertex generation via `SV_VertexID`

**Command Buffer Order:**
1. Push uniform data (camera, transforms)
2. Begin render pass
3. Bind pipeline and draw primitives
4. End pass and submit

**Coordinate Systems:**
- Screen space: (0,0) top-left
- NDC space: (-1,-1) bottom-left to (1,1) top-right
- Aspect ratio correction in shaders

### Entity System

**Storage Pattern:**
```zig
World {
    player: Player
    bullets: [MAX_BULLETS]Bullet
    zones: [MAX_ZONES]Zone {
        units: [MAX_UNITS]Unit
        obstacles: [MAX_OBSTACLES]Obstacle
        portals: [MAX_PORTALS]Portal
        lifestones: [MAX_LIFESTONES]Lifestone
    }
}
```

**Key Features:**
- Fixed-size pools (no dynamic allocation)
- Contiguous arrays (cache-friendly)
- Explicit types (no abstractions)
- Zone-based organization

### Performance Optimizations

**GPU Strategies:**
- Batch by shape type (circles, rectangles)
- Minimize pipeline state changes
- Use distance fields for anti-aliasing
- Procedural generation reduces bandwidth

**CPU Strategies:**
- Short-circuit dead entities
- Squared distance calculations
- Zone-based spatial partitioning
- Fixed-size memory pools

## Requirements

### System Requirements
- **Zig**: 0.14.1 or newer
- **GPU**: Vulkan 1.0 or DirectX 12 support
- **OS**: Windows 10+, Linux, macOS 10.14+
- **RAM**: 256MB minimum

### Dependencies
- **SDL3**: Window management and GPU API (auto-fetched)
- **SDL_shadercross**: HLSL compilation (for development)
- **MoltenVK**: Vulkan→Metal translation (macOS/iOS, optional)

## Extending the Game

### Adding New Entity Types
1. Define struct in `entities.zig`
2. Add update function to `behaviors.zig`
3. Implement collision in `physics.zig`
4. Add rendering to `renderer.zig`
5. Update zone loader if data-driven

### Creating New Zones
1. Edit `game_data.zon` configuration
2. Define zone properties and entities
3. Set camera mode and scale
4. Configure portal connections

### Writing Custom Shaders
1. Create HLSL in `shaders/source/`
2. Follow uniform buffer conventions
3. Compile with `compile_shaders.sh`
4. Load in renderer pipeline

## Performance Tips

- **Development**: Use debug builds for better errors
- **Testing**: Enable `DEBUG_MODE` for GPU visualizations
- **Production**: Use `ReleaseFast` for maximum speed
- **Profiling**: Tools like RenderDoc for GPU analysis

## License

See LICENSE file in project root.

## Credits

Built with:
- [Zig](https://ziglang.org/) - Systems programming language
- [SDL3](https://libsdl.org/) - Cross-platform GPU API
- [SDL_shadercross](https://github.com/libsdl-org/SDL_shadercross) - Shader compilation