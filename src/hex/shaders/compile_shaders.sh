#!/bin/bash
# compile_shaders.sh - Compile all HLSL shaders to multiple formats
# Usage: ./compile_shaders.sh [--clean]

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

SHADERCROSS="/home/desk/dev/gamedev/SDL_shadercross/build/shadercross"

# Parse command line arguments
CLEAN_BUILD=false
if [ "$1" = "--clean" ]; then
    CLEAN_BUILD=true
fi

# Check if shadercross tool exists
if [ ! -f "$SHADERCROSS" ]; then
    echo "Error: shadercross tool not found at $SHADERCROSS"
    echo "Please build SDL_shadercross first"
    exit 1
fi

echo "Working in directory: $SCRIPT_DIR"

# Clean existing compiled shaders if requested
if [ "$CLEAN_BUILD" = true ]; then
    echo "🧹 Cleaning existing compiled shaders..."
    rm -rf compiled/
    echo "   Removed compiled/ directory"
fi

# Create output directories (focusing on working platforms)
mkdir -p compiled/d3d12
mkdir -p compiled/vulkan

# Show what we're about to do
if [ "$CLEAN_BUILD" = true ]; then
    echo "🔄 Clean rebuild requested"
else
    echo "🔧 Incremental build (use --clean for full rebuild)"
fi

# Compile all shaders to multiple formats
FAILED_SHADERS=()
SUCCESS_COUNT=0
TOTAL_COUNT=0

for shader in triangle triangle_uniforms simple_circle debug_circle circle rectangle effect simple_rectangle; do
    echo "Compiling $shader..."
    
    # Check if source file exists
    if [ ! -f "source/${shader}.hlsl" ]; then
        echo "Warning: source/${shader}.hlsl not found, skipping..."
        continue
    fi
    
    # Check if we need to rebuild (source newer than compiled files)
    NEEDS_REBUILD=false
    if [ "$CLEAN_BUILD" = true ]; then
        NEEDS_REBUILD=true
    else
        # Check if any target files are missing or older than source
        for target in "compiled/vulkan/${shader}_vs.spv" "compiled/vulkan/${shader}_ps.spv" \
                     "compiled/d3d12/${shader}_vs.dxil" "compiled/d3d12/${shader}_ps.dxil"; do
            if [ ! -f "$target" ] || [ "source/${shader}.hlsl" -nt "$target" ]; then
                NEEDS_REBUILD=true
                break
            fi
        done
    fi
    
    if [ "$NEEDS_REBUILD" = false ]; then
        echo "  ⏭️  Skipping $shader (up to date)"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        TOTAL_COUNT=$((TOTAL_COUNT + 1))
        continue
    fi
    
    SHADER_SUCCESS=true
    
    # Vulkan (SPIRV)
    echo "  → SPIRV..."
    if ! $SHADERCROSS source/${shader}.hlsl -s HLSL -d SPIRV -t vertex -e vs_main -o compiled/vulkan/${shader}_vs.spv 2>/dev/null; then
        echo "    ❌ Failed to compile ${shader} vertex shader to SPIRV"
        SHADER_SUCCESS=false
    fi
    if ! $SHADERCROSS source/${shader}.hlsl -s HLSL -d SPIRV -t fragment -e ps_main -o compiled/vulkan/${shader}_ps.spv 2>/dev/null; then
        echo "    ❌ Failed to compile ${shader} fragment shader to SPIRV"
        SHADER_SUCCESS=false
    fi
    
    # D3D12 (DXIL)
    echo "  → DXIL..."
    if ! $SHADERCROSS source/${shader}.hlsl -s HLSL -d DXIL -t vertex -e vs_main -o compiled/d3d12/${shader}_vs.dxil 2>/dev/null; then
        echo "    ❌ Failed to compile ${shader} vertex shader to DXIL"
        SHADER_SUCCESS=false
    fi
    if ! $SHADERCROSS source/${shader}.hlsl -s HLSL -d DXIL -t fragment -e ps_main -o compiled/d3d12/${shader}_ps.dxil 2>/dev/null; then
        echo "    ❌ Failed to compile ${shader} fragment shader to DXIL"
        SHADER_SUCCESS=false
    fi
    
    if $SHADER_SUCCESS; then
        echo "✅ Compiled $shader (SPIRV ✓, DXIL ✓)"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo "❌ Failed to compile $shader"
        FAILED_SHADERS+=("$shader")
    fi
    
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
done

# Only show summary if there were failures or if running interactively
if [ ${#FAILED_SHADERS[@]} -gt 0 ] || [ -t 1 ]; then
    echo ""
    echo "=== Compilation Summary ==="
    echo "Successfully compiled: $SUCCESS_COUNT/$TOTAL_COUNT shaders"
    
    if [ ${#FAILED_SHADERS[@]} -gt 0 ]; then
        echo "Failed shaders: ${FAILED_SHADERS[*]}"
        exit 1
    fi
fi