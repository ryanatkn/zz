# CONTEXT.md

**Living state document - updated as work progresses**

## Current Work in Progress

### Active Development
- **Benchmark duration handling** - Added duration multipliers to `src/benchmark/main.zig`
  - Path operations: 2x duration multiplier (moderate variance)
  - Memory pools: 3x duration multiplier (high variance)
  - String pool: 1x (stable)
  - Glob patterns: 1x (stable)

### Recent Changes
- **2024-01-12**: Updated docs/slop philosophy docs
  - Removed marketing language and emoji
  - Added TASTE.md, ANTIPATTERNS.md, ERGONOMICS.md, CONSTRAINTS.md, SIGNALS.md
  - Aligned with "old-school C discipline + modern pragmatism" philosophy

## Performance Baselines (Debug Mode)

| Operation | Current | Target | Notes |
|-----------|---------|--------|-------|
| Path joining | ~47-51μs | <60μs | Variance expected |
| String pool | ~154ns | <200ns | Very stable |
| Memory pools | ~50-51μs | <100μs | High variance normal |
| Glob patterns | ~34ns | <50ns | Very stable |

## Known Issues

### High Priority
- None currently

### Medium Priority
- Memory pool benchmarks show high variance in Debug mode (this is expected)
- Tree output for symlinks inconsistent between real/mock filesystem

### Low Priority
- Some test names don't follow "test what breaks" convention
- Benchmark pretty output could use better progress indicators

## Don't Touch Areas
- **src/lib/string_pool.zig** - Recently optimized, working well
- **src/lib/path.zig** - Performance-critical, thoroughly tested
- **src/patterns/matcher.zig** - Complex but working, needs careful consideration for changes

## Module Status

### Stable (minimal changes expected)
- `src/lib/path.zig` - Path operations
- `src/lib/string_pool.zig` - String interning
- `src/filesystem/` - Filesystem abstraction

### Active (expect changes)
- `src/benchmark/` - Adding variance handling
- `src/cli/help.zig` - Needs update for new benchmark flags

### Future Work (not started)
- `zz-ts` - TypeScript parser (separate binary)
- `zz-web` - Web framework tools (separate binary)
- `zz-llm` - LLM integration (separate binary)

## Test Coverage

- **Total tests**: 190+
- **Pass rate**: 100%
- **Flaky tests**: None known
- **Slowest test**: Performance stress tests (~500ms each)

## Build Notes

- Debug build: ~2 seconds
- Release build: ~5 seconds
- Binary size (debug): ~4MB
- Binary size (release): ~2MB
- Target: < 5MB for core `zz` binary

## Integration Points

- **Claude Code**: Configured in `.claude/config.json` for `zz:*` and `rg:*` commands
- **Benchmarks**: Results saved to `benchmarks/latest.md`, baseline in `benchmarks/baseline.md`
- **Config**: `zz.zon` affects both tree and prompt commands

## Active Experiments

- Testing variance-based duration multipliers for more stable benchmarks
- Considering progress bars for long operations (>2s)

## Notes for Next Session

- Benchmark duration multipliers implemented but need testing in practice
- Philosophy docs complete, may need examples added over time
- Consider adding `zz explain` command for code documentation generation

---
*Last updated: 2024-01-12*