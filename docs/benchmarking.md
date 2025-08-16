# Benchmarking Guide

Performance benchmarking is critical for maintaining and improving the efficiency of zz. The benchmark system follows Unix philosophy: the CLI outputs to stdout, and users control file management.

## Design Philosophy
- **CLI is pure**: `zz benchmark` always outputs to stdout
- **Multiple formats**: markdown (default), json, csv, pretty
- **Build commands add convenience**: Handle file management for common workflows
- **Composable**: Works with Unix pipes and redirects

## CLI Usage (outputs to stdout)
```bash
# Default: markdown format to stdout (2 seconds per benchmark)
$ zz benchmark

# Different output formats
$ zz benchmark --format=pretty             # Clean color terminal output with status indicators
$ zz benchmark --format=json               # Machine-readable JSON
$ zz benchmark --format=csv                # Spreadsheet-compatible CSV

# Control timing and what runs
$ zz benchmark --duration=1s               # Run each benchmark for 1 second
$ zz benchmark --duration=500ms            # Run each benchmark for 500 milliseconds
$ zz benchmark --only=path,string          # Run specific benchmarks
$ zz benchmark --skip=glob                 # Skip specific benchmarks

# Duration control for more stable results
$ zz benchmark --duration-multiplier=2.0   # 2x longer for all benchmarks

# Save results via shell redirect
$ zz benchmark > results.md                # Save to any file
$ zz benchmark | grep "Path"               # Pipe to other tools
$ zz benchmark --format=json | jq '.results[]'  # Process JSON output

# Baseline comparison (auto-loads if exists)
$ zz benchmark --baseline=old.md           # Compare with specific baseline
$ zz benchmark --no-compare                # Disable auto-comparison
```

## Build Commands (project workflow)
```bash
# Common workflow with file management
$ zig build benchmark                      # Save to latest.md, compare, show pretty output
$ zig build benchmark-baseline             # Create/update baseline.md
$ zig build benchmark-stdout               # Pretty output without saving

# Release mode benchmarking (longer duration for more stable results)
$ zig build -Doptimize=ReleaseFast
$ ./zig-out/bin/zz benchmark --duration=5s
```

## Features
- Multiple output formats for different use cases
- Automatic baseline comparison (when benchmarks/baseline.md exists)
- Regression detection with exit code 1 (20% threshold)
- Clean separation: CLI for data, build commands for workflow
- Clean color-enhanced terminal output with status indicators
- Human-readable time units (ns, μs, ms, s)
- **Duration multiplier system** - Allows extending benchmark duration for more stable results

## Performance Baselines (Release build, 2025-08-13)
- Path operations: ~11μs per operation
- String pooling: ~11ns per operation
- Memory pools: ~11μs per allocation/release cycle
- Glob patterns: ~4ns per operation
- Code extraction: ~21μs per extraction
- Benchmark execution: ~10 seconds total
- Regression threshold: 20%
- Time-based execution: 2 seconds default per benchmark

## When to Run Benchmarks
- Before and after implementing optimizations
- When modifying core infrastructure (`src/lib/`)
- To verify performance improvements are maintained
- During development of new features that impact performance
- In CI/CD to catch performance regressions

> TODO benchmarking needs better DX and features