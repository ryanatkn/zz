# Hex - GPU-Accelerated 2D Action RPG

A procedurally-rendered 2D topdown action RPG built with Zig, SDL3 GPU API, and HLSL shaders.

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

## Current Module Structure

```
└── hex
    ├── docs
    │   ├── ecs.md                    # Entity-component system documentation
    │   ├── gpu.md                    # GPU rendering and SDL3 API reference
    │   └── shader_compilation.md     # HLSL compilation workflow
    ├── shaders
    │   ├── compiled [...]            # Auto-generated SPIRV/DXIL binaries
    │   ├── source                    # HLSL shader source files
    │   │   ├── circle.hlsl           # Standard circle rendering shader
    │   │   ├── debug_circle.hlsl     # Debug circle with orbital animation
    │   │   ├── effect.hlsl           # Visual effects shader
    │   │   ├── rectangle.hlsl        # Rectangle rendering shader
    │   │   ├── simple_circle.hlsl    # Basic circle distance field shader
    │   │   ├── simple_rectangle.hlsl # Basic rectangle shader
    │   │   ├── triangle.hlsl         # Triangle rendering shader
    │   │   └── triangle_uniforms.hlsl# Triangle with uniform data test
    │   └── compile_shaders.sh        # Automated HLSL→SPIRV/DXIL compilation
    ├── CLAUDE.md                     # Module documentation and development notes
    ├── behaviors.zig                 # Entity behavior updates (player, units, bullets)
    ├── camera.zig                    # Viewport camera system (fixed/follow modes)
    ├── combat.zig                    # Combat system (bullets, damage, death)
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
    ├── simple_gpu_renderer.zig      # Clean GPU rendering backend
    └── types.zig                     # Shared data types (GPU-compatible structs)
```

**Status:** ✅ Complete GPU-accelerated game with zone-based world

## GPU Architecture Overview

**Architecture Highlights:**
- Modular component separation: game logic, rendering, input, physics
- Camera system: fixed (overworld) vs follow (dungeon) modes  
- Data-driven zones via ZON configuration
- Complete GPU rendering pipeline with HLSL shaders

## Features

- GPU-accelerated procedural rendering (no textures)
- Dual camera system: fixed (overworld) + follow (dungeons)
- Complete gameplay: combat, portals, lifestones, unit AI
- Multi-zone world with ZON data configuration

**Usage:**
- `./zz hex` - Build and run game (auto-compiles shaders)
- Set `DEBUG_MODE = true` in main.zig for GPU debug tests
- Controls: Mouse/WASD movement, right-click fire, Space pause, R respawn, ESC quit

## Game Design

**Zone System:**
- Zones combine environmental properties with entity storage
- Travel between zones via portals (travel metaphor, not "scene changes")
- Each zone has its own camera mode and scale settings
- Units renamed from "enemies" for flexible AI (friendly/neutral/hostile)
- Camera-aware movement bounds (fixed mode only)
- Persistent state across death/respawn cycles

## Technical Notes

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