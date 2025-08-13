# Prompt Module - LLM Prompt Generation

Sophisticated file aggregation with intelligent code extraction, 40-60% glob speedup, and language-aware parsing via tree-sitter integration.

## Architecture

**Design:** Five focused components with excellent separation of concerns.

## Module Structure

- `main.zig` - Command orchestration, argument parsing, deduplication
- `builder.zig` - Arena-based prompt building with XML tags and extraction flags
- `config.zig` - Flag parsing (--prepend, --append, --allow-*, extraction flags)
- `fence.zig` - Dynamic fence detection for nested code blocks
- `glob.zig` - Pattern expansion with fast-path optimization
- `test.zig` - Test runner
- `test/` - 14 test files with comprehensive coverage

**External Dependencies:**
- `../lib/parser.zig` - Tree-sitter integration for language-aware code extraction

## Key Features

### Intelligent Code Extraction

**Language-Aware Parsing:** Tree-sitter integration for precise code analysis
**Extraction Modes:** Eight specialized flags for different use cases
**Language Detection:** Automatic parser selection based on file extensions
**Backward Compatibility:** Default `--full` preserves existing behavior

**Extraction Flags:**
- `--signatures` - Function/method signatures only
- `--types` - Type definitions (structs, enums, interfaces)
- `--docs` - Documentation comments and docstrings
- `--structure` - Code organization without implementations
- `--imports` - Import/include statements and dependencies
- `--errors` - Error handling patterns and definitions
- `--tests` - Test functions and test-related code
- `--full` - Complete file content (default, backward compatible)

**Flag Combination:** Multiple flags can be combined: `--signatures --types --docs`

**Supported Languages:**
- **Zig** - Functions, structs, enums, tests, errors, imports
- **JS/TypeScript** - Functions, classes, interfaces, imports
- **Python** - Functions, classes, decorators, imports
- **Rust** - Functions, structs, enums, traits, tests, errors
- **Go** - Functions, structs, interfaces, packages, errors
- **C/C++** - Functions, structs, typedefs, includes
- **Fallback** - Plain text extraction for unsupported languages

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
- `*.{js,ts}` - JS/TypeScript
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
// extracted content based on flags
// for --full: complete file content
// for --signatures: function signatures only
// for combination flags: merged relevant sections
```

</File>
```

**Features:**
- XML tags for LLM semantic context
- Automatic syntax highlighting by extension
- Language-aware content extraction via tree-sitter
- Intelligent section selection based on extraction flags
- 10MB file size limit with warnings
- Smart fence handling for nested blocks
- Preserves code structure and relationships

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
  
  # Content Options
  --prepend=TEXT        # Add before files
  --append=TEXT         # Add after files
  
  # Error Handling
  --allow-empty-glob    # Warn on empty globs
  --allow-missing       # Warn on missing files
  --no-gitignore        # Disable gitignore
  
  # Code Extraction (can be combined)
  --signatures          # Function/method signatures
  --types              # Type definitions
  --docs               # Documentation comments
  --structure          # Code organization
  --imports            # Import statements
  --errors             # Error handling
  --tests              # Test functions
  --full               # Complete content (default)
```

**Usage Examples:**
```bash
# Extract only function signatures from Zig files
zz prompt src/**/*.zig --signatures

# Get types and documentation for review
zz prompt src/**/*.{zig,h} --types --docs

# Full codebase overview with structure
zz prompt src/ --structure --imports

# Default behavior (backward compatible)
zz prompt src/main.zig  # equivalent to --full
```

## Performance Characteristics

- **Arena allocators:** Reduce allocation overhead
- **Fast-path globs:** 40-60% speedup for common patterns
- **O(1) deduplication:** StringHashMap for efficiency
- **Early skip:** Ignored directories never opened
- **Lazy parsing:** Tree-sitter parsing only when extraction flags used
- **Cached parsers:** Language parsers reused across files
- **Selective extraction:** Only parse relevant syntax nodes

## Architectural Strengths

1. **Modular design:** Clear component boundaries with shared lib integration
2. **Performance-conscious:** Arena allocators, fast-paths, lazy parsing
3. **Language-aware:** Tree-sitter integration for precise code understanding
4. **Flexible extraction:** Eight specialized modes for different workflows
5. **Robust error handling:** Multiple modes for different use cases
6. **Comprehensive testing:** Edge cases thoroughly covered
7. **Filesystem abstraction:** Enables isolated testing
8. **Memory safety:** Proper cleanup with errdefer
9. **Backward compatible:** Default --full preserves existing behavior
10. **Unix philosophy:** Composable with clear I/O

## Implementation Notes

### ExtractionFlags Integration

The `Config` struct now includes `ExtractionFlags` to control parsing behavior:
```zig
pub const Config = struct {
    extraction_flags: ExtractionFlags,
    // ... other fields
};
```

### PromptBuilder Enhancement

`PromptBuilder.buildPrompt()` accepts extraction flags parameter:
```zig
pub fn buildPrompt(
    self: *PromptBuilder, 
    paths: []const []const u8, 
    extraction_flags: ExtractionFlags
) !void
```

When extraction flags are specified (not `--full`), the builder uses `../lib/parser.zig` for language-aware content extraction. For `--full` or unsupported languages, it falls back to complete file inclusion for backward compatibility.