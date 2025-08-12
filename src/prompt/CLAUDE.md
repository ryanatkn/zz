# Prompt Module - LLM Prompt Generation

Sophisticated file aggregation with 40-60% glob speedup and intelligent error handling.

## Architecture

**Design:** Five focused components with excellent separation of concerns.

## Module Structure

- `main.zig` - Command orchestration, argument parsing, deduplication
- `builder.zig` - Arena-based prompt building with XML tags
- `config.zig` - Flag parsing (--prepend, --append, --allow-*)
- `fence.zig` - Dynamic fence detection for nested code blocks
- `glob.zig` - Pattern expansion with fast-path optimization
- `test.zig` - Test runner
- `test/` - 14 test files with comprehensive coverage

## Key Features

### Glob Pattern Support

**Wildcards:** `*`, `?`, `**` (recursive, depth limit: 20)
**Character Classes:** `[0-9]`, `[a-zA-Z]`, `[!0-9]`
**Brace Expansion:** `*.{zig,{md,txt}}` → `*.zig`, `*.md`, `*.txt`
**Escape Sequences:** `\*` for literal asterisk
**Hidden Files:** `*` excludes hidden, `.*` includes them
**Directory Support:** `src/` recursively processes all files

### Fast-Path Optimizations

**Pre-optimized patterns (40-60% speedup):**
- `*.{zig,c,h}` - C/Zig development
- `*.{js,ts}` - JavaScript/TypeScript
- `*.{md,txt}` - Documentation

### Error Handling Modes

**Strict (default):**
- Errors on missing explicit files
- Errors on empty glob patterns
- Errors when requested files are ignored

**Permissive:**
- `--allow-empty-glob` - Warnings for empty globs
- `--allow-missing` - Warnings for all missing files
- Text-only mode - Valid with just --prepend/--append

## Implementation Details

### Deduplication (main.zig:110-139)

```zig
var seen = std.StringHashMap(void).init(allocator);
if (!seen.contains(path)) {
    try seen.put(path, {});
    try filtered_paths.append(path);
}
```

O(1) deduplication across all pattern expansions.

### Arena Memory Management

**Temporary allocations during expansion:**
```zig
var arena = std.heap.ArenaAllocator.init(self.allocator);
defer arena.deinit();
// Complex glob operations...
// Final results copied to main allocator
```

### Smart Fence Detection (fence.zig)

**Algorithm:**
1. Start with `````
2. Check for conflicts in content
3. Increment fence length until no conflicts
4. Cap at 32 backticks for safety

### Output Format

```markdown
<File path="src/main.zig">

```zig
// file content with proper syntax highlighting
```

</File>
```

**Features:**
- XML tags for LLM semantic context
- Automatic syntax highlighting by extension
- 10MB file size limit with warnings
- Smart fence handling for nested blocks

## Directory Integration

- Uses `DirectoryTraverser` from `lib/traversal.zig`
- Respects ignore patterns from `zz.zon`
- Gitignore integration (unless --no-gitignore)
- Early directory skipping for performance
- Unix-style hidden file conventions

## Test Coverage

**14 comprehensive test files:**
- Core functionality (builder, config, glob)
- Edge cases (empty, boundary, Unicode)
- Security (path traversal protection)
- Integration (directories, flags, symlinks)
- Large files and memory management
- Explicit ignore interactions

**190+ tests with 100% success rate**

## Command-Line Interface

```bash
zz prompt [files...] [options]
  --prepend=TEXT        # Add before files
  --append=TEXT         # Add after files
  --allow-empty-glob    # Warn on empty globs
  --allow-missing       # Warn on missing files
  --no-gitignore        # Disable gitignore
```

## Performance Characteristics

- **Arena allocators:** Reduce allocation overhead
- **Fast-path globs:** 40-60% speedup for common patterns
- **O(1) deduplication:** StringHashMap for efficiency
- **Early skip:** Ignored directories never opened

## Architectural Strengths

1. **Modular design:** Clear component boundaries
2. **Performance-conscious:** Arena allocators, fast-paths
3. **Robust error handling:** Multiple modes for different workflows
4. **Comprehensive testing:** Edge cases thoroughly covered
5. **Filesystem abstraction:** Enables isolated testing
6. **Memory safety:** Proper cleanup with errdefer
7. **Unix philosophy:** Composable with clear I/O