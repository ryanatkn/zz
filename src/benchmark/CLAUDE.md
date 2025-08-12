# Benchmark Module - Performance Measurement System

Sophisticated benchmarking orchestration with variance-aware duration control and multiple output formats.

## Architecture

**Separation of Concerns:**
- `main.zig` - CLI orchestration, argument parsing, output routing
- `test.zig` - Unit tests for duration parsing, format validation
- Core logic in `lib/benchmark.zig` - Actual benchmark implementations

## Key Data Structures

```zig
Options = struct {
    duration_ns: u64 = 2_000_000_000,     // 2s default
    format: OutputFormat = .markdown,
    baseline: ?[]const u8 = null,         // Auto-loads benchmarks/baseline.md
    no_compare: bool = false,
    only: ?[]const u8 = null,             // Comma-separated names
    skip: ?[]const u8 = null,
    warmup: bool = false,
    duration_multiplier: f64 = 1.0,
};

BenchmarkResult = struct {
    name: []const u8,
    total_operations: usize,
    elapsed_ns: u64,
    ns_per_op: u64,
    extra_info: ?[]const u8 = null,       // Cache efficiency, fast-path ratios
};
```

## Duration Control System

**Built-in Variance Multipliers:**
- Path operations: **2x** (I/O dependent)
- Memory pools: **3x** (allocation dependent)  
- String pool: **1x** (CPU bound)
- Glob patterns: **1x** (CPU bound)

**Effective Duration:** `base_duration * builtin_multiplier * user_multiplier`

## Output Formats

**Markdown:** Header → Results table → Baseline comparison → Notes
**JSON:** Flat object with metadata + results array
**CSV:** Simple header + data rows (no baseline)
**Pretty:** Unicode boxes, progress bars, color coding:
- Green ✓: improvements < -1%
- Yellow ⚠: regressions > +5%
- Cyan ?: new benchmarks

## Baseline Comparison

- **Auto-loading:** markdown/pretty formats load `benchmarks/baseline.md` unless `--no-compare`
- **Regression threshold:** 20% tolerance (Debug mode variance)
- **Exit code:** Returns 1 if any benchmark regresses > 20%
- **Parsing:** Extracts from markdown tables (name, operations, ns/op)

## Command-Line Interface

```bash
zz benchmark [options]
  --format=FORMAT           # markdown|json|csv|pretty
  --duration=TIME           # 1s, 500ms, 2000000000 (ns)
  --duration-multiplier=N   # Extra multiplier (default: 1.0)
  --baseline=FILE           # Custom baseline (default: benchmarks/baseline.md)
  --no-compare              # Disable baseline comparison
  --only=path,string        # Run specific benchmarks
  --skip=glob,memory        # Skip specific benchmarks
  --warmup                  # Include warmup phase
```

## Performance Baselines

| Benchmark | Performance | Notes |
|-----------|-------------|-------|
| Path operations | ~47μs/op | 20-30% faster than stdlib |
| String pooling | ~145ns/op | 95-100% cache efficiency |
| Memory pools | ~50μs/cycle | ArrayList reuse |
| Glob patterns | ~25ns/op | 75% fast-path ratio |

## Implementation Details

- **Time-based execution:** Runs until duration reached (not iteration-based)
- **Warmup:** 100 × 1KB allocations + computational loop
- **Build mode:** Currently hardcoded as "Debug"
- **Memory management:** Proper cleanup with defer blocks
- **Name aliases:** "string" or "string-pool" both work