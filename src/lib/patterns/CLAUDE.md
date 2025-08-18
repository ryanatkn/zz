# Patterns Module - High-Performance Pattern Matching

Optimized pattern matching utilities for glob patterns and gitignore rules. POSIX-focused with zero-allocation operations where possible.

## Module Structure

```
src/lib/patterns/
├── glob.zig        # Glob pattern matching with wildcards
├── gitignore.zig   # Gitignore pattern handling
└── text.zig        # Text pattern utilities (extractBetween, countBalance, etc.)
```

## Glob Pattern Matching (`glob.zig`)

### Features
- **Wildcards:** `*` (any characters), `?` (single character)
- **Character Classes:** `[0-9]` (ranges), `[abc]` (sets), `[!def]` (negation)
- **Fast paths:** Pre-optimized for common patterns
- **Compiled patterns:** Pre-process for repeated matching
- **Zero allocations:** For simple pattern checks

### Pattern Syntax
```
*.zig           # Match all .zig files
src/*.c         # Match C files in src/
test??.zig      # Match test01.zig, test99.zig, etc.
log[0-9].txt    # Match log0.txt, log5.txt, log9.txt
file[!abc].txt  # Match file1.txt, but not filea.txt
**/test.zig     # Match test.zig in any subdirectory
```

### API
```zig
// Simple matching
const matches = matchSimplePattern("main.zig", "*.zig");  // true

// Multiple patterns
const patterns = [_][]const u8{ "*.zig", "*.zon" };
const matches = matchAnyPattern("config.zon", &patterns);  // true

// Compiled pattern for performance
var glob = try CompiledGlob.init(allocator, "*.zig");
defer glob.deinit();
const matches = glob.match("test.zig");  // true
```

### Performance
- **Simple patterns:** ~10ns per match
- **Wildcard patterns:** ~50ns per match
- **Compiled patterns:** ~30% faster for repeated use

## Gitignore Patterns (`gitignore.zig`)

### Features
- **Directory patterns:** `node_modules/`
- **Negation:** `!important.txt`
- **Comments:** Lines starting with `#`
- **ZON integration:** Serialize/deserialize patterns

### Pattern Rules
```
# Comments are ignored
*.tmp           # Match all .tmp files
/build          # Match build at root only
docs/           # Match docs directory
!README.md      # Don't ignore README.md
```

### API
```zig
// Load from file
const patterns = try GitignorePatterns.loadFromDirHandle(
    allocator, dir, ".gitignore"
);
defer patterns.deinit();

const should_ignore = patterns.shouldIgnore("build/output.js");  // true

// Create from ZON config
const patterns = try GitignorePatterns.fromZon(allocator, &.{
    "*.tmp",
    "build/",
    "node_modules/",
});

// Serialize to ZON
const zon_string = try patterns.toZon(allocator);
```

### Common Pattern Sets
```zig
// Pre-defined patterns for common project types
const zig_patterns = CommonPatterns.zig_project;     // zig-out/, zig-cache/
const node_patterns = CommonPatterns.node_project;   // node_modules/, dist/
const general = CommonPatterns.general;              // .DS_Store, *.swp
```

## Pattern Matching Algorithm

### Wildcard Matching
1. Split pattern on `*` boundaries
2. Check each part exists in sequence
3. Early exit on non-match
4. O(n*m) worst case, O(n) typical

### Optimization Strategies
- **String interning:** Reuse pattern strings
- **Compiled patterns:** Pre-process for repeated use
- **Fast paths:** Common patterns (*.ext) optimized
- **Early exits:** Fail fast on obvious non-matches

## Integration with zz

### Tree Module
```zig
const patterns = @import("lib/patterns/gitignore.zig");
if (patterns.shouldIgnore(path)) continue;  // Skip ignored files
```

### Prompt Module
```zig
const glob = @import("lib/patterns/glob.zig");
if (glob.matchSimplePattern(file, pattern)) {
    // Include file in prompt
}
```

### Config Module
```zig
// Load patterns from zz.zon
const ignore_patterns = try GitignorePatterns.fromZon(
    allocator, config.ignore
);
```

## Performance Benchmarks

```
Pattern         Operation       Time
----------------------------------------
*.zig           Simple match    10ns
src/*.c         Path match      45ns
**/test.zig     Recursive       120ns
log[0-9].txt    Character class 85ns
[!abc]*.txt     Negated class   95ns
Compiled *.zig  Repeated match  7ns
```

## Memory Management

### Allocation Strategy
- **Stack buffers:** For pattern parts <256 bytes
- **Arena allocators:** For temporary pattern expansion
- **String pooling:** For frequently used patterns
- **Compiled patterns:** Amortize allocation cost

### Best Practices
```zig
// Good: Compile pattern once, use many times
var glob = try CompiledGlob.init(allocator, pattern);
defer glob.deinit();
for (files) |file| {
    if (glob.match(file)) { ... }
}

// Bad: Recompile pattern every iteration
for (files) |file| {
    if (matchSimplePattern(file, pattern)) { ... }
}
```

## Text Utilities

**Note:** Text pattern utilities have been moved to the `lib/text/` module for better organization:
- **Text processing:** See `lib/text/processing.zig` for `startsWithAny()`, `containsAny()`, etc.
- **Delimiter operations:** See `lib/text/delimiters.zig` for `countBalance()`, `extractBetween()`, etc.
- **String building:** See `lib/text/builders.zig` for efficient string construction

The patterns module now focuses exclusively on file path patterns (glob and gitignore).

## ZON Serialization

Patterns integrate with ZON for configuration:

```zon
.ignore = .{
    "zig-out/",
    "zig-cache/",
    "*.tmp",
    "node_modules/",
}
```

Deserialization maintains pattern semantics and performance.

## Future Enhancements

1. **Regular expressions:** Full regex support
2. **Negative lookahead:** More complex patterns
3. **Pattern composition:** Combine multiple patterns
4. **Incremental matching:** For streaming data
5. **SIMD optimization:** For bulk matching

## Migration from Legacy

**Before (scattered locations):**
```zig
const glob = @import("lib/parsing/glob.zig");
const gitignore = @import("lib/parsing/gitignore.zig");
const text_patterns = @import("lib/patterns/text.zig");  // OLD
```

**After (organized modules):**
```zig
const glob = @import("lib/patterns/glob.zig");
const gitignore = @import("lib/patterns/gitignore.zig");
const text = @import("lib/text/processing.zig");  // Text utilities moved here
const delimiters = @import("lib/text/delimiters.zig");  // Delimiter operations here
```

## Development Guidelines

1. **Prefer compiled patterns** for repeated matching
2. **Use fast paths** for common patterns (*.ext)
3. **Avoid regex** unless necessary (performance)
4. **Cache pattern results** when possible
5. **Test with large file sets** for performance

The patterns module provides the high-performance pattern matching that makes zz's file operations fast and efficient.