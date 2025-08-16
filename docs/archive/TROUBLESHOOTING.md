# Troubleshooting Guide for zz

This guide helps you resolve common issues when using or developing zz.

## Installation Issues

### "Zig version not found" or "Zig version too old"

**Problem:** The build fails with Zig version errors.

**Solution:**
```bash
# Check your Zig version
zig version

# Should be 0.14.1 or later
# If not, update Zig:
# macOS:
brew upgrade zig

# Linux (using zigup):
zigup master

# Or download from https://ziglang.org/download/
```

### Build fails with "out of memory"

**Problem:** Large projects fail to build on systems with limited RAM.

**Solution:**
```bash
# Use release mode (uses less memory during compilation)
zig build -Doptimize=ReleaseSmall

# Or limit parallel jobs
zig build -j 2
```

### Installation path not found

**Problem:** `zz: command not found` after installation.

**Solution:**
```bash
# Check if ~/.zz/bin is in your PATH
echo $PATH | grep -q ".zz/bin" && echo "Path is set" || echo "Path not set"

# Add to PATH if missing
echo 'export PATH="$PATH:$HOME/.zz/bin"' >> ~/.bashrc
source ~/.bashrc

# Or for zsh:
echo 'export PATH="$PATH:$HOME/.zz/bin"' >> ~/.zshrc
source ~/.zshrc
```

## Runtime Issues

### "Permission denied" errors

**Problem:** zz tree fails with permission errors on certain directories.

**Solution:**
```bash
# Option 1: Skip directories with permission errors
zz tree --skip-errors

# Option 2: Run with elevated permissions (if appropriate)
sudo zz tree /protected/directory

# Option 3: Add to ignored patterns in zz.zon
.{
    .ignored_patterns = .{
        "/protected/directory",
    },
}
```

### Out of memory on large directories

**Problem:** zz crashes when processing very large directory trees.

**Solution:**
```bash
# Limit depth
zz tree . 3  # Max depth of 3

# Increase ignore patterns
# Add common large directories to zz.zon:
.{
    .ignored_patterns = .{
        "node_modules",
        ".git",
        "target",
        "build",
        "dist",
        "vendor",
    },
}

# Use list format (uses less memory)
zz tree --format=list
```

### Slow performance on network drives

**Problem:** Commands are very slow on network-mounted filesystems.

**Solution:**
```bash
# Option 1: Copy to local disk first
rsync -av network:/path /tmp/local-copy
zz tree /tmp/local-copy

# Option 2: Limit depth and ignore patterns
zz tree network:/path 2

# Option 3: Disable gitignore checking (reduces I/O)
zz tree --no-gitignore network:/path
```

### Unicode/special characters display incorrectly

**Problem:** Tree output shows garbled characters or boxes.

**Solution:**
```bash
# Check terminal encoding
locale

# Set UTF-8 if needed
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Use ASCII-only output (future feature)
# zz tree --ascii
```

## Pattern Matching Issues

### Glob patterns not matching expected files

**Problem:** Patterns like `*.{js,ts}` don't match files.

**Solution:**
```bash
# Check pattern syntax - zz uses specific glob syntax
# Correct:
zz prompt "*.{js,ts}"          # Quotes required for shell
zz prompt '**/*.zig'           # Single quotes also work

# Incorrect:
zz prompt *.{js,ts}            # Shell expands before zz sees it
zz prompt **/*.zig             # Shell may expand ** differently

# Debug pattern matching
zz prompt "*.{js,ts}" --debug  # Shows pattern expansion (future)
```

### Files being unexpectedly ignored

**Problem:** Some files don't appear in tree or prompt output.

**Solution:**
```bash
# Check if file is gitignored
git check-ignore path/to/file

# Override gitignore
zz tree --no-gitignore

# Check zz.zon for ignore patterns
cat zz.zon

# Check for hidden file filtering
# Hidden files need explicit patterns:
zz prompt ".*"  # Include hidden files
```

### Pattern performance issues

**Problem:** Complex patterns cause slow performance.

**Solution:**
```zig
// Use fast-path patterns when possible
// Fast (optimized):
"*.{zig,c,h}"
"*.{js,ts}"
"*.{md,txt}"

// Slow (full parser):
"*.{a,b,{c,d},e}"
"**/*{test,spec}.{js,ts}"

// Break complex patterns into simpler ones:
// Instead of: "**/*{test,spec}.{js,ts,jsx,tsx}"
// Use:
zz prompt "**/*test.js" "**/*test.ts" "**/*spec.js" "**/*spec.ts"
```

## Configuration Issues

### zz.zon not being loaded

**Problem:** Configuration changes don't take effect.

**Solution:**
```bash
# Check if zz.zon exists in current directory
ls -la zz.zon

# Verify syntax (must be valid ZON)
zig fmt zz.zon  # Will report syntax errors

# Common syntax issues:
# Missing comma:
.{
    .ignored_patterns = .{
        "node_modules"  # <- Missing comma
        "dist"
    },
}

# Correct:
.{
    .ignored_patterns = .{
        "node_modules",
        "dist",
    },
}
```

### Invalid configuration values

**Problem:** zz crashes or behaves unexpectedly with certain config values.

**Solution:**
```zon
// Valid symlink_behavior values:
.symlink_behavior = "skip"    // Default
.symlink_behavior = "follow"  // Follow symlinks
.symlink_behavior = "show"    // Show as symlinks

// Valid base_patterns values:
.base_patterns = "extend"     // Add to defaults
.base_patterns = .{ "custom", "patterns" }  // Replace defaults

// Boolean values:
.respect_gitignore = true     // Not "true" (string)
```

## Benchmark Issues

### Benchmark results vary wildly

**Problem:** Benchmark results are inconsistent between runs.

**Solution:**
```bash
# Use release mode for consistent results
zig build -Doptimize=ReleaseFast
./zig-out/bin/zz benchmark

# Increase iterations for stability
zz benchmark --iterations=10000

# Close other programs to reduce interference
# Disable CPU frequency scaling (Linux):
sudo cpupower frequency-set -g performance

# Run multiple times and average
for i in {1..5}; do zz benchmark; done
```

### Regression detection too sensitive

**Problem:** Minor performance variations trigger regression warnings.

**Solution:**
```bash
# Current threshold is 20% for Debug mode
# For Release mode, expect tighter variance

# Run benchmarks in Release mode:
zig build -Doptimize=ReleaseFast
./zig-out/bin/zz benchmark

# Or adjust regression threshold (requires code change)
# In src/benchmark/main.zig:
if (change > 0.2) { // Change from 0.2 to 0.3 for 30% threshold
```

## Development Issues

### Tests failing randomly

**Problem:** Tests pass individually but fail when run together.

**Solution:**
```bash
# Run tests with -Dtest-filter to isolate
zig build test -Dtest-filter="specific test"

# Check for test pollution (shared state)
# Each test should be independent

# Run with different allocators to catch memory issues
zig test src/test.zig --test-allocator

# Use mock filesystem for deterministic tests
# See src/filesystem/mock.zig for examples
```

### Memory leaks detected

**Problem:** Valgrind or tests report memory leaks.

**Solution:**
```bash
# Run with Valgrind to identify leak location
valgrind --leak-check=full --show-leak-kinds=all ./zig-out/bin/zz tree

# Common leak patterns:
# 1. Missing defer for cleanup
const data = try allocator.alloc(u8, 100);
// Missing: defer allocator.free(data);

# 2. Not using arena allocator for temporary data
var arena = std.heap.ArenaAllocator.init(allocator);
defer arena.deinit();
// Use arena.allocator() for all temporary allocations

# 3. Circular references in data structures
# Use weak references or explicit cleanup
```

### Performance regression after changes

**Problem:** Benchmarks show performance degradation.

**Solution:**
```bash
# Profile to identify the cause
perf record ./zig-out/bin/zz tree /large/directory
perf report

# Common causes:
# 1. Accidental O(n²) algorithm
# 2. Repeated allocations in hot path
# 3. Missing fast-path optimization
# 4. Cache-unfriendly data access

# Revert and bisect to find the problematic commit
git bisect start
git bisect bad HEAD
git bisect good <last-known-good>
# Test each commit with benchmarks
```

## Platform-Specific Issues

### macOS: "Operation not permitted" errors

**Problem:** Security restrictions prevent file access.

**Solution:**
```bash
# Grant terminal full disk access:
# System Preferences → Security & Privacy → Privacy → Full Disk Access
# Add your terminal application

# Or use a different directory:
zz tree ~/Documents  # Instead of ~/Library
```

### Linux: inotify limit reached

**Problem:** File watching features fail with "too many open files".

**Solution:**
```bash
# Increase inotify limits
echo fs.inotify.max_user_watches=524288 | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Check current limit
cat /proc/sys/fs/inotify/max_user_watches
```

### BSD: kqueue errors

**Problem:** Event notification fails on BSD systems.

**Solution:**
```bash
# Increase kern.maxfiles
sysctl kern.maxfiles=65536

# Make permanent in /etc/sysctl.conf
echo "kern.maxfiles=65536" >> /etc/sysctl.conf
```

## Getting Help

### Debug Output

Enable debug output for more information (future feature):
```bash
ZZ_DEBUG=1 zz tree
ZZ_DEBUG=pattern zz prompt "*.zig"
ZZ_DEBUG=perf zz benchmark
```

### Reporting Issues

When reporting issues, include:
1. Zig version: `zig version`
2. OS and version: `uname -a`
3. zz version/commit: `git rev-parse HEAD`
4. Minimal reproduction steps
5. Error messages or unexpected output
6. Relevant configuration (zz.zon)

### Community Support

- GitHub Issues: Report bugs and request features
- Discussions: Ask questions and share tips
- Pull Requests: Contribute fixes

## Common Error Messages

| Error | Meaning | Solution |
|-------|---------|----------|
| `OutOfMemory` | Allocation failed | Reduce scope or increase RAM |
| `FileNotFound` | Path doesn't exist | Check path and permissions |
| `PermissionDenied` | Insufficient access | Run with sudo or skip |
| `InvalidPattern` | Malformed glob | Check pattern syntax |
| `PathTooLong` | Exceeds OS limit | Use shorter paths |
| `TooManyOpenFiles` | FD limit reached | Increase ulimit |
| `BrokenPipe` | Output interrupted | Normal when piping to head |
| `InvalidConfiguration` | Bad zz.zon | Fix syntax errors |

## Performance Tuning

### For Large Repositories

```zon
// Optimize zz.zon for large repos
.{
    .base_patterns = "extend",
    .ignored_patterns = .{
        "node_modules",
        ".git",
        "target",
        "build",
        "dist",
        ".cache",
        "vendor",
        "third_party",
    },
    .respect_gitignore = true,  // Use existing gitignore
}
```

### For Speed

```bash
# Build with maximum optimization
zig build -Doptimize=ReleaseFast

# Use simpler operations
zz tree --format=list  # Faster than tree format
zz prompt "*.zig" --no-dedup  # Skip deduplication (future)
```

### For Memory

```bash
# Limit scope
zz tree . 3  # Limit depth
zz prompt "src/*.zig"  # Not "**/*.zig"

# Use streaming (future feature)
zz prompt --stream "*.zig" | process-as-you-go
```

## Quick Fixes

```bash
# Reset to defaults
rm zz.zon

# Clean build
rm -rf zig-cache zig-out
zig build

# Fresh clone
git clone <repo> zz-fresh
cd zz-fresh
zig build

# Test minimal case
echo "test" > test.txt
zz prompt test.txt  # Should work

# Verify installation
which zz
zz help
```