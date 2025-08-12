# Lib Module - Shared Infrastructure

Performance-critical utilities achieving 20-30% speedup through POSIX-specific optimizations.

## Component Overview

| File | Purpose | Performance Impact |
|------|---------|-------------------|
| `path.zig` | POSIX path operations | ~47μs/op (20-30% faster) |
| `string_pool.zig` | String interning | ~145ns/op (95-100% efficiency) |
| `pools.zig` | Memory pool management | ~50μs/cycle |
| `traversal.zig` | Directory traversal | Early skip optimization |
| `filesystem.zig` | Error handling | Graceful degradation |
| `benchmark.zig` | Performance measurement | Multiple output formats |

## path.zig - POSIX Optimizations

**Key Techniques:**
- **Direct buffer manipulation:** `@memcpy` instead of `fmt.allocPrint`
- **POSIX-only:** Hardcoded `/` separator, no cross-platform overhead
- **Zero allocation:** Path component extraction without allocation

**Core Functions:**
```zig
joinPath()      // Fast two-component joining
joinPaths()     // Multi-component with pre-calculated sizes
basename()      // Extract filename
normalizePath() // Remove redundant separators
isHiddenFile()  // Dot-file detection
```

## string_pool.zig - String Interning

**Architecture:**
- **Arena-based:** All strings in single arena
- **HashMapUnmanaged:** Better cache locality
- **Performance counters:** Hit/miss tracking
- **Pre-populated cache:** Common paths (src, test, node_modules)

**PathCache Features:**
- 95-100% cache efficiency for common patterns
- 15-25% memory reduction in deep traversals
- Specialized `internPath()` for dir/name combinations

## pools.zig - Memory Management

**Specialized Pools:**
```zig
StringPool     // Variable-sized strings, size-based pooling
ArrayListPool  // Generic ArrayList reuse with capacity retention
MemoryPools    // Coordinated management
```

**RAII Wrappers:**
- `withPathList()` - Automatic cleanup for path lists
- `withConstPathList()` - Const variant
- Best-fit allocation for strings up to 2048 bytes

## traversal.zig - Unified Traversal

**Features:**
- **Filesystem abstraction:** Uses `FilesystemInterface`
- **Callback-based:** Custom file/directory handlers
- **Depth limiting:** MAX_TRAVERSAL_DEPTH = 20
- **Pattern integration:** Built-in glob support
- **Early skip:** Ignored directories never opened

**Key API:**
```zig
DirectoryTraverser.collectFiles() // Build file lists with patterns
```

## filesystem.zig - Error Handling

**Error Categories:**
- **Safe to ignore:** FileNotFound, AccessDenied, NotDir
- **Must propagate:** OutOfMemory, SystemResources
- **Config-specific:** Missing config = use defaults

**Patterns:**
```zig
ErrorHandling   // Error classification
Operations      // Safe filesystem wrappers
Helpers         // Common utilities
```

## benchmark.zig - Performance Measurement

**Output Formats:**
- **Markdown:** Tables with baseline comparison
- **JSON:** Machine-readable results
- **CSV:** Spreadsheet-compatible
- **Pretty:** Color terminal with progress bars

**Features:**
- Time-based execution (2s default)
- Baseline comparison (20% regression threshold)
- Human-readable units (ns, μs, ms, s)
- Exit code 1 on regression

**Core Benchmarks:**
```zig
benchmarkPathJoining()   // Path operations
benchmarkStringPool()    // String interning
benchmarkMemoryPools()   // Pool allocation
benchmarkGlobPatterns()  // Pattern matching
```

## Cross-Module Integration

- **Shared patterns:** Error handling used across all modules
- **Path utilities:** Replace stdlib for performance
- **Traversal:** Supports both tree and prompt
- **Memory management:** Reduces allocation pressure
- **Performance validation:** Measures optimization effectiveness

## Architectural Decisions

1. **POSIX-only focus:** Eliminates cross-platform overhead
2. **Arena allocators:** Temporary allocations during traversal
3. **Capacity retention:** ArrayLists keep capacity when pooled
4. **Size-based pooling:** Different strategies by allocation size
5. **Graceful degradation:** Robust real-world operation