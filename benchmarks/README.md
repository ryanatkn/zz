# zz Performance Benchmarks

This directory contains internal performance benchmarks for the zz codebase itself.

## Development Workflow

zz's performance is measured via a separate `zz-benchmark` executable to keep the main CLI focused:

```bash
# Establish baseline (first time)
zig build benchmark-baseline

# Regular development - track performance changes  
zig build benchmark

# View results without saving files
zig build benchmark-stdout
```

## Files

- `baseline.md` - Reference performance results
- `latest.md` - Most recent benchmark results (for comparison)

## Direct CLI Usage (Advanced)

The `zz-benchmark` executable provides full control:

```bash
# Run all benchmarks (markdown output)
./zig-out/bin/zz-benchmark

# Pretty terminal output with progress bars
./zig-out/bin/zz-benchmark -- --format pretty

# Run specific suites only
./zig-out/bin/zz-benchmark -- --only stream_first,zon-lexer

# Extended duration for stable results
./zig-out/bin/zz-benchmark -- --duration 500ms --duration-multiplier 2.0
```

## Understanding Results

### Pretty Format (Terminal)
```
╔══════════════════════════════════════════════════════════════╗
║                  zz Performance Benchmarks                   ║
╚══════════════════════════════════════════════════════════════╝

✓ Stream.next() throughput           112 ns [          ] (+0.9% vs     111 ns)
✓ Fact creation                       10 ns [          ] (+0.0% vs      10 ns)
✓ Span distance                        7 ns [▼▼▼▼▼▼▼▼▼▼] (-12.5% vs       8 ns)

Summary: 19 benchmarks, 4928.82 ms total
         ✓ 2 improved  ⚠ 0 regressed
```

**Features:**
- **Progress bars**: Show percentage changes proportionally (▲ = slower, ▼ = faster)
- **Confidence symbols**: ✓ (high), ○ (medium), △ (low), ⚠ (insufficient data)
- **Baseline comparison**: Shows improvements/regressions vs saved baseline

### Markdown Format (Default)
```markdown
| Benchmark | Operations | Time (ms) | ns/op | vs Baseline |
|-----------|------------|-----------|-------|-------------|
| Stream.next() throughput | 1800000 | 200.0 | 111 | +0.9% |
```

Perfect for saving to files and version control tracking.

## Architecture

The benchmark system measures performance of zz's internal modules:

- **stream_first**: Stream processing architecture performance
- **zon-lexer**: ZON language lexing speed
- **Core modules**: Memory, patterns, text processing (currently disabled)

Built as a separate executable to maintain clean separation between zz's user-facing commands and internal development tools.

## Performance Targets

| Module | Target | Current Status |
|--------|--------|----------------|
| Stream.next() | >1M ops/sec | ✅ ~8M ops/sec |
| Fact creation | >100K ops/sec | ✅ ~96M ops/sec |
| Span operations | <50ns/op | ✅ 5-22ns/op |

See [src/benchmark/CLAUDE.md](../src/benchmark/CLAUDE.md) for implementation details.