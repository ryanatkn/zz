# Patches for Vendored Dependencies

This directory contains patches that need to be applied to vendored dependencies after updating them.

## Current Patches

None required for current versions.

## Creating a Patch

If you need to modify a vendored dependency:

1. Make your changes in the `deps/` directory
2. Create a patch file:
   ```bash
   cd deps/tree-sitter
   git diff > ../patches/tree-sitter.patch
   ```

3. Add the patch to the `PATCHES` array in `scripts/update-deps.sh`:
   ```bash
   declare -A PATCHES=(
       ["tree-sitter"]="deps/patches/tree-sitter.patch"
   )
   ```

## Historical Patches

### tree-sitter ABI version (no longer needed)
- **Version affected**: v0.24.6
- **Issue**: ABI version 14 was incompatible with tree-sitter-zig grammar (needed 15)
- **Solution**: Updated to v0.25.0 which has ABI version 15
- **Patch**: Changed `TREE_SITTER_LANGUAGE_VERSION` from 14 to 15 in api.h

## Testing Patches

After applying patches, always test:
```bash
zig build test
zig build run -- prompt src/*.zig --signatures
```