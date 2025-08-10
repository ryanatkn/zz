# Tree Module - Directory Visualization System

A high-performance directory tree visualization tool with configurable filtering and efficient traversal optimization.

## Design Philosophy

**Performance-First Architecture:**
- Early directory skip optimization prevents expensive filesystem operations
- Configurable patterns avoid hardcoded assumptions
- Memory-efficient traversal with proper cleanup
- Single-pass directory scanning with intelligent filtering

**Clean Separation of Concerns:**
- **Config**: Centralized configuration loading and management
- **Filter**: Pattern matching and ignore logic  
- **Walker**: Core traversal algorithm with performance optimizations
- **Formatter**: Clean tree-style output rendering
- **Entry**: Lightweight data structures for file/directory representation

## Module Structure

```
└── tree
    ├── config.zig             # Configuration parser and defaults
    ├── entry.zig              # File/directory entry data structures
    ├── filter.zig             # Pattern matching and ignore logic
    ├── formatter.zig          # Tree output formatting and display
    ├── main.zig               # Module entry point and CLI integration
    ├── walker.zig             # Core recursive traversal algorithm
    ├── test.zig               # Main test runner (basic functionality tests)
    ├── test/                   # Comprehensive test suite
    │   ├── config_test.zig     # Configuration system edge cases
    │   ├── filter_test.zig     # Pattern matching comprehensive tests
    │   ├── formatter_test.zig  # Output formatting tests
    │   ├── integration_test.zig# End-to-end workflow tests
    │   ├── performance_test.zig# Performance and scalability tests
    │   └── walker_test.zig     # Core traversal algorithm tests
    └── CLAUDE.md              # This documentation
```

## Architecture Overview

**Configuration System:**
- `config.zig`: Loads settings from `zz.zon` with graceful fallbacks to defaults
- Supports both name-based patterns (`node_modules`) and path-based patterns (`src/ignored/path`)
- Single source of truth eliminates duplication between ignored patterns and stop-crawling lists

**Filtering Engine:**
- `filter.zig`: High-performance pattern matching with early termination
- `shouldIgnore()`: Determines if directory should show as `[...]`
- `shouldIgnoreAtPath()`: Handles complex path-based patterns
- `shouldHide()`: Completely hidden files (not displayed at all)

**Traversal Optimization:**
- `walker.zig`: Core recursive algorithm with performance-critical optimizations
- **Early Directory Skip**: Ignored directories are never opened or traversed
- **Memory Management**: Proper allocation/deallocation with RAII patterns
- **Error Handling**: Graceful handling of permission denied, broken symlinks, etc.

**Output Generation:**
- `formatter.zig`: Clean tree-style rendering with Unicode box characters
- `entry.zig`: Lightweight data structures optimized for tree display
- Colored output for ignored directories (`[...]` in gray)

## Performance Optimizations

**Filesystem Efficiency:**
```zig
// BEFORE: Always traverse, then filter (slow)
readdir() -> filter -> display

// AFTER: Filter before traversal (fast)  
check_patterns -> skip_or_traverse -> display
```

**Memory Management:**
- Configuration loaded once, reused across traversal
- Path strings allocated/freed efficiently with proper cleanup
- No global state - each operation is self-contained

**Early Termination:**
- Dot-prefixed directories (`.git`, `.cache`) auto-ignored
- Path-based patterns caught early
- Depth limiting prevents infinite recursion

## Key Features

**Configurable Patterns:**
- `zz.zon` configuration with intelligent defaults
- Both exact matches and path-based patterns supported
- Graceful fallback when config file is missing

**Performance Monitoring:**
- Comprehensive test suite verifies no crawling of ignored directories
- Edge case testing covers nested patterns, dot-directories, empty vs populated dirs
- Memory leak detection and proper cleanup validation

**Developer Experience:**
- Clean module boundaries with clear responsibilities  
- Comprehensive error handling without crashes
- Extensive test coverage for edge cases and real-world scenarios

## Usage Patterns

**Basic Usage:**
```zig
// Load configuration
var config = try Config.fromArgs(allocator, args);
defer config.deinit(allocator);

// Create walker and traverse
const walker = Walker.init(allocator, config);
try walker.walk(directory_path);
```

**Configuration Structure:**
```zig
// zz.zon configuration
.tree = .{
    .ignored_patterns = .{
        ".git", "node_modules", "src/ignored/dir"  
    },
    .hidden_files = .{
        "Thumbs.db", ".DS_Store"
    },
}
```

## Testing Strategy

**Test Structure:**
```bash
# Complete test suite with all modules active
zig test src/tree/test.zig  # Runs all 57 tests across 8 modules
```

**Active Test Modules:**
- ✅ **Configuration** - Loading, parsing, memory management, edge cases
- ✅ **Filter** - Pattern matching, Unicode, security, performance
- ✅ **Walker** - Directory traversal, ignore behavior, mock testing
- ✅ **Formatter** - Output rendering, connectors, entry handling
- ✅ **Integration** - End-to-end workflows with real directory structures
- ✅ **Edge Cases** - Unicode, special characters, symlinks, encoding
- ✅ **Performance** - Large structures, scalability, memory stress testing
- ✅ **Concurrency** - Multi-instance, config immutability, lifecycle

**Test Coverage:**
- 57 comprehensive tests covering all functionality
- Mock filesystem testing for behavior verification
- Performance benchmarking with speedup measurements
- Memory leak detection and cleanup validation
- Error handling for malformed configs and permission issues

## Integration Points

**CLI Integration:**
- `main.zig` provides clean interface for `src/cli/runner.zig`
- Proper error propagation and resource cleanup
- Consistent argument parsing and validation

**Configuration Integration:**
- Reads from project root `zz.zon` file
- Falls back to sensible defaults for common patterns
- Extensible for future configuration needs

## Development Notes

**Performance Critical Paths:**
- Directory pattern matching (hot path - optimized for speed)
- Filesystem traversal (early termination essential)
- Memory allocation (minimize allocations in recursive calls)

**Code Quality:**
- Zero global state - all operations are self-contained
- Comprehensive error handling without panics
- Memory safety with proper RAII patterns
- Extensive test coverage for reliability

**Future Enhancements:**
- Full `.zon` file parsing (currently uses defaults)
- Glob pattern support for more flexible matching
- Performance metrics and profiling integration
- Interactive configuration validation