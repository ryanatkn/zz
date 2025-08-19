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

- **Modular Core**: `src/lib/benchmark/` - Separated into focused modules:
  - `types.zig` - Core data structures, statistical confidence enums
  - `runner.zig` - BenchmarkRunner orchestration
  - `timer.zig` - Measurement with confidence tracking
  - `output.zig` - All formatting (markdown, json, csv, pretty)
  - `baseline.zig` - Baseline comparison management
- **Benchmark Suites**: `src/benchmark/suites/` - Organized by module type
- **Exact duration**: Runs for precise target duration (default 200ms), no minimum iterations

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
zz benchmark --duration 500ms         # Run each benchmark for 500ms (default: 200ms)
zz benchmark --duration-multiplier 2.0  # Double all durations for stability

# Baseline comparison
zz benchmark --baseline old.md        # Compare with specific baseline
zz benchmark --no-compare             # Skip baseline comparison
```

## Output Formats

- **markdown** (default): Tables with baseline comparison and confidence warnings (⚠)
- **pretty**: Terminal output with confidence symbols (✓○△⚠) and performance colors
- **json**: Structured data with confidence statistics for tooling integration  
- **csv**: Simple spreadsheet format with confidence levels

## Statistical Confidence

Each benchmark result includes a confidence level based on operation count:
- **✓ High** (1000+ operations): Statistically reliable
- **○ Medium** (100-1000 operations): Generally reliable  
- **△ Low** (10-100 operations): May have variance
- **⚠ Insufficient** (<10 operations): Unreliable, increase duration

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

Current baselines (Debug build, 200ms duration):
- Path operations: ~50μs/op (Medium-High confidence)
- Character predicates: ~5ns/op (High confidence) 
- ArrayList operations: ~50μs/op (Medium confidence)
- Pattern matching: ~400ns/op (High confidence)
- JSON text analysis: ~1.6μs/op (High confidence)

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

2. **Stable measurements**: Use `--duration-multiplier 2.0` or increase `--duration` for confidence

3. **Track history**: Commit `benchmarks/baseline.md` to git for historical tracking

4. **Filter noise**: Use `--only` to focus on specific areas during development

5. **Confidence requirements**: Use `--min-confidence=medium` to fail on unreliable results

## Implementation Notes

- **Exact duration enforcement**: No minimum iterations, runs for precise target time
- **Statistical confidence tracking**: All results include reliability metadata
- **Adaptive check intervals**: 10/100/1000 operations based on benchmark speed  
- **Warmup phase**: 100 iterations with timeout protection before timing
- **Modular architecture**: Clean separation of timing, output, baseline management
- **Variance multipliers**: Each suite defines expected variability (1x-3x)
- **Memory safety**: Proper cleanup with defer blocks and owned text tracking