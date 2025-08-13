# Benchmark Proposals for zz

This document outlines proposed benchmarks and systematic improvements for the zz performance testing infrastructure.

## Current Benchmark Coverage

✓ **Existing Benchmarks:**
1. **Path Joining** - Tests optimized POSIX path operations (~47μs/op)
2. **String Pool** - Tests string interning cache efficiency (~145ns/op)
3. **Memory Pools** - Tests ArrayList pooling performance (~50μs/op)
4. **Glob Patterns** - Tests fast-path optimization for common patterns (~25ns/op)

## Proposed New Benchmarks

### 1. Directory Traversal Performance
**Module:** `src/lib/traversal.zig`
**Why:** Core operation for both tree and prompt commands
**Metrics to track:**
- Files/directories per second
- Memory allocation per directory
- Early skip effectiveness (% directories skipped)
- Filesystem abstraction overhead

```zig
pub fn benchmarkTraversal(self: *Self, iterations: usize) !void {
    // Test with mock filesystem at various scales:
    // - Small (10 dirs, 100 files)
    // - Medium (100 dirs, 1000 files)
    // - Large (1000 dirs, 10000 files)
    // - Deep nesting (10 levels deep)
}
```

### 2. Pattern Matcher Performance
**Module:** `src/patterns/matcher.zig`
**Why:** Critical hot path for filtering operations
**Metrics to track:**
- Pattern matches per second
- Fast-path vs slow-path ratio
- Cache hit rate for compiled patterns
- Memory per pattern compilation

```zig
pub fn benchmarkPatternMatcher(self: *Self, iterations: usize) !void {
    // Test scenarios:
    // - Simple wildcards: *.zig, test?.md
    // - Complex globs: src/**/*.{zig,c,h}
    // - Gitignore patterns: !important.txt, /build/
    // - Mixed pattern sets (10, 100, 1000 patterns)
}
```

### 3. Configuration Loading
**Module:** `src/config/zon.zig`
**Why:** Startup performance impacts user experience
**Metrics to track:**
- ZON parse time
- Pattern compilation time
- Memory footprint
- Config resolution speed

```zig
pub fn benchmarkConfigLoading(self: *Self, iterations: usize) !void {
    // Test with various config sizes:
    // - Minimal config
    // - Typical config (10-20 patterns)
    // - Large config (100+ patterns)
    // - Deeply nested config structures
}
```

### 4. Tree Formatting
**Module:** `src/tree/formatter.zig`
**Why:** Output generation can be bottleneck for large trees
**Metrics to track:**
- Lines formatted per second
- Unicode box drawing overhead
- Memory per tree node
- Buffer allocation efficiency

```zig
pub fn benchmarkTreeFormatting(self: *Self, iterations: usize) !void {
    // Test scenarios:
    // - Flat structure (1000 files in root)
    // - Deep nesting (10 levels)
    // - Wide structure (100 dirs with 10 files each)
    // - Mixed with ignored entries
}
```

### 5. Prompt Building
**Module:** `src/prompt/builder.zig`
**Why:** File aggregation and fence detection performance
**Metrics to track:**
- Files processed per second
- Smart fence detection time
- Deduplication overhead
- XML tag generation speed

```zig
pub fn benchmarkPromptBuilder(self: *Self, iterations: usize) !void {
    // Test scenarios:
    // - Single large file
    // - Many small files (100+)
    // - Nested code blocks
    // - Mixed content types
}
```

### 6. Filesystem Abstraction Overhead
**Module:** `src/filesystem/interface.zig`
**Why:** Measure cost of abstraction layer
**Metrics to track:**
- Virtual call overhead
- Mock vs Real performance delta
- Iterator creation cost
- Error handling overhead

```zig
pub fn benchmarkFilesystemAbstraction(self: *Self, iterations: usize) !void {
    // Compare:
    // - Direct std.fs calls
    // - RealFilesystem interface
    // - MockFilesystem interface
    // - Mixed operations (open, read, iterate)
}
```

### 7. Arena Allocator Performance
**Module:** Various (tree, prompt modules)
**Why:** Memory allocation strategy impact
**Metrics to track:**
- Allocation speed vs general allocator
- Memory fragmentation
- Reset/cleanup time
- Peak memory usage

```zig
pub fn benchmarkArenaAllocator(self: *Self, iterations: usize) !void {
    // Compare:
    // - General allocator
    // - Arena allocator
    // - Fixed buffer allocator
    // For typical tree/prompt workloads
}
```

## Systematic Improvements

### 1. Benchmark Infrastructure Enhancements

#### A. Warmup System
```zig
// Add intelligent warmup that detects stability
pub fn intelligentWarmup(self: *Self) !void {
    var variance: f64 = 1.0;
    while (variance > 0.05) { // 5% variance threshold
        // Run benchmark
        // Calculate variance
        // Adjust iterations
    }
}
```

#### B. Statistical Analysis
```zig
pub const BenchmarkStats = struct {
    mean: f64,
    median: f64,
    std_dev: f64,
    min: u64,
    max: u64,
    percentile_95: u64,
    percentile_99: u64,
};
```

#### C. Memory Profiling
```zig
pub const MemoryMetrics = struct {
    peak_usage: usize,
    allocations: usize,
    deallocations: usize,
    leaked_bytes: usize,
    fragmentation: f64,
};
```

### 2. Continuous Performance Monitoring

#### A. Git Hook Integration
```bash
# .git/hooks/pre-commit
#!/bin/bash
zig build benchmark --format=json > current.json
if [ -f benchmarks/baseline.json ]; then
    zz check-regression current.json benchmarks/baseline.json || exit 1
fi
```

#### B. Performance Dashboard
- Generate HTML reports with charts
- Track performance over time
- Identify regression commits
- Compare across different machines/OSes

#### C. Automated Profiling
```zig
// Add profiling mode to benchmarks
pub const ProfilingOptions = struct {
    enable_callgrind: bool = false,
    enable_perf: bool = false,
    enable_tracy: bool = false,
    sample_rate: u32 = 1000,
};
```

### 3. Benchmark Organization

#### A. Benchmark Categories
```zig
pub const BenchmarkCategory = enum {
    core,        // Critical path operations
    startup,     // Initialization and config
    io,          // File system operations
    memory,      // Allocation and pooling
    parsing,     // Pattern and config parsing
    formatting,  // Output generation
};
```

#### B. Benchmark Profiles
```zig
pub const BenchmarkProfile = enum {
    quick,       // ~1 second, CI/CD checks
    standard,    // ~10 seconds, development
    thorough,    // ~1 minute, release validation
    stress,      // ~10 minutes, stress testing
};
```

### 4. Real-World Benchmark Scenarios

#### A. Repository Benchmarks
Test against real repository structures:
- Small project (100 files)
- Medium project (1000 files)
- Large monorepo (10000+ files)
- Node.js project (with node_modules)
- Rust project (with target/)

#### B. Workload Simulation
```zig
pub const Workload = struct {
    name: []const u8,
    setup: fn(allocator: Allocator) !void,
    execute: fn(allocator: Allocator) !void,
    validate: fn(allocator: Allocator) !bool,
    teardown: fn(allocator: Allocator) !void,
};
```

### 5. Platform-Specific Optimizations

#### A. OS-Specific Benchmarks
```zig
pub fn benchmarkPlatformSpecific(self: *Self) !void {
    switch (builtin.os.tag) {
        .linux => {
            // Test io_uring integration
            // Test fanotify for change detection
        },
        .macos => {
            // Test FSEvents integration
            // Test APFS clone operations
        },
        .freebsd => {
            // Test kqueue optimizations
        },
        else => {},
    }
}
```

#### B. Hardware Utilization
- CPU cache optimization benchmarks
- SIMD pattern matching (where applicable)
- Parallel directory traversal
- Memory prefetching effectiveness

### 6. Regression Detection Improvements

#### A. Adaptive Thresholds
```zig
// Different thresholds for different benchmark types
pub const RegressionThreshold = struct {
    core_ops: f64 = 0.05,      // 5% for critical paths
    memory_ops: f64 = 0.10,     // 10% for memory operations
    io_ops: f64 = 0.20,         // 20% for I/O (more variance)
    startup: f64 = 0.15,        // 15% for initialization
};
```

#### B. Trend Analysis
```zig
// Detect gradual performance degradation
pub fn analyzeTrend(history: []const BenchmarkResult) !TrendAnalysis {
    // Linear regression
    // Moving average
    // Anomaly detection
}
```

### 7. Benchmark Documentation

#### A. Performance Cookbook
Document common optimization patterns:
- String interning best practices
- Arena allocator usage patterns
- Path operation optimizations
- Pattern matching shortcuts

#### B. Benchmark Writing Guide
- How to add new benchmarks
- Ensuring benchmark stability
- Avoiding common pitfalls
- Interpreting results

## Implementation Priority

### Phase 1: Core Infrastructure (Week 1)
1. Statistical analysis additions
2. Memory profiling integration
3. Benchmark categories and profiles

### Phase 2: Critical Path Benchmarks (Week 2)
1. Directory traversal benchmark
2. Pattern matcher benchmark
3. Filesystem abstraction overhead

### Phase 3: Extended Coverage (Week 3)
1. Tree formatting benchmark
2. Prompt building benchmark
3. Configuration loading benchmark

### Phase 4: Monitoring & Analysis (Week 4)
1. Regression trend analysis
2. Performance dashboard
3. Git hook integration

## Success Metrics

- **Coverage:** 80%+ of hot code paths benchmarked
- **Stability:** <5% variance in benchmark results
- **Detection:** 100% of >5% regressions caught
- **Speed:** Full benchmark suite runs in <30 seconds
- **Insights:** Actionable performance data for optimization

## Notes

- Benchmarks should run in both Debug and Release modes
- Consider separate benchmarks for cold vs warm filesystem cache
- Add benchmarks for error paths (permission denied, etc.)
- Track both throughput and latency metrics
- Consider adding flame graph generation for profiling