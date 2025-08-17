# Development Workflow

> ⚠️ AI slop code and docs, is unstable and full of lies

## Managing Vendored Dependencies

The project uses vendored dependencies for tree-sitter libraries to ensure reliable, reproducible builds without network access.

```bash
# Check current state (idempotent - safe to run anytime)
./scripts/update-deps.sh

# Force update all dependencies
./scripts/update-deps.sh --force

# Force update specific dependency
./scripts/update-deps.sh --force-dep tree-sitter

# View help and available dependencies
./scripts/update-deps.sh --help
```

### Script Features
- **Idempotent:** Only updates when versions change or files are missing
- **Efficient:** Skips up-to-date dependencies, uses shallow git clones
- **Clean:** Removes `.git` directories and incompatible build files
- **Versioned:** Creates `.version` files for tracking

### After Updating Dependencies
```bash
zig build test           # Verify everything works
git add deps/            # Commit vendored code
git commit -m "Update vendored dependencies"
```

## TODO Document Workflow

### Active TODO Documents
- **Active TODO docs** should be placed in root directory with `TODO_*.md` prefix and caps like TODO_FOO.md or TODO_BAR.md for high visibility
- **Completed TODO docs** should be **updated in place** with completion status, not moved
  - Update title: `# TODO: Task Name` → `# ✅ COMPLETED: Task Name`
  - Add completion date and final status summary
  - Keep file in root to show what major work has been accomplished

### Validation Before Archival
For complex architecture migrations:
1. Run validation session to verify implementation matches design intent
2. Machine develops complete understanding of relevant codebase parts
3. Validate local file state against TODO documentation claims
4. User and machine independently verify results, conclusions, and presented data
5. Only after convening and getting user approval does the machine proceed to archive validated TODO files

### Document Organization
- **Permanent docs** (README.md, CLAUDE.md) remain unprefixed in root
- **Only archive to `docs/archive/`** when TODO docs become stale, superseded, or fully validated as complete
- **Always commit todo docs** to git both during work and after completion
- This workflow ensures completed work remains visible while tracking major accomplishments

## Build Commands

```bash
# Build commands (default is Debug mode)
$ zig build                         # Debug build (default)
$ zig build -Doptimize=ReleaseFast  # ReleaseFast | ReleaseSafeFast | ReleaseSmall
$ zig build --use-llvm              # Use LLVM backend

# Development workflow
$ zig build run -- tree [args]          # Run tree command in development
$ zig build run -- prompt [args]        # Run prompt command in development
$ zig build run -- benchmark [args]     # Run benchmarks
$ zig build run -- format [args]        # Run formatter in development
$ zig build run -- demo [args]          # Run demo in development
```

## Testing During Development

```bash
# Run all tests
$ zig build test

# Run specific test module
$ zig build test -Dtest-filter="tree"

# Run with verbose output
$ zig build test --verbose
```

See [Testing Guide](./testing.md) for comprehensive testing documentation.

## Performance Verification

When modifying core infrastructure:
```bash
# Run benchmarks before changes
$ zig build benchmark-baseline

# Make your changes...

# Run benchmarks after changes
$ zig build benchmark

# Check for regressions (auto-compares with baseline)
```

See [Benchmarking Guide](./benchmarking.md) for detailed performance testing.

## Claude Code Configuration

The project is configured for optimal Claude Code usage:

**Tool Preferences (`.claude/config.json`):**
- `rg:*` - Prefer ripgrep (`rg`) over `grep`/`find`/`cat`
- `zz:*` - Full access to project CLI for testing and development and feature usage

**Best Practices:**
- Always use `rg` for text search instead of `grep` or `find`
- Use `zig build test` for testing and `zig build benchmark` for benchmarking
- Use `zz` commands for exploring code with semantic extraction (`zz prompt`, `zz tree`, etc.)
- Leverage Claude Code's native Grep tool which uses ripgrep internally

## Notes for Contributors

When selecting tasks:
1. Start with high impact, low effort items
2. Ensure backward compatibility (unless explicitly breaking)
3. Add tests for all new features
4. Update documentation immediately
5. Benchmark performance impacts
6. Consider POSIX compatibility
7. Keep the Unix philosophy in mind

## Development Guidelines

- We want idiomatic Zig, taking more after C than C++
- Do not support backwards compatibility unless explicitly asked
- Never deprecate or preserve legacy code unless explicitly requested, default to deleting old code aggressively
- Never re-export in modules unless explicitly justified with a comment or requested
- Focus on performance and clean architecture
- Test frequently with `zig build run` to ensure each step works
- Add and extend benchmarks when appropriate
- Performance is top priority - optimize for speed
- Address duplicated code and antipatterns
- Keep modules self-contained and focused on their specific purpose
- We have `rg` (ripgrep) installed, so always prefer `rg` over `grep` and `find`
- Always update docs at ./CLAUDE.md and ./README.md
- Always include tests for new functionality and newly handled edge cases
- Leave `// TODO terse explanation` when you encounter unknowns
- Less is more - avoid over-engineering