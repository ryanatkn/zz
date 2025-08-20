# Core Module - Fundamental Utilities

Essential utilities and types that are used throughout the zz codebase. Performance-optimized for POSIX systems.

## Module Structure

```
src/lib/core/
├── language.zig       # Language detection and enumeration
├── extraction.zig     # Code extraction configuration flags
├── path.zig           # POSIX-optimized path operations
├── collections.zig    # Memory-efficient data structures
├── filesystem.zig     # Filesystem utilities and error handling
├── io.zig             # I/O utilities and buffering
├── reporting.zig      # Consistent CLI error and status reporting
└── traversal.zig      # Directory traversal with pattern support
```

## Key Components

### Language Detection (`language.zig`)

**Purpose:** Centralized language detection and capabilities

**Features:**
- File extension to language mapping
- Language capability queries (formatting, linting)
- Consistent enumeration across all modules

**API:**
```zig
const lang = Language.fromPath("src/main.zig");  // Returns .zig
const ext = Language.zig.getExtensions();        // Returns [".zig"]
const can_format = lang.supportsFormatting();    // Returns true
```

**Supported Languages:**
- Zig, TypeScript/JavaScript, CSS, HTML, JSON, ZON, Svelte

### Extraction Configuration (`extraction.zig`)

**Purpose:** Configure what code elements to extract

**Extraction Flags:**
- `signatures` - Function/method signatures
- `types` - Type definitions
- `docs` - Documentation comments
- `structure` - Code organization
- `imports` - Import statements
- `errors` - Error handling
- `tests` - Test functions
- `full` - Complete content (default)

**API:**
```zig
const flags = ExtractionFlags.forApiDocs();  // Signatures, types, docs
const zon = try flags.toZon(allocator);       // Serialize to ZON
```

### Path Operations (`path.zig`)

**Purpose:** High-performance POSIX path manipulation

**Optimizations:**
- Direct buffer manipulation (no allocations)
- Hardcoded `/` separator (POSIX-only)
- Pre-calculated buffer sizes

**Key Functions:**
```zig
joinPath()      // Two-component joining
joinPaths()     // Multi-component with pre-calculated sizes
basename()      // Extract filename
normalizePath() // Remove redundant separators
isHiddenFile()  // Dot-file detection
```

### Collections (`collections.zig`)

**Purpose:** Memory-efficient data structures

**Components:**
- `ManagedArrayList` - RAII ArrayList with automatic cleanup
- `StringPool` - String interning for deduplication
- `PathCache` - Cached path operations

**Performance:**
- Arena allocators for temporary collections
- Capacity retention for reused lists
- Size-based pooling strategies

### Reporting (`reporting.zig`)

**Purpose:** Consistent CLI error and status reporting across all commands

**Functions:**
- `reportError` - Errors that prevent operation (stderr, "Error:" prefix)
- `reportWarning` - Issues that don't prevent continuation (stderr, "Warning:" prefix)  
- `reportInfo` - Status information (stderr, no prefix)
- `reportSuccess` - Successful operations (stdout, no prefix)
- `reportDebug` - Diagnostic information (stderr, no prefix)
- `printUsage` - Help/usage text (stderr, no prefix)

**Benefits:**
- Unified message formatting across format, prompt, tree, deps commands
- Consistent prefix usage and output stream routing
- Easier to maintain and modify error reporting behavior

**API:**
```zig
const reporting = @import("lib/core/reporting.zig");

try reporting.reportError("Failed to process file '{s}': {s}", .{ path, @errorName(err) });
try reporting.reportWarning("Unknown file type for '{s}', skipping", .{path});
try reporting.reportSuccess("Formatted {s}", .{path});
```

### Filesystem (`filesystem.zig`)

**Purpose:** Robust filesystem operations with error handling

**Error Categories:**
- **Safe to ignore:** FileNotFound, AccessDenied
- **Must propagate:** OutOfMemory, SystemResources
- **Config-specific:** Missing configs use defaults

**Key Functions:**
```zig
safeFileOperation()  // Wrapped file ops with error classification
gracefulOpenFile()   // Consistent error handling
ensureDir()          // Create with parent directories
```

## Performance Characteristics

- **Path operations:** ~47μs/op
- **String interning:** ~145ns/op
- **Directory traversal:** Early skip optimization
- **Memory pools:** ~50μs/cycle

## Design Principles

1. **POSIX-only focus:** No Windows overhead
2. **Zero allocations:** Where possible
3. **Arena allocators:** For temporary operations
4. **Error resilience:** Graceful degradation
5. **Cache efficiency:** String interning, path caching

## Usage Examples

### Language Detection
```zig
const Language = @import("lib/core/language.zig").Language;

pub fn processFile(path: []const u8) !void {
    const lang = Language.fromPath(path);
    if (lang.supportsFormatting()) {
        // Format the file...
    }
}
```

### Extraction Configuration
```zig
const ExtractionFlags = @import("lib/core/extraction.zig").ExtractionFlags;

// API documentation mode
const flags = ExtractionFlags{
    .signatures = true,
    .types = true,
    .docs = true,
};

// Or use preset
const flags = ExtractionFlags.forAnalysis();
```

### Path Operations
```zig
const path_utils = @import("lib/core/path.zig");

const full_path = try path_utils.joinPaths(allocator, &.{
    "/home", "user", "project", "src", "main.zig"
});
const filename = path_utils.basename(full_path);  // "main.zig"
```

## Migration from Legacy

**Before (legacy lib/language/):**
```zig
const Language = @import("lib/language/detection.zig").Language;
const flags = @import("lib/language/flags.zig").ExtractionFlags;
```

**After (core module):**
```zig
const Language = @import("lib/core/language.zig").Language;
const ExtractionFlags = @import("lib/core/extraction.zig").ExtractionFlags;
```

## Integration Points

- **Format module:** Uses language detection for formatter dispatch
- **Prompt module:** Uses extraction flags for code selection
- **AST module:** Uses collections for efficient node storage
- **All modules:** Use path utilities for file operations

The core module provides the fundamental building blocks that make zz fast, reliable, and maintainable.