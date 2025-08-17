# Vendored Dependencies

This directory contains vendored dependencies for the zz project. We vendor these libraries to ensure:
- Reliable builds without network access
- Consistent versions across all builds
- No dependency on external package managers
- Protection against upstream changes/deletions

## Current Dependencies

| Dependency | Version | Purpose | Language |
|------------|---------|---------|----------|
| tree-sitter | v0.25.0 | Core syntax tree parsing library (C) | Core |
| zig-tree-sitter | v0.25.0 | Zig bindings for tree-sitter API | Core |
| tree-sitter-zig | main | Zig language grammar | zig |
| tree-sitter-css | v0.23.0 | CSS language grammar | css |
| tree-sitter-html | v0.23.0 | HTML language grammar | html |
| tree-sitter-json | v0.24.8 | JSON language grammar | json |
| tree-sitter-typescript | v0.23.2 | TypeScript/JavaScript grammar | typescript |
| tree-sitter-svelte | v1.0.2 | Svelte component grammar | svelte |
| zig-spec | main | Zig language specification (reference) | - |
| webref | main | W3C web specs reference data | - |

### Dependency Relationships

- **tree-sitter**: Core C library that all parsing depends on
- **zig-tree-sitter**: Provides Zig API to use tree-sitter (imported as module)
- **tree-sitter-{lang}**: Language grammars providing `tree_sitter_{lang}()` C functions
- **zig-spec** & **webref**: Reference documentation, not compiled

See [deps/CLAUDE.md](CLAUDE.md) for detailed technical explanation.

## Dependency Management

### Using the zz CLI

```bash
# Check dependency status
zz deps --check

# Generate/update manifest.json (auto-detects changes)
zz deps --generate-manifest

# Update all dependencies
zz deps update

# Dry run to see what would change
zz deps update --dry-run

# Force update specific dependency
zz deps update --force-dep tree-sitter
```

### Automatic Features

- **Change Detection**: Only regenerates manifest when deps.zon changes
- **Smart Caching**: Uses content hashing to detect changes efficiently
- **No Timestamp Churn**: Manifest has deterministic content (no git noise)
- **All Dependencies**: Correctly processes all 11 vendored dependencies

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