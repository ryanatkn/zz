# Contributing to zz

Thank you for your interest in contributing to zz! This guide will help you get started.

## Development Philosophy

- **Performance first** - Measure everything, optimize the hot path
- **No backwards compatibility** - Break things when it improves them
- **Zero dependencies** - If we can't write it, we don't need it
- **POSIX only** - Unix is our home, no Windows compromises
- **Less is more** - Simple > clever, always
- **Old-school discipline** - K&R clarity, byte-counting mentality
- **Modern pragmatism** - TypeScript/Svelte for web, LLMs as tools

## Getting Started

### Prerequisites
- Zig 0.14.1 or later
- POSIX-compliant operating system (Linux, macOS, BSD)
- Git for version control
- ripgrep (`rg`) for code searching

### Setup
```bash
# Clone the repository
git clone https://github.com/ryanatkn/zz.git
cd zz

# Build the project
zig build

# Run tests
zig build test

# Run benchmarks
zig build benchmark
```

## Code Style

### General Guidelines
- Write Zig like C, not C++ (simple, direct, obvious)
- Names should be clear, not clever
- Functions do one thing well
- Document the why, not the what
- Comments only when the code can't speak for itself
- No emoji in code or commits (see TASTE.md)

### Formatting
```zig
// Functions: camelCase
pub fn calculatePath(allocator: Allocator, base: []const u8) ![]u8 {
    // ...
}

// Types: PascalCase
pub const WalkerOptions = struct {
    max_depth: u32 = 10,
    follow_symlinks: bool = false,
};

// Constants: UPPER_SNAKE_CASE for globals, lower_snake_case for locals
const MAX_PATH_LENGTH = 4096;
const default_patterns = [_][]const u8{ ".git", "node_modules" };

// Errors: PascalCase
const WalkerError = error{
    PathTooLong,
    PermissionDenied,
};
```

### Memory Management
```zig
// Always use defer for cleanup
const data = try allocator.alloc(u8, size);
defer allocator.free(data);

// Prefer arena allocators for temporary data
var arena = std.heap.ArenaAllocator.init(allocator);
defer arena.deinit();

// Use string pooling for repeated strings
var cache = try PathCache.init(allocator);
defer cache.deinit();
```

## Making Changes

### 1. Find or Create an Issue
- Check existing issues first
- Create a new issue for bugs or features
- Discuss major changes before implementing

### 2. Create a Branch
```bash
git checkout -b feature/your-feature-name
# or
git checkout -b fix/bug-description
```

### 3. Write Code
Follow these practices:
- **Write tests first** (TDD encouraged)
- **Benchmark performance-critical code**
- **Update documentation** as you go
- **Keep commits focused** and atomic

### 4. Testing

#### Unit Tests
```zig
test "your feature works correctly" {
    const allocator = testing.allocator;
    const result = try yourFunction(allocator, input);
    defer allocator.free(result);
    try testing.expectEqualStrings("expected", result);
}
```

#### Integration Tests
```bash
# Run all tests
zig build test

# Run specific module tests
zig build test-tree
zig build test-prompt

# Run with filter
zig test src/test.zig --test-filter "pattern"
```

#### Performance Tests
```zig
// Add benchmarks for new performance-critical code
pub fn benchmarkYourFeature(self: *Benchmark, iterations: usize) !void {
    var timer = try std.time.Timer.start();
    
    for (0..iterations) |_| {
        // Your operation here
    }
    
    const elapsed = timer.read();
    try self.results.append(.{
        .name = "Your Feature",
        .total_operations = iterations,
        .elapsed_ns = elapsed,
        .ns_per_op = elapsed / iterations,
    });
}
```

### 5. Documentation

Update relevant documentation:
- `README.md` - User-facing features
- `CLAUDE.md` - Implementation details and architecture
- Module-specific docs (e.g., `src/tree/CLAUDE.md`)
- Inline documentation for complex algorithms

### 6. Submit Pull Request

#### PR Checklist
- [ ] Tests pass: `zig build test`
- [ ] No performance regression: `zig build benchmark`
- [ ] Code follows style guidelines
- [ ] Documentation updated
- [ ] Commit messages are clear
- [ ] PR description explains the change

#### Commit Message Format
```
module: Brief description (50 chars max)

Longer explanation if needed. Explain what changed and why,
not how (the code shows how).

Fixes #123
```

Examples:
```
tree: Add symlink following support

prompt: Optimize glob pattern expansion by 40%

benchmark: Add color support to pretty output
```

## Project Structure

### Adding a New Command
1. Create module directory: `src/yourcommand/`
2. Required files:
   ```
   src/yourcommand/
   ├── main.zig         # Entry point with run() function
   ├── config.zig       # Command-specific configuration
   ├── test.zig         # Test runner
   └── test/            # Test files
   ```

3. Update CLI:
   ```zig
   // src/cli/command.zig
   pub const Command = enum {
       tree,
       prompt,
       benchmark,
       yourcommand,  // Add here
   };
   
   // src/cli/runner.zig
   .yourcommand => {
       const yc = @import("../yourcommand/main.zig");
       try yc.run(allocator, remaining_args);
   },
   ```

### Adding Shared Utilities
Place in appropriate module:
- `src/lib/` - General utilities
- `src/patterns/` - Pattern matching
- `src/config/` - Configuration handling
- `src/filesystem/` - Filesystem operations

## Performance Guidelines

### Always Measure
```bash
# Before changes
zig build benchmark-baseline

# After changes
zig build benchmark

# Check for regressions
```

### Optimization Checklist
- [ ] Profile before optimizing
- [ ] Measure impact with benchmarks
- [ ] Document performance characteristics
- [ ] Consider memory vs speed tradeoffs
- [ ] Test with large inputs (10,000+ files)

### Common Optimizations
```zig
// String operations - use direct buffer manipulation
const result = try path_utils.joinPath(allocator, dir, file);

// Pattern matching - use fast path for common cases
if (isCommonPattern(pattern)) {
    return fastMatch(pattern, text);
}

// Memory - use pools and arenas
var pool = MemoryPools.init(allocator);
defer pool.deinit();
```

## Review Process

### What We Look For
1. **Correctness** - Does it work as intended?
2. **Performance** - No regressions, optimizations welcome
3. **Tests** - Comprehensive coverage including edge cases
4. **Code Quality** - Clean, idiomatic, maintainable
5. **Documentation** - Clear and up-to-date

### Review Timeline
- Initial response: 1-2 days
- Full review: 3-5 days
- Iteration: As needed

## Getting Help

### Resources
- Read existing code for patterns
- Check test files for usage examples
- Review CLAUDE.md for architecture details
- Use `rg` to search codebase

### Communication
- Open an issue for questions
- Comment on PRs for clarification
- Be respectful and constructive

## Advanced Topics

### Debugging
```bash
# Debug build with symbols
zig build

# Use lldb or gdb
lldb zig-out/bin/zz
(lldb) breakpoint set --file src/tree/walker.zig --line 42
(lldb) run tree

# Debug prints (remove before committing)
std.debug.print("DEBUG: value = {}\n", .{value});
```

### Profiling
```bash
# Build with release mode
zig build -Doptimize=ReleaseFast

# Use perf on Linux
perf record ./zig-out/bin/zz tree /large/directory
perf report

# Use Instruments on macOS
instruments -t "Time Profiler" ./zig-out/bin/zz
```

### Memory Leak Detection
```bash
# Use valgrind on Linux
valgrind --leak-check=full ./zig-out/bin/zz tree

# Use Zig's built-in detection
zig build test -Dtest-memory-leaks
```

## Recognition

Contributors are recognized in:
- Git history (use real name/email if comfortable)
- Release notes for significant contributions
- README.md contributors section (for major features)

## Code of Conduct

- Be respectful and inclusive
- Focus on constructive criticism
- Assume good intentions
- Help others learn and grow

## License

By contributing, you agree that your contributions will be licensed under the same license as the project.

## Questions?

Open an issue with the "question" label, and we'll be happy to help!

Thank you for contributing to making zz faster and better.