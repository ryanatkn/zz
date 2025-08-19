# Benchmarking Guide

Performance benchmarking system for tracking and comparing zz's performance over time.

## Quick Start

```bash
# Run benchmarks and compare with baseline
zig build benchmark

# Save new baseline after optimizations
zig build benchmark-baseline

# Just view results without saving
zig build benchmark-stdout
```

## Architecture

- **Core Module**: `src/lib/benchmark/mod.zig` - Runner, measurement, output formatting
- **Benchmark Suites**: `src/benchmark/suites/` - Organized by module type
  - `core.zig` - Path, memory, text, patterns, character operations
  - `languages.zig` - JSON, ZON, parser layer benchmarks
- **Time-based execution**: Runs for fixed duration (default 2s), not fixed iterations

## CLI Usage

```bash
# Basic usage
zz benchmark                          # Markdown output to stdout
zz benchmark --format pretty          # Colored terminal output
zz benchmark --format json            # Machine-readable JSON

# Control what runs
zz benchmark --only path,memory       # Run specific suites
zz benchmark --skip parser            # Skip specific suites

# Timing control
zz benchmark --duration 5s            # Run each benchmark for 5 seconds
zz benchmark --duration-multiplier 2.0  # Double all durations for stability

# Baseline comparison
zz benchmark --baseline old.md        # Compare with specific baseline
zz benchmark --no-compare             # Skip baseline comparison
```

## Output Formats

- **markdown** (default): Tables with baseline comparison, suitable for documentation
- **pretty**: Terminal output with colors (✓ improved, ⚠ regressed, ? new)
- **json**: Structured data for tooling integration
- **csv**: Simple spreadsheet format

## Variance Multipliers

Built-in multipliers account for operation variability:
- Path operations: 2x (I/O dependent)
- Memory operations: 3x (allocation variability)
- Pattern matching: 2x (complexity dependent)
- Text/char operations: 1x (CPU bound)
- Language processing: 1.5x (parser complexity)

## Baseline Management

```bash
# Workflow for performance optimization
zig build benchmark-baseline         # Save current state
# ... make optimizations ...
zig build benchmark                  # Compare improvements
# If satisfied with improvements:
zig build benchmark-baseline         # Update baseline
```

Files in `benchmarks/`:
- `baseline.md` - Reference performance baseline
- `latest.md` - Most recent benchmark run (created by `zig build benchmark`)

## Performance Targets

Current baselines (Debug build, 2s duration):
- Path operations: ~50μs/op
- Character predicates: ~30ns/op
- ArrayList operations: ~50μs/op
- Pattern matching: ~400ns/op
- JSON text analysis: ~1.6μs/op

**Regression threshold**: 20% slower than baseline triggers exit code 1

## CI Integration

```yaml
# GitHub Actions example
- name: Check Performance
  run: |
    zig build -Doptimize=ReleaseFast
    if ! ./zig-out/bin/zz benchmark; then
      echo "Performance regression detected!"
      exit 1
    fi
```

## Tips

1. **Release mode for accurate results**: 
   ```bash
   zig build -Doptimize=ReleaseFast
   ./zig-out/bin/zz benchmark --duration 5s
   ```

2. **Stable measurements**: Use `--duration-multiplier 2.0` or higher for less variance

3. **Track history**: Commit `benchmarks/baseline.md` to git for historical tracking

4. **Filter noise**: Use `--only` to focus on specific areas during development

## Implementation Notes

- Operations run until duration expires (time-based, not count-based)
- Warmup phase runs 100 iterations before timing
- Each suite can define its own variance multiplier
- Benchmark functions return `BenchmarkError` for proper error handling
- Uses `std.mem.doNotOptimizeAway()` to prevent compiler optimizations