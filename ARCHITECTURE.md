# zz Architecture Guide

## Overview

zz is a high-performance CLI utility suite built with a modular, performance-first architecture. This document describes the system design, key architectural decisions, and module relationships.

## Core Design Principles

1. **Performance First**: Every abstraction must justify its cost
2. **Zero Dependencies**: Pure Zig implementation, no external libraries
3. **Modular Design**: Clear boundaries between commands and shared infrastructure
4. **POSIX Only**: Optimized for Unix-like systems, no Windows support
5. **Memory Efficient**: Arena allocators, string interning, and memory pools

## System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         CLI Layer                            │
│  ┌─────────┐  ┌─────────┐  ┌──────────┐  ┌────────────┐   │
│  │  main   │→ │  args   │→ │ command  │→ │   runner   │   │
│  └─────────┘  └─────────┘  └──────────┘  └────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                      Command Modules                         │
│  ┌──────────┐     ┌──────────┐     ┌──────────────────┐   │
│  │   tree   │     │  prompt  │     │   benchmark      │   │
│  └──────────┘     └──────────┘     └──────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                    Shared Infrastructure                     │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │  config  │  │ patterns │  │filesystem│  │   lib    │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Module Hierarchy

### Entry Points
- `src/main.zig` - Minimal entry point, delegates to CLI
- `src/cli/main.zig` - Argument parsing and command dispatch
- `src/cli/runner.zig` - Command execution orchestration

### Command Modules
Each command is a self-contained module with:
- `main.zig` - Entry point with `run(allocator, args)` interface
- `config.zig` - Command-specific configuration
- Internal implementation files
- `test/` directory with comprehensive tests

### Shared Infrastructure

#### Configuration System (`src/config/`)
```
config/
├── shared.zig      # Core types and SharedConfig structure
├── zon.zig         # ZON file parsing and loading
└── resolver.zig    # Pattern resolution and defaults
```

#### Pattern Matching (`src/patterns/`)
```
patterns/
├── matcher.zig     # Unified pattern engine with fast/slow paths
├── glob.zig        # Glob pattern implementation
└── gitignore.zig   # Gitignore-specific logic
```

#### Filesystem Abstraction (`src/filesystem/`)
```
filesystem/
├── interface.zig   # Abstract interfaces for testing
├── real.zig        # Production filesystem implementation
└── mock.zig        # Mock filesystem for tests
```

#### Core Libraries (`src/lib/`)
```
lib/
├── path.zig        # POSIX-optimized path operations
├── traversal.zig   # Unified directory traversal
├── string_pool.zig # String interning for memory efficiency
├── pools.zig       # Memory pool allocators
├── benchmark.zig   # Performance measurement utilities
└── filesystem.zig  # Error handling patterns
```

## Data Flow

### Command Execution Flow
```
User Input → CLI Parser → Command Dispatcher → Command Module
                                                      ↓
                                              Command Logic
                                                      ↓
                                          Shared Infrastructure
                                                      ↓
                                              Output to User
```

### Configuration Loading
```
zz.zon file → ZON Parser → SharedConfig → Pattern Resolver
                                              ↓
                                     Command-Specific Config
                                              ↓
                                       Runtime Behavior
```

### Directory Traversal
```
Entry Point → Walker.init → Filesystem Interface
                                    ↓
                            Directory Iterator
                                    ↓
                            Pattern Matching
                                    ↓
                            Entry Collection
                                    ↓
                              Formatting
```

## Key Design Patterns

### 1. Parameterized Dependencies
All modules accept interfaces rather than concrete implementations:
```zig
pub fn initWithOptions(allocator: Allocator, config: Config, options: struct {
    filesystem: FilesystemInterface = RealFilesystem.init(),
}) Walker
```

### 2. Arena Allocation
Commands use arena allocators for temporary data:
```zig
var arena = std.heap.ArenaAllocator.init(allocator);
defer arena.deinit();
// All command allocations use arena.allocator()
```

### 3. String Interning
Path strings are interned to reduce memory usage:
```zig
var path_cache = try PathCache.init(allocator);
defer path_cache.deinit();
const interned_path = try path_cache.getPath(path);
```

### 4. Fast/Slow Path Optimization
Pattern matching uses optimized paths for common cases:
```zig
// Fast path for common patterns (90% of cases)
if (isCommonPattern(pattern)) {
    return matchFast(pattern, text);
}
// Slow path for complex patterns (10% of cases)
return matchSlow(pattern, text);
```

## Performance Considerations

### Memory Management
- **Arena Allocators**: Used for per-command allocations
- **String Pooling**: 15-25% memory reduction for deep hierarchies
- **Memory Pools**: Reusable ArrayLists for reduced allocation overhead

### CPU Optimization
- **Early Termination**: Skip ignored directories without opening
- **Path Operations**: Direct buffer manipulation instead of formatting
- **Pattern Caching**: Compiled patterns are cached and reused

### I/O Optimization
- **Single-Pass Traversal**: Read each directory only once
- **Buffered Output**: Minimize write syscalls
- **Lazy Loading**: Config loaded only when needed

## Testing Strategy

### Test Levels
1. **Unit Tests**: Individual function testing
2. **Module Tests**: Component integration testing
3. **Integration Tests**: End-to-end command testing
4. **Performance Tests**: Benchmark and stress testing

### Mock Filesystem
Enables deterministic testing without real I/O:
```zig
var mock_fs = MockFilesystem.init(allocator);
try mock_fs.addFile("test.zig", "content");
const walker = Walker.initWithOptions(allocator, config, .{
    .filesystem = mock_fs.interface(),
});
```

## Extension Points

### Adding New Commands
1. Create module directory: `src/newcmd/`
2. Implement `main.zig` with `run(allocator, args)` function
3. Add to `Command` enum in `src/cli/command.zig`
4. Update `src/cli/runner.zig` to dispatch
5. Add tests in `src/newcmd/test/`

### Adding Shared Utilities
1. Add to appropriate module in `src/lib/`
2. Follow existing patterns for API design
3. Include benchmarks if performance-critical
4. Add comprehensive tests

## Security Considerations

- **Path Traversal**: All paths are validated and normalized
- **Resource Limits**: Maximum depth and file count limits
- **Error Handling**: No panics, all errors handled gracefully
- **Input Validation**: All user input is sanitized

## Future Architecture Considerations

### Potential Enhancements
- Parallel directory traversal (with work stealing)
- Incremental updates (watch mode)
- Caching layer for repeated operations
- Plugin system for custom commands

### Scaling Considerations
- Current design handles 100,000+ files efficiently
- Memory usage is O(depth) not O(total files)
- Pattern matching is O(patterns × files) but optimized

## Conclusion

The architecture prioritizes performance and modularity while maintaining clean interfaces. The design allows for easy testing, extension, and optimization without compromising the core functionality.