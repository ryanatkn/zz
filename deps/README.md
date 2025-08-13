# Vendored Dependencies

This directory contains vendored dependencies for the zz project. We vendor these libraries to ensure:
- Reliable builds without network access
- Consistent versions across all builds
- No dependency on external package managers
- Protection against upstream changes/deletions

## Current Dependencies

| Dependency | Version | Purpose | Source |
|------------|---------|---------|--------|
| tree-sitter | v0.25.0 | Core syntax tree parsing library (C) | https://github.com/tree-sitter/tree-sitter |
| zig-tree-sitter | v0.25.0 | Zig bindings for tree-sitter API | https://github.com/tree-sitter/zig-tree-sitter |
| tree-sitter-zig | main | Zig language grammar (C parser) | https://github.com/maxxnino/tree-sitter-zig |
| zig-spec | main | Zig language specification (docs only) | https://github.com/ziglang/zig-spec |

### Dependency Relationships

- **tree-sitter**: Core C library that all parsing depends on
- **zig-tree-sitter**: Provides Zig API to use tree-sitter (imported as module)
- **tree-sitter-zig**: Provides `tree_sitter_zig()` C function for parsing Zig code
- **zig-spec**: Reference documentation, not compiled

See [deps/CLAUDE.md](CLAUDE.md) for detailed technical explanation.

## Updating Dependencies

### Quick Start

```bash
# Check if updates are needed (safe to run anytime)
./scripts/update-deps.sh

# Force update all dependencies
./scripts/update-deps.sh --force

# Update specific dependency only
./scripts/update-deps.sh --force-dep tree-sitter

# Show help and available options
./scripts/update-deps.sh --help
```

### What the Script Does

The update script is **idempotent** and **efficient**:

1. **Checks first**: Only updates if version changed or files missing
2. **Shallow clones**: Uses `--depth 1` to save bandwidth
3. **Cleans up**: Removes `.git` directories and incompatible build files
4. **Tracks versions**: Creates `.version` files with timestamps
5. **Shows progress**: Clear output of what's happening

### Script Output

```
📦 Checking vendored dependencies for zz

  ⏭ Skipping tree-sitter (already up to date: v0.25.0)
  ✓ zig-tree-sitter vendored successfully

📦 Updated 1 dependencies
```

## Why Vendor?

We chose vendoring over other approaches for these reasons:

1. **Reliability**: No network dependencies during build
2. **Reproducibility**: Everyone builds with the same code
3. **Simplicity**: No submodule complexity or package manager issues
4. **Compatibility**: Avoids Zig package manager naming restrictions
5. **Stability**: Protected from upstream breaking changes

## Files We Remove

The update script removes these files from vendored dependencies:

| Dependency | Removed Files | Reason |
|------------|---------------|--------|
| tree-sitter | build.zig, build.zig.zon | Incompatible with Zig 0.14.1 (uses string literals for names) |
| zig-tree-sitter | build.zig, build.zig.zon | Incompatible naming ("tree-sitter" with hyphen) |
| tree-sitter-zig | build.zig, build.zig.zon | We compile the C parser directly |

## Files We Modify

Currently no modifications needed. Any future patches go in `deps/patches/` directory.

## Manual Update Process

If you need to update a specific dependency manually:

```bash
# Example: Update tree-sitter-zig
cd deps/
rm -rf tree-sitter-zig
git clone --depth 1 https://github.com/maxxnino/tree-sitter-zig.git
rm -rf tree-sitter-zig/.git
echo "manual update $(date)" > tree-sitter-zig/.version
```

## Adding New Language Grammars

To add support for a new language:

1. Find the tree-sitter grammar repository
2. Add it to `scripts/update-deps.sh`
3. Run the update script
4. Update `build.zig` to compile the grammar
5. Add language support to `src/lib/parser.zig`

Example grammar repositories:
- TypeScript: https://github.com/tree-sitter/tree-sitter-typescript
- Rust: https://github.com/tree-sitter/tree-sitter-rust
- Go: https://github.com/tree-sitter/tree-sitter-go
- Python: https://github.com/tree-sitter/tree-sitter-python