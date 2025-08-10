# Hex - GPU-Accelerated 2D Action RPG

A procedurally-rendered 2D topdown action RPG built with Zig, SDL3 GPU API, and HLSL shaders.

Performance is a top priority, and we dont care about backwards compat - always try to get to the final best code.

## Environment

```bash
$ zig version
0.14.1
```

Dependencies: SDL3 (auto-fetched), SDL_shadercross (HLSL→SPIRV/DXIL compilation)

## Design Philosophy

**Procedural-First Approach:**
- All visuals generated algorithmically - no texture or sprite assets
- Shapes, effects, and animations defined entirely in code and shaders
- Distance field techniques for high-quality anti-aliased primitives
- Mathematical beauty over static content

**GPU-First Architecture:**
- SDL3 GPU API with Vulkan/D3D12 backends
- Procedural vertex generation (no vertex buffers)
- Distance field shaders for anti-aliased primitives
- Camera system with fixed/follow modes

**Performance-Focused:**
- GPU instancing, batching, minimal state changes
- Cache-friendly data structures
- Fixed-size memory pools
- Squared distance calculations

## Project Structure

```
└── .
    ├── docs/                         # Technical documentation
    │   ├── ecs.md                    # Entity system architecture (no ECS abstractions)
    │   ├── gpu.md                    # SDL3 GPU API reference and patterns
    │   └── shader_compilation.md     # HLSL compilation workflow
    ├── shaders/
    │   ├── compiled/                 # Platform-specific bytecode
    │   │   ├── vulkan/              # SPIRV for Linux/Android/macOS (via MoltenVK)
    │   │   └── d3d12/               # DXIL for Windows
    │   ├── source/                   # HLSL shader sources
    │   │   ├── simple_circle.hlsl    # Basic circle distance field shader
    │   │   ├── simple_rectangle.hlsl # Basic rectangle shader
    │   │   ├── circle.hlsl           # Standard circle rendering shader
    │   │   ├── debug_circle.hlsl     # Debug circle with orbital animation
    │   │   ├── effect.hlsl           # Visual effects shader
    │   │   ├── rectangle.hlsl        # Rectangle rendering shader
    │   │   ├── triangle.hlsl         # Triangle rendering shader
    │   │   └── triangle_uniforms.hlsl# Triangle with uniform data test
    │   └── compile_shaders.sh        # Automated HLSL→SPIRV/DXIL compilation
    ├── behaviors.zig                 # Entity behavior updates (player, units, bullets)
    ├── borders.zig                   # Border rendering system
    ├── camera.zig                    # Viewport camera system (fixed/follow modes)
    ├── combat.zig                    # Combat system (bullets, damage, death)
    ├── constants.zig                 # Game constants and configuration
    ├── controls.zig                  # Control mapping and handling
    ├── effects.zig                   # Visual effects system
    ├── entities.zig                  # Zone-based world and entity system
    ├── game.zig                      # Main game state management and update loop
    ├── game_data.zon                 # Data-driven zone configuration
    ├── hud.zig                       # HUD system (FPS counter, UI elements)
    ├── input.zig                     # Input handling (keyboard, mouse)
    ├── loader.zig                    # ZON data loading and parsing
    ├── main.zig                      # SDL3 application entry point and game loop
    ├── maths.zig                     # Mathematical utilities and vector operations
    ├── physics.zig                   # Collision detection and physics
    ├── player.zig                    # Player controller and movement logic
    ├── portals.zig                   # Portal system for zone travel
    ├── renderer.zig                  # GPU renderer with camera integration
    ├── sdl.zig                       # SDL3 bindings and helpers
    ├── simple_gpu_renderer.zig      # Clean GPU rendering backend
    ├── types.zig                     # Shared data types (GPU-compatible structs)
    ├── CLAUDE.md                     # This file - AI assistant documentation
    ├── README.md                     # User-facing documentation
    ├── build.zig                     # Zig build configuration
    └── build.zig.zon                 # Package manifest and dependencies
```

**Status:** ✅ Complete GPU-accelerated game with zone-based world

## Commands

```bash
$ zig build              # Build the game
$ zig build run          # Build and run
$ ./zig-out/bin/hex      # Run after building

# Shader compilation (automatic with build)
$ ./shaders/compile_shaders.sh        # Incremental build (only changed shaders)
$ ./shaders/compile_shaders.sh --clean # Clean rebuild all shaders
```

## Quick Start

**Controls:** Mouse/WASD movement, right-click fire, Space pause, R respawn, ESC quit

**Features:**
- Procedural distance-field rendering for all shapes
- GPU-accelerated visual effects system
- Zone-based world with portal travel between areas
- Data-driven configuration via ZON files
- Complete gameplay: combat, lifestones, unit AI

## GPU Performance Strategy

**Rendering Pipeline:**
- **Minimize draw calls:** Batch similar primitives using instanced rendering
- **Reduce state changes:** Group by pipeline, then by uniform data, then by vertex data
- **Procedural generation:** Generate geometry in vertex shaders to reduce bandwidth
- **Distance field rendering:** High-quality circles/shapes without textures

**Memory & Bandwidth:**
- **Triple buffering:** Cycle GPU buffers to avoid CPU/GPU synchronization stalls
- **Uniform buffers:** Small frame-constant data (camera, time, screen size)
- **Instance buffers:** Large per-object data (positions, colors, radii)
- **Align data structures:** Use `extern struct` for GPU compatibility

**Shader Optimization:**
- **Minimize branching:** Use `step()`, `mix()`, `smoothstep()` instead of if/else
- **Precompute in CPU:** Pass complex calculations as uniforms, not recalculate per-pixel
- **Pack data efficiently:** RGBA colors as float4, positions as Vec2, etc.

**Algorithm Focus:**
- Replace CPU collision detection with GPU parallel approaches where beneficial
- Use squared distances to avoid expensive sqrt operations
- Batch entities by type/behavior for SIMD-friendly processing

## GPU Development Notes

**Working Features:**
- ✅ Complete GPU rendering pipeline with camera system
- ✅ HLSL shaders for procedural shapes and effects
- ✅ Zone-based world with portal travel system
- ✅ Full gameplay loop with combat and respawn mechanics
- ✅ Data-driven zone configuration via ZON files

**Key Success Factors:**
- **Procedural vertex generation:** Use `SV_VertexID` instead of vertex buffers for basic shapes
- **Minimal state:** Start with no uniforms, no vertex input, hardcoded data in shaders
- **Follow SDL3 BasicTriangle pattern:** Proven working approach for pipeline creation

**Architecture Highlights:**
- Zone system: Merged environmental properties with entity storage
- Travel metaphor: Players travel between zones via portals
- Camera modes: Fixed (overworld) vs follow (dungeons)
- Procedural rendering: All visuals generated algorithmically

## Game Design

**Zone System:**
- Zones combine environmental properties with entity storage
- Travel between zones via portals (travel metaphor, not "scene changes")
- Each zone has its own camera mode and scale settings
- Units renamed from "enemies" for flexible AI (friendly/neutral/hostile)
- Camera-aware movement bounds (fixed mode only)
- Persistent state across death/respawn cycles

## Technical Implementation

**GPU Performance:**
- Batch draw calls, minimize render passes and state changes
- Use procedural vertex generation (SV_VertexID) to reduce bandwidth
- Distance field shaders for anti-aliased shapes without textures

**SDL3 GPU Critical Requirements:**
- Vertex shaders: `register(b[n], space1)` for uniform buffers
- Push uniforms BEFORE `SDL_BeginGPURenderPass()`
- Avoid float4 arrays in HLSL cbuffers (use individual floats)
- Screen→NDC coordinate conversion with aspect ratio correction

**Development Principles:**
- Procedural generation over static assets
- Camera system integration for all rendering
- Modular architecture with clean component separation
- Zone-based world design with travel metaphors

## Notes to LLMs

- Game is fully functional - focus on performance and gameplay improvements
- Prioritize procedural generation and performance over asset-based approaches
- Focus on code-driven visuals and algorithmic generation
- Test frequently with `zig build run` to ensure each step works
- Less is more - avoid over-engineering
- Performance is a top priority - always optimize for the final best code
- When working with shaders, follow the SDL3 GPU patterns documented here
- The entity system is NOT an ECS - it's simple arrays with direct function calls
- Do what has been asked; nothing more, nothing less
- NEVER create files unless they're absolutely necessary for achieving your goal
- ALWAYS prefer editing an existing file to creating a new one
- NEVER proactively create documentation files (*.md) or README files unless explicitly requested