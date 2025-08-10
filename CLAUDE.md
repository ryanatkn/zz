# zz - Experimental Software Tools

CLI utilities and games in Zig. Filesystem tree visualization + Hex 2D action RPG with modern GPU rendering.

Performance is a top priority, and we dont care about backwards compat -
always try to get to the final best code. 

## Environment

```bash
$ zig version
0.14.1
```

Dependencies: SDL3 (auto-fetched), SDL_shadercross (HLSL→SPIRV/DXIL compilation)

## Project Structure

```
└── .
    ├── .claude [...]                  # Claude Code configuration directory
    ├── .git [...]                     # Git repository metadata  
    ├── .zig-cache [...]               # Zig build cache (filtered from tree output)
    ├── src                            # Source code (modular architecture)
    │   ├── cli                        # CLI interface module (command parsing & execution)
    │   │   ├── command.zig            # Command enumeration and string parsing
    │   │   ├── help.zig               # Usage documentation and help text
    │   │   ├── main.zig               # CLI entry point and argument processing
    │   │   └── runner.zig             # Command dispatch and orchestration
    │   ├── hex                        # Hex game module (GPU-accelerated 2D action RPG)
    │   │   ├── shaders                # HLSL shader pipeline (procedural rendering)
    │   │   │   ├── compiled [...]     # SPIRV/DXIL binaries (auto-generated, filtered)
    │   │   │   ├── source             # HLSL source shaders
    │   │   │   └── compile_shaders.sh # Automated shader compilation pipeline
    │   │   ├── CLAUDE.md              # Detailed hex module documentation
    │   │   ├── game_data.zon          # Data-driven game configuration
    │   │   ├── main.zig               # Complete GPU game with debug modes
    │   │   ├── simple_gpu_renderer.zig # Clean GPU rendering backend
    │   │   ├── types.zig              # Shared data structures (GPU-compatible)
    │   │   └── [other game files]     # Legacy and specialized game logic
    │   ├── tree                       # Tree visualization module (high-performance directory traversal)
    │   │   ├── config.zig             # Configuration loading and management
    │   │   ├── entry.zig              # File/directory data structures
    │   │   ├── filter.zig             # Pattern matching and ignore logic
    │   │   ├── formatter.zig          # Tree output rendering
    │   │   ├── main.zig               # Tree command entry point
    │   │   ├── walker.zig             # Core traversal algorithm with optimizations
    │   │   ├── test.zig               # Test runner for basic functionality
    │   │   ├── test/                  # Comprehensive test suite
    │   │   └── CLAUDE.md              # Detailed tree module documentation
    │   └── main.zig                   # Minimal application entry point
    ├── zig-out [...]                  # Build output directory (auto-generated)
    ├── .gitignore                     # Git ignore patterns
    ├── CLAUDE.md                      # AI assistant development documentation
    ├── README.md                      # User-facing documentation and usage guide
    ├── build.zig                      # Zig build system configuration
    ├── build.zig.zon                  # Package manifest and dependencies
    ├── zz                             # Build wrapper script (auto-builds and runs)
    └── zz.zon                         # CLI configuration (tree filtering patterns)
```

## Commands

```bash
$ ./zz tree [dir] [depth]    # Directory tree
$ ./zz hex                   # 2D action RPG
$ ./zz help                  # Command list

# Development workflow - use ./zz instead of zig build for auto-rebuild
$ ./zz                       # Auto-builds and runs with default args
$ ./zz hex                   # Auto-compiles shaders + builds + runs hex game
$ zig build                  # Manual build only (outputs to zig-out/bin/zz)

# Manual shader compilation (./zz hex does this automatically)
$ ./src/hex/shaders/compile_shaders.sh    # Recompile shaders to SPIRV/DXIL
```

## Testing

```bash
$ zig test src/tree/test.zig # Run tree module tests
```

Comprehensive test suite covers configuration parsing, directory filtering, performance optimization, edge cases, and security patterns.

## Hex Game - Modern GPU-Accelerated 2D RPG

**Current Status:** ✅ Complete GPU-accelerated game with zone-based world

**Architecture:** SDL3 GPU API with Vulkan/D3D12 backends, HLSL shaders compiled to SPIRV/DXIL

**Design Philosophy:**
- **Procedural-first:** All visuals generated algorithmically, no texture assets
- **Performance-focused:** GPU instancing, batching, minimal state changes
- **Code-driven:** Shapes, colors, effects defined in shaders and algorithms

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

## Module Structure

**Core Architecture:**
- **CLI Module:** `src/cli/` - Command parsing, validation, and dispatch system
- **Tree Module:** `src/tree/` - High-performance directory traversal with configurable filtering
- **Hex Module:** `src/hex/` - GPU-accelerated 2D action RPG with zone-based world and procedural rendering

**Key Components:**
- **Configuration System:** `zz.zon` + fallback defaults for CLI behavior
- **GPU Rendering Pipeline:** SDL3 GPU API + HLSL shaders → SPIRV/DXIL compilation
- **Performance Optimizations:** Early directory skip, memory management, efficient traversal
- **Modular Design:** Each module is self-contained with clean interfaces

**Adding New Commands:**
1. Add to `Command` enum in `src/cli/command.zig`
2. Update parsing and help text
3. Add handler in `src/cli/runner.zig`  
4. Complex features get dedicated module with `run(allocator, args)` interface

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

## Notes to LLMs

- Game is fully functional - focus on performance and gameplay improvements
- Prioritize procedural generation and performance over asset-based approaches
- Focus on code-driven visuals and algorithmic generation
- Test frequently with `./zz hex` to ensure each step works (user will run this, do not offer, instead just end your turn with instructions to do this)
- Less is more