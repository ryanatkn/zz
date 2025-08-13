#!/bin/bash
# zz Terminal Demo - Showcasing fast CLI utilities for code analysis

set -e

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Demo header
clear
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║                    zz CLI Terminal Demo                      ║${NC}"
echo -e "${BOLD}${CYAN}║         Fast Command-Line Utilities for POSIX Systems        ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo

# Build zz first
echo -e "${YELLOW}Building zz...${NC}"
if [ ! -f "./zig-out/bin/zz" ]; then
    zig build -Doptimize=ReleaseFast 2>/dev/null || zig build
fi
echo -e "${GREEN}✓ Build complete${NC}"
echo

# Demo function
demo_step() {
    local title="$1"
    local cmd="$2"
    echo -e "${BOLD}${BLUE}═══ $title ═══${NC}"
    echo -e "${MAGENTA}$ $cmd${NC}"
    echo
    eval "$cmd"
    echo
    read -p "Press Enter to continue..."
    echo
}

# Introduction
echo -e "${BOLD}This demo showcases zz's capabilities:${NC}"
echo "• High-performance directory tree visualization"
echo "• Smart code extraction with language awareness"
echo "• LLM-optimized prompt generation"
echo "• Multiple output formats (tree, list)"
echo "• Gitignore integration"
echo
read -p "Press Enter to start the demo..."
clear

# Demo 1: Tree visualization of sample files
demo_step "1. Directory Tree Visualization" \
    "./zig-out/bin/zz tree examples --no-gitignore"

# Demo 2: List format
demo_step "2. List Format Output" \
    "./zig-out/bin/zz tree examples --format=list"

# Demo 3: Show sample TypeScript file
echo -e "${BOLD}${BLUE}═══ 3. Sample TypeScript File ═══${NC}"
echo -e "${CYAN}Showing first 15 lines of examples/app.ts:${NC}"
head -15 examples/app.ts
echo -e "${CYAN}...${NC}"
read -p "Press Enter to parse this file..."
echo

# Demo 4: Extract TypeScript signatures and types
demo_step "4. Extract TypeScript Signatures & Types" \
    "./zig-out/bin/zz prompt examples/app.ts --signatures --types"

# Demo 5: Extract CSS selectors and properties
demo_step "5. Extract CSS Structure" \
    "./zig-out/bin/zz prompt examples/styles.css --types | head -30"

# Demo 6: Extract HTML structure
demo_step "6. Extract HTML Structure" \
    "./zig-out/bin/zz prompt examples/index.html --structure | head -30"

# Demo 7: Extract Svelte component sections
demo_step "7. Parse Svelte Component (Multi-Section)" \
    "./zig-out/bin/zz prompt examples/component.svelte --signatures --types | head -40"

# Demo 7.5: Svelte 5 Runes with TypeScript
demo_step "7.5. Parse Svelte 5 Runes (Modern Reactive TypeScript)" \
    "./zig-out/bin/zz prompt examples/runes.svelte.ts --signatures --types | head -40"

# Demo 8: JSON structure extraction
demo_step "8. Extract JSON Structure" \
    "./zig-out/bin/zz prompt examples/config.json --structure"

# Demo 9: Glob patterns
demo_step "9. Use Glob Patterns" \
    "./zig-out/bin/zz prompt 'examples/*.{ts,css,html,svelte}' --signatures | head -40"

# Demo 10: Performance benchmark
echo -e "${BOLD}${BLUE}═══ 10. Performance Benchmarks ═══${NC}"
echo -e "${MAGENTA}$ ./zig-out/bin/zz benchmark --format=pretty${NC}"
echo
./zig-out/bin/zz benchmark --format=pretty 2>/dev/null || echo "Run 'zig build benchmark' for full benchmarks"
echo

# Summary
echo -e "${BOLD}${GREEN}═══ Demo Complete! ═══${NC}"
echo
echo -e "${BOLD}Key Features Demonstrated:${NC}"
echo "✓ Terminal-only rendering with clean output"
echo "✓ Fast directory traversal with pattern matching"
echo "✓ Language-aware code extraction (TS, CSS, HTML, JSON, Svelte, Svelte+TS)"
echo "✓ Multiple extraction modes (signatures, types, structure)"
echo "✓ Glob pattern support for file selection"
echo "✓ Performance benchmarking capabilities"
echo
echo -e "${BOLD}Performance Highlights:${NC}"
echo "• Path operations: ~47μs per operation (20-30% faster than stdlib)"
echo "• String pooling: ~145ns per operation"
echo "• Pattern matching: ~25ns per operation"
echo
echo -e "${CYAN}For more information, see README.md${NC}"
echo -e "${CYAN}Repository: https://github.com/ryanatkn/zz${NC}"