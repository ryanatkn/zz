# TODO: Add `zz demo` Command & Cleanup

## High-Level Task
Add `zz demo` as a built-in command to the main zz CLI, replacing the separate zz-demo executable.

## Implementation Steps

### 1. Integrate Demo into Main CLI
- [ ] Add `demo` to Command enum in `src/cli/command.zig`
- [ ] Create `src/demo.zig` module with `run(allocator, args)` interface
- [ ] Add handler in `src/cli/runner.zig` to dispatch to demo module
- [ ] Remove separate zz-demo executable from build.zig

### 2. Refactor Demo Module Structure
- [ ] Move `src/demo/` to `src/demo/` (keep as module directory)
- [ ] Consolidate demo logic into clean module interface
- [ ] Support flags: `--non-interactive`, `--output=<file>`
- [ ] Ensure examples/ directory is found relative to binary location

### 3. Cleanup & Polish
- [ ] Remove demo.sh (replaced by pure Zig implementation)
- [ ] Update README.md to reference `zz demo` instead of separate binary
- [ ] Consider adding `--speed=<slow|normal|fast>` for demo pacing
- [ ] Add `--skip-to=<step>` to jump to specific demo sections

### 4. Terminal Library Extensions
- [ ] Consider adding progress bars to `src/lib/terminal/`
- [ ] Add table formatting utilities for benchmark output
- [ ] Extract box-drawing primitives for reuse

### 5. Documentation
- [ ] Update CLAUDE.md with new demo command documentation
- [ ] Add demo command to help text
- [ ] Document terminal library for other modules to use

## Benefits
- Single binary distribution (no separate demo executable)
- Consistent command interface
- Better integration with main CLI
- Reusable terminal components across all commands

## Notes
- Keep non-interactive mode for README generation via `zig build update-readme`
- Ensure demo output remains clean for documentation purposes
- Consider caching demo output to avoid re-running examples