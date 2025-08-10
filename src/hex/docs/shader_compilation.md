# Shader Compilation Guide

## Directory Structure

```
src/hex/shaders/
├── source/          # HLSL source files (.hlsl)
│   ├── circle.hlsl
│   ├── rectangle.hlsl
│   └── effect.hlsl
└── compiled/        # Compiled shader bytecode
    ├── vulkan/      # SPIRV bytecode (.spv) - for Linux, Android, Steam Deck, macOS/iOS
    └── d3d12/       # DXIL bytecode (.dxil) - for Windows
```

## Prerequisites

We use SDL_shadercross for shader compilation, which is already built and available at:
`/home/desk/dev/gamedev/SDL_shadercross/build/shadercross`

The tool supports:
- **Source formats**: HLSL, SPIRV
- **Primary output formats**: SPIRV (for Vulkan), DXIL (for D3D12)
- **Shader stages**: vertex, fragment, compute
- **Features**: Include directories, defines, debug info, cross-platform compilation

## Compilation Commands (Using SDL_shadercross)

### Circle Shader
```bash
# Define the shadercross tool path
SHADERCROSS="/home/desk/dev/gamedev/SDL_shadercross/build/shadercross"

# Vertex shader - compile to SPIRV and DXIL
$SHADERCROSS src/hex/shaders/source/circle.hlsl -s HLSL -d SPIRV -t vertex -e vs_main -o src/hex/shaders/compiled/vulkan/circle_vs.spv
$SHADERCROSS src/hex/shaders/source/circle.hlsl -s HLSL -d DXIL -t vertex -e vs_main -o src/hex/shaders/compiled/d3d12/circle_vs.dxil

# Fragment shader - compile to SPIRV and DXIL  
$SHADERCROSS src/hex/shaders/source/circle.hlsl -s HLSL -d SPIRV -t fragment -e ps_main -o src/hex/shaders/compiled/vulkan/circle_ps.spv
$SHADERCROSS src/hex/shaders/source/circle.hlsl -s HLSL -d DXIL -t fragment -e ps_main -o src/hex/shaders/compiled/d3d12/circle_ps.dxil
```

### Rectangle Shader
```bash
# Vertex shader - compile to SPIRV and DXIL
$SHADERCROSS src/hex/shaders/source/rectangle.hlsl -s HLSL -d SPIRV -t vertex -e vs_main -o src/hex/shaders/compiled/vulkan/rectangle_vs.spv
$SHADERCROSS src/hex/shaders/source/rectangle.hlsl -s HLSL -d DXIL -t vertex -e vs_main -o src/hex/shaders/compiled/d3d12/rectangle_vs.dxil

# Fragment shader - compile to SPIRV and DXIL
$SHADERCROSS src/hex/shaders/source/rectangle.hlsl -s HLSL -d SPIRV -t fragment -e ps_main -o src/hex/shaders/compiled/vulkan/rectangle_ps.spv
$SHADERCROSS src/hex/shaders/source/rectangle.hlsl -s HLSL -d DXIL -t fragment -e ps_main -o src/hex/shaders/compiled/d3d12/rectangle_ps.dxil
```

### Effect Shader
```bash
# Vertex shader - compile to SPIRV and DXIL
$SHADERCROSS src/hex/shaders/source/effect.hlsl -s HLSL -d SPIRV -t vertex -e vs_main -o src/hex/shaders/compiled/vulkan/effect_vs.spv
$SHADERCROSS src/hex/shaders/source/effect.hlsl -s HLSL -d DXIL -t vertex -e vs_main -o src/hex/shaders/compiled/d3d12/effect_vs.dxil

# Fragment shader - compile to SPIRV and DXIL
$SHADERCROSS src/hex/shaders/source/effect.hlsl -s HLSL -d SPIRV -t fragment -e ps_main -o src/hex/shaders/compiled/vulkan/effect_ps.spv
$SHADERCROSS src/hex/shaders/source/effect.hlsl -s HLSL -d DXIL -t fragment -e ps_main -o src/hex/shaders/compiled/d3d12/effect_ps.dxil
```

### Automated Compilation Script

We provide a smart build script at `src/hex/shaders/compile_shaders.sh` that handles all compilation automatically.

#### Usage:
```bash
# Incremental build (default) - only rebuild changed shaders
./src/hex/shaders/compile_shaders.sh

# Clean build - delete all compiled shaders and rebuild everything
./src/hex/shaders/compile_shaders.sh --clean
```

#### Features:
- **🧹 Clean builds**: `--clean` deletes all compiled shaders before rebuilding
- **⚡ Incremental builds**: Default mode only recompiles when HLSL source is newer
- **📁 Smart directory handling**: Always creates output directories relative to script location
- **✅ Error handling**: Clear feedback on compilation success/failure
- **⏭️ Skip optimization**: Shows which shaders are up-to-date and skipped

#### Sample Output:
```
Working in directory: /home/desk/dev/zz/src/hex/shaders
🔧 Incremental build (use --clean for full rebuild)
Compiling circle...
  ⏭️  Skipping circle (up to date)
Compiling rectangle...
  → SPIRV...
  → DXIL...
  → MSL...
  ⚠️  Failed to compile rectangle vertex shader to MSL (descriptor set compatibility issue)
✅ Compiled rectangle (SPIRV ✓, DXIL ✓, MSL ⚠️)

=== Compilation Summary ===
Successfully compiled: 2/2 shaders
```

## Advanced Features

### Shader Reflection (JSON output)
Get detailed information about shader resources and inputs/outputs:
```bash
$SHADERCROSS src/hex/shaders/source/circle.hlsl -s HLSL -d JSON -t vertex -e vs_main -o circle_vs_reflection.json
```

### With Include Directories and Defines
```bash
$SHADERCROSS src/hex/shaders/source/effect.hlsl \
    -s HLSL -d SPIRV -t fragment -e ps_main \
    -I src/hex/shaders/includes \
    -DDEBUG_MODE=1 -DUSE_LIGHTING \
    -g -o effect_ps_debug.spv
```

### Alternative: Native Metal Compilation (Advanced)
While our primary strategy uses MoltenVK translation for Apple platforms, SDL_shadercross can also generate native Metal shaders. However, this requires HLSL source modifications for Metal compatibility:

```bash
# Two-stage compilation (HLSL → SPIRV → MSL)
$SHADERCROSS shader.hlsl -s HLSL -d SPIRV -t vertex -e vs_main -o temp.spv
$SHADERCROSS temp.spv -s SPIRV -d MSL -t vertex -e vs_main -o shader.metal

# Note: May fail due to descriptor set layout incompatibilities
# Our shaders use register(b0) which Metal doesn't support
```

## Alternative: Use SDL_shadercross for runtime compilation

SDL_shadercross also provides a C library for runtime compilation in your application. This allows compiling shaders at startup or dynamically:

```c
// Example C code for runtime compilation:
#include <SDL3_shadercross/SDL_shadercross.h>

SDL_ShaderCross_HLSL_Info hlsl_info = {
    .source = hlsl_source_code,
    .entrypoint = "vs_main",
    .shader_stage = SDL_SHADERCROSS_SHADERSTAGE_VERTEX,
    .enable_debug = false
};

size_t spirv_size;
void* spirv_bytecode = SDL_ShaderCross_CompileSPIRVFromHLSL(&hlsl_info, &spirv_size);
```

## Cross-Platform Strategy

Our shader compilation strategy provides **100% platform coverage** with just two formats:

### **Shader Format by Platform:**
1. **Windows**: DXIL bytecode (.dxil files) → D3D12
2. **Linux/Steam Deck**: SPIRV bytecode (.spv files) → Vulkan  
3. **Android**: SPIRV bytecode (.spv files) → Vulkan
4. **macOS**: SPIRV bytecode (.spv files) → Vulkan via MoltenVK
5. **iOS**: SPIRV bytecode (.spv files) → Vulkan via MoltenVK

### **Apple Platform Support:**
Apple devices use **MoltenVK**, a translation layer that converts Vulkan API calls to Metal at runtime:
```
Your Game → Vulkan API → MoltenVK → Metal → Apple GPU
```

**Benefits:**
- **No shader source changes needed** - use optimal HLSL for D3D12/Vulkan
- **95%+ native Metal performance**  
- **Battle-tested solution** used by major game engines
- **~2-3MB runtime overhead** (bundled with your game)

## Build Strategy Recommendations

### For Development:
```bash
# Fast iterative development - only rebuild changed shaders
./src/hex/shaders/compile_shaders.sh
```

### For Production/CI:
```bash
# Clean build to ensure no stale files
./src/hex/shaders/compile_shaders.sh --clean
```

### Platform Support Status:
- **✅ SPIRV compilation**: Works reliably for Vulkan (Linux, Android, Steam Deck, macOS/iOS via MoltenVK)
- **✅ DXIL compilation**: Works reliably for D3D12 (Windows)  
- **❌ Native MSL compilation**: Disabled due to descriptor set incompatibility (use MoltenVK instead)

### **Complete Platform Coverage:**
Our **SPIRV + DXIL strategy with MoltenVK** supports:
- **✅ Windows** (D3D12) - Primary gaming platform
- **✅ Linux** (Vulkan) - Steam Deck, desktop Linux  
- **✅ Android** (Vulkan) - Mobile gaming
- **✅ macOS** (Vulkan→Metal via MoltenVK) - Mac gaming
- **✅ iOS** (Vulkan→Metal via MoltenVK) - Mobile gaming

This covers **100% of gaming platforms** while keeping HLSL source optimal for the primary APIs.

## Performance Notes

- **Pre-compiled shaders** load faster than runtime compilation
- **SPIRV** provides excellent cross-platform compatibility (Vulkan + MoltenVK)
- **DXIL** offers optimal performance on Windows with D3D12  
- **MoltenVK** provides 95%+ native Metal performance with minimal overhead
- **Incremental builds** speed up development workflow significantly
- Use `--clean` when shader names change or for CI/production builds
- Use `-g` flag during development for debugging

## Distribution Notes

### **MoltenVK Integration:**
- **Size**: ~2-3MB additional binary size
- **Platforms**: Include MoltenVK when targeting macOS/iOS
- **Steam**: Often handles MoltenVK automatically for Vulkan games
- **Standalone**: Bundle `libMoltenVK.dylib` (macOS) or `MoltenVK.framework` (iOS)

### **Shader Loading Strategy in Your Renderer:**
```c
// Pseudocode for shader loading priority:
if (platform == Windows) {
    load_dxil_shader("compiled/d3d12/shader.dxil");
} else {
    // Linux, Android, macOS, iOS all use SPIRV
    load_spirv_shader("compiled/vulkan/shader.spv");  
    // MoltenVK handles Vulkan→Metal translation on Apple platforms
}
```