# Benchmark Workflow

This directory contains performance benchmark results for the zz project.

## Design Philosophy

The benchmark system follows Unix philosophy:
- **CLI outputs to stdout**: Always predictable, always composable
- **Users control files**: You decide where results go via shell redirects
- **Build commands for convenience**: Common workflows are automated

## Files

- `baseline.md` - Reference benchmark results (your performance baseline)
- `latest.md` - Most recent benchmark results (for comparison)

## Typical Workflow

### Option 1: Using Build Commands (Recommended)

The build system provides convenient commands that handle file management:

```bash
# First time - establish baseline
zig build benchmark-baseline

# Regular development - track changes
zig build benchmark
# This command:
# 1. Saves results to benchmarks/latest.md
# 2. Compares with baseline.md if it exists
# 3. Shows pretty comparison in terminal

# After optimizations - update baseline
zig build benchmark-baseline

# Just view results without saving
zig build benchmark-stdout
```

### Option 2: Using CLI Directly (Full Control)

The CLI always outputs to stdout, giving you complete control:

```bash
# Create baseline
zz benchmark > benchmarks/baseline.md

# Save and compare manually
zz benchmark > benchmarks/latest.md
diff benchmarks/baseline.md benchmarks/latest.md

# Pretty terminal output
zz benchmark --format=pretty

# Different formats for different needs
zz benchmark --format=json | jq '.results[] | select(.name=="Path Joining")'
zz benchmark --format=csv > results.csv

# Run specific benchmarks
zz benchmark --only=path,string > quick-check.md

# Extend duration for more stable results
zz benchmark --duration-multiplier=2.0 > stable-results.md
```

## Understanding the Output

### Markdown Format (default)
```markdown
# Benchmark Results
Date: 2024-01-15 10:30:45
Build: Debug
Iterations: 200

| Benchmark | Operations | Time (ms) | ns/op | vs Baseline |
|-----------|------------|-----------|-------|-------------|
| Path Joining | 4000 | 190 | 47500 | -8.3% |
```

### Pretty Format (terminal)
```
╔══════════════════════════════════════════════════════════════╗
║                  zz Performance Benchmarks                   ║
╚══════════════════════════════════════════════════════════════╝

✓ Path Joining         47.50 μs [=========-] (-8.3% vs 51.84 μs)
✓ String Pool            143 ns [----------] (-2.0% vs 146 ns)
⚠ Memory Pools         51.20 μs [==========] (+2.4% vs 50.00 μs)

──────────────────────────────────────────────────────────────
Summary: 3 benchmarks, 812.34 ms total
         ✓ 2 improved  ⚠ 1 regressed
```

**Features:**
- Color-coded results (green=improved, yellow=regressed, cyan=new)
- Human-readable time units (ns, μs, ms, s)
- Progress bars showing relative performance
- Summary with totals and counts

### JSON Format (machine-readable)
```json
{
  "timestamp": 1705312245,
  "build_mode": "Debug",
  "iterations": 200,
  "results": [
    {
      "name": "Path Joining",
      "operations": 4000,
      "elapsed_ns": 190000000,
      "ns_per_op": 47500
    }
  ]
}
```

## Regression Detection

If any benchmark regresses by more than 10%, the command exits with code 1.
This helps catch performance regressions in CI/CD pipelines:

```bash
# In CI/CD script
if ! zz benchmark > /dev/null; then
    echo "Performance regression detected!"
    exit 1
fi
```

## Advanced Usage

### Custom Comparisons
```bash
# Compare with different baseline
zz benchmark --baseline=benchmarks/v1.0-baseline.md

# Disable comparison even if baseline exists
zz benchmark --no-compare

# Reduce variance for more reliable baseline comparisons
zz benchmark --duration-multiplier=3.0 --baseline=benchmarks/stable-baseline.md
```

### Shell Functions
Add these to your `.bashrc` or `.zshrc`:

```bash
# Quick benchmark and save with timestamp
bench-save() {
    zz benchmark > "benchmarks/$(date +%Y%m%d_%H%M%S).md"
}

# Compare two benchmark files
bench-compare() {
    diff -u "$1" "$2" | grep "^[+-]|" | grep -v "^[+-]|--"
}

# Watch for performance changes
bench-watch() {
    watch -n 5 'zz benchmark --format=pretty'
}
```

## Tips

1. **Always benchmark in release mode** for accurate results:
   ```bash
   zig build -Doptimize=ReleaseFast
   ./zig-out/bin/zz benchmark
   ```

2. **Use duration multiplier** for stable results on all benchmarks:
   ```bash
   zz benchmark --duration-multiplier=2.0  # 2x longer for all benchmarks
   zz benchmark --duration-multiplier=3.0  # 3x longer for most stable results
   ```

3. **Track history** in git:
   ```bash
   git add benchmarks/baseline.md
   git commit -m "Update performance baseline"
   ```

4. **Automate in CI** to catch regressions:
   ```yaml
   - name: Check Performance
     run: |
       zig build -Doptimize=ReleaseFast
       ./zig-out/bin/zz benchmark || exit 1
   ```