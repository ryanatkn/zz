# Benchmark Module - Performance Measurement System

Sophisticated benchmarking orchestration with variance-aware duration control and multiple output formats.

## Architecture

**Modular Design:**
- `main.zig` - CLI orchestration, argument parsing, output routing
- `test.zig` - Unit tests for duration parsing, format validation
- `lib/benchmark/` - Modular core system:
  - `types.zig` - Core data structures, confidence enums
  - `runner.zig` - BenchmarkRunner orchestration
  - `timer.zig` - Measurement with statistical confidence
  - `output.zig` - All formatting (markdown, json, csv, pretty)
  - `baseline.zig` - Baseline comparison management
  - `utils.zig` - Helper functions
  - `mod.zig` - Clean re-exports

## Key Data Structures

```zig
Options = struct {
    duration_ns: u64 = 200_000_000,      // 200ms default (increased for accuracy)
    format: OutputFormat = .markdown,
    baseline: ?[]const u8 = null,         // Auto-loads benchmarks/baseline.md
    no_compare: bool = false,
    only: ?[]const u8 = null,             // Comma-separated names
    skip: ?[]const u8 = null,
    warmup: bool = true,                  // Default enabled
    duration_multiplier: f64 = 1.0,
    min_confidence: ?StatisticalConfidence = null, // Optional confidence requirement
};

BenchmarkResult = struct {
    name: []const u8,
    total_operations: usize,
    elapsed_ns: u64,
    ns_per_op: u64,
    confidence: StatisticalConfidence,    // NEW: Statistical confidence level
    extra_info: ?[]const u8 = null,       // Cache efficiency, fast-path ratios
};

StatisticalConfidence = enum {
    high,        // >1000 operations (✓)
    medium,      // 100-1000 operations (○)  
    low,         // 10-100 operations (△)
    insufficient, // <10 operations (⚠)
};
```

## Duration Control System

**Built-in Variance Multipliers:**
- Path operations: **2x** (I/O dependent)
- Memory pools: **3x** (allocation dependent)  
- String pool: **1x** (CPU bound)
- Glob patterns: **2x** (pattern matching variability)

**Effective Duration:** `base_duration * builtin_multiplier * user_multiplier`

## Output Formats

**Markdown:** Header → Results table → Baseline comparison → Notes
**JSON:** Flat object with metadata + results array
**CSV:** Simple header + data rows (no baseline)
**Pretty:** Clean terminal output with confidence symbols and color coding:
- Confidence: ✓ (high), ○ (medium), △ (low), ⚠ (insufficient)
- Performance: Green ✓ (improvements), Yellow ⚠ (regressions), Cyan ? (new)
- **Statistical warnings** for low confidence results

## Baseline Comparison

- **Auto-loading:** markdown/pretty formats load `benchmarks/baseline.md` unless `--no-compare`
- **Regression threshold:** 20% tolerance (Debug mode variance)
- **Exit code:** Returns 1 if any benchmark regresses > 20%
- **Parsing:** Extracts from markdown tables (name, operations, ns/op)

## Command-Line Interface

```bash
zz benchmark [options]
  --format=FORMAT           # markdown|json|csv|pretty
  --duration=TIME           # 200ms default, supports 1s, 500ms, ns values
  --duration-multiplier=N   # Extra multiplier (default: 1.0)
  --baseline=FILE           # Custom baseline (default: benchmarks/baseline.md)
  --no-compare              # Disable baseline comparison
  --only=path,string        # Run specific benchmarks
  --skip=glob,memory        # Skip specific benchmarks
  --no-warmup               # Skip warmup phase
  --min-confidence=LEVEL    # Require minimum statistical confidence
```

## Performance Baselines

| Benchmark | Performance | Notes |
|-----------|-------------|-------|
| Path operations | ~47μs/op | 20-30% faster than stdlib |
| String pooling | ~145ns/op | 95-100% cache efficiency |
| Memory pools | ~50μs/cycle | ArrayList reuse |
| Glob patterns | ~25ns/op | 75% fast-path ratio |
| Code extraction | ~92μs/op | 4 extraction modes (full, signatures, types, combined) |

## Implementation Details

- **Exact duration:** Runs for precise target duration (no minimum iteration forcing)
- **Statistical confidence:** Tracks operation count reliability with symbols
- **Adaptive timing:** Check intervals adjust based on operation speed (10/100/1000)
- **Warmup:** 100 iterations with timeout protection
- **Build mode:** Currently hardcoded as "Debug"
- **Memory management:** Proper cleanup with defer blocks