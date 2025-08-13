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
| `parser.zig` | Language-aware code extraction | Tree-sitter ready architecture |
| `ast.zig` | AST traversal framework | NodeVisitor pattern |
| `cache.zig` | LRU caching system | ~95% cache efficiency |
| `incremental.zig` | Change detection & state | ~2-5ms change detection |
| `parallel.zig` | Worker pools & scheduling | Linear CPU scaling |
| `file_helpers.zig` | Consolidated file operations | Eliminated 15+ patterns |
| `error_helpers.zig` | Standardized error handling | Eliminated 20+ switch statements |
| `collection_helpers.zig` | Memory-managed collections | Eliminated 30+ ArrayList patterns |
| `ast_walker.zig` | Unified AST traversal | Consolidated 5+ walkNode implementations |
| `code_analysis.zig` | Advanced code analysis | Call graphs & dependency analysis |
| `semantic_analysis.zig` | Intelligent code summarization | LLM context optimization |

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
- **Initial directory handling:** Special treatment for starting directory to allow "." traversal

**Key API:**
```zig
DirectoryTraverser.collectFiles() // Build file lists with patterns
```

**Implementation Details:**
- `traverseRecursiveInternal` accepts `is_initial` flag to skip ignore checks on starting directory
- Ensures "." can be used as starting point for directory traversal
- Subdirectories still respect ignore patterns normally

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

## parser.zig - Language-Aware Code Extraction

**NEW:** Language-aware code parsing and extraction system designed for LLM prompt generation with future tree-sitter AST integration.

**Architecture Philosophy:**
- **Text-based foundation:** Fast, reliable extraction without external dependencies
- **Tree-sitter ready:** API designed for seamless AST integration
- **Language extensible:** Easy addition of new programming languages
- **Performance-focused:** Efficient extraction for large codebases

### Language Detection

**Supported Languages:**
```zig
// Comprehensive language support with file extension mapping
.zig     -> Language.zig          // Primary language
.c, .h   -> Language.c            // C programming
.cpp, .hpp, .cc, .cxx -> Language.cpp  // C++
.js, .jsx -> Language.javascript  // JS
.ts, .tsx -> Language.typescript  // TypeScript  
.py      -> Language.python       // Python
.rs      -> Language.rust         // Rust
.go      -> Language.go           // Go
.java    -> Language.java         // Java
.*       -> Language.generic      // Fallback
```

**Detection API:**
```zig
const language = Parser.detectLanguage("src/main.zig");
// Returns Language.zig for Zig files

const lang_str = Parser.languageToString(language);
// Returns "zig" for display/logging
```

### Extraction Configuration

**ExtractionFlags Structure:**
```zig
const ExtractionFlags = struct {
    // Content selection
    functions: bool = true,        // Function/method definitions
    structs: bool = true,          // Struct/class/interface definitions
    constants: bool = true,        // Constants, enums, static values
    imports: bool = true,          // Import/include/use statements
    comments: bool = false,        // Documentation comments
    
    // Extraction control
    include_bodies: bool = false,  // Function bodies vs signatures only
    include_private: bool = true,  // Private/internal members
    max_depth: u32 = 0,           // Nested extraction depth (0 = unlimited)
};
```

**Common Extraction Patterns:**
```zig
// API documentation - signatures only
const api_flags = ExtractionFlags{
    .functions = true,
    .structs = true,
    .include_bodies = false,  // Signatures for better LLM context
    .include_private = false, // Public API only
    .comments = true,         // Include documentation
};

// Code analysis - full structure
const analysis_flags = ExtractionFlags{
    .functions = true,
    .structs = true,
    .constants = true,
    .include_bodies = true,   // Full implementation details
    .comments = false,        // Focus on code structure
};

// Quick overview - minimal extraction
const overview_flags = ExtractionFlags{
    .functions = true,
    .structs = true,
    .constants = false,
    .imports = true,
    .include_bodies = false,  // Structure only
};
```

### Current Implementation: Text-Based Extraction

**Language-Specific Patterns:**
- **Zig:** `pub fn`, `const`, `var`, `struct`, `enum`, `@import`
- **C/C++:** Function signatures, struct/class definitions, #include statements
- **JS/TypeScript:** Function declarations, class definitions, import/export
- **Python:** def, class, import statements with proper indentation handling
- **Rust:** fn, struct, enum, use statements, impl blocks
- **Go:** func, struct, type, import declarations
- **Java:** method signatures, class definitions, import statements

**Text Processing Features:**
- **Multi-line aware:** Handles function signatures spanning multiple lines
- **Comment preservation:** Extracts documentation comments when requested
- **Scope detection:** Understands basic code structure and nesting
- **Error resilient:** Graceful handling of malformed or incomplete code

**Performance Characteristics:**
- **Linear complexity:** O(n) with file size, single-pass processing
- **Low memory overhead:** Streaming extraction without full AST
- **Fast startup:** No parser initialization or grammar loading
- **Language scaling:** Consistent performance across all supported languages

### Future Tree-Sitter Integration

**Planned API Extensions:**
```zig
const ParserOptions = struct {
    extraction_flags: ExtractionFlags,
    
    // Future tree-sitter options
    use_ast: bool = false,           // Enable AST-based parsing
    preserve_formatting: bool = true, // Maintain original code style
    extract_metadata: bool = false,   // Include position/semantic info
    cache_parsers: bool = true,       // Cache parsers for repeated use
};

// Future extraction with AST
const extracted = try parser.extractCodeAdvanced("src/main.zig", content, .{
    .extraction_flags = flags,
    .use_ast = true,
    .preserve_formatting = true,
});
```

**Tree-Sitter Benefits:**
- **Precise extraction:** AST eliminates false positives from regex patterns
- **Semantic awareness:** Understanding of variable scope and code relationships  
- **Language completeness:** Full grammar support for complex syntax
- **Incremental parsing:** Efficient updates for changed files
- **Robust error handling:** Graceful parsing of incomplete/malformed code

### Integration with Prompt Module

**Seamless Integration:**
```zig
// In prompt/builder.zig - automatic extraction during file processing
const parser = try Parser.init(allocator);
defer parser.deinit();

for (files) |file_path| {
    const content = try fs.readFileAlloc(allocator, file_path);
    defer allocator.free(content);
    
    // Extract relevant code sections for LLM context
    const extracted = try parser.extractCode(file_path, content, .{
        .functions = true,
        .structs = true,
        .include_bodies = false,  // Signatures reduce token usage
        .comments = true,         // Preserve documentation
    });
    defer allocator.free(extracted);
    
    try builder.addCodeSection(file_path, extracted);
}
```

**LLM Optimization Features:**
- **Token efficiency:** Extract signatures without implementation details
- **Context preservation:** Maintain file structure and imports
- **Documentation focus:** Include relevant comments for understanding
- **Relationship mapping:** Future AST integration will show code dependencies

### Error Handling and Resilience

**Graceful Degradation:**
```zig
// Unknown language fallback
if (language == .generic) {
    // Return raw content with basic filtering
    return try filterGenericContent(content, flags);
}

// Malformed code handling
if (extraction_failed) {
    // Fall back to raw content rather than failing
    return content;  // or filtered version
}
```

**Error Categories:**
- **Language detection:** Unknown extensions use generic text processing
- **Syntax errors:** Malformed code falls back to raw content
- **Memory issues:** Streaming processing for large files
- **Encoding problems:** UTF-8 validation with replacement characters

### Performance Benchmarks

**Current Text-Based Performance (Debug build):**
- **Small files (< 10KB):** ~2-5μs extraction time
- **Medium files (10-100KB):** ~15-50μs extraction time  
- **Large files (100KB-1MB):** ~150-500μs extraction time
- **Memory usage:** ~1.5x file size during processing
- **Language overhead:** <1μs difference between languages

**Expected Tree-Sitter Performance:**
- **Parser initialization:** ~10-50ms per language (cached)
- **AST parsing:** ~2-5x slower than text-based for initial parse
- **Incremental updates:** ~10-20x faster for changed files
- **Memory usage:** ~3-5x file size for full AST representation

### Usage Examples

**Basic extraction with language auto-detection:**
```zig
const parser = try Parser.init(allocator);
defer parser.deinit();

const content = try std.fs.cwd().readFileAlloc(allocator, "src/main.zig", 1024 * 1024);
defer allocator.free(content);

const extracted = try parser.extractCode("src/main.zig", content, .{});
defer allocator.free(extracted);

// Result contains function signatures, struct definitions, imports
```

**Documentation-focused extraction:**
```zig
const docs_flags = ExtractionFlags{
    .functions = true,
    .structs = true,
    .constants = true,
    .comments = true,         // Include documentation
    .include_bodies = false,  // Signatures only for clarity
    .include_private = false, // Public API focus
};

const api_docs = try parser.extractCode("src/api.zig", content, docs_flags);
```

**Full code analysis:**
```zig
const analysis_flags = ExtractionFlags{
    .functions = true,
    .structs = true,
    .constants = true,
    .imports = true,
    .include_bodies = true,   // Full implementation
    .include_private = true,  // Complete picture
};

const full_code = try parser.extractCode("src/complex.zig", content, analysis_flags);
```

### Testing Strategy

**Comprehensive Test Coverage:**
- **Language detection:** All supported file extensions
- **Extraction accuracy:** Function/struct detection across languages
- **Edge cases:** Empty files, malformed code, very large files
- **Performance:** Benchmark extraction speed across languages
- **Integration:** End-to-end testing with prompt module

**Test Organization:**
```
src/lib/test/
├── parser_test.zig           # Core parser functionality
├── language_detection_test.zig # File extension mapping
├── extraction_flags_test.zig   # Configuration testing
└── integration_test.zig        # Cross-module integration
```

### Development Roadmap

**Phase 1 (Current): Text-Based Foundation**
- ✓ Language detection from file extensions
- ✓ Configurable extraction with ExtractionFlags
- ✓ Multi-language text-based extraction
- ✓ Integration with prompt module

**Phase 2 (Next): Tree-Sitter Integration**
- 🔄 Tree-sitter language parsers integration
- 🔄 AST-based extraction with semantic awareness
- 🔄 Incremental parsing for large codebases
- 🔄 Enhanced error recovery and malformed code handling

**Phase 3 (Future): Advanced Features**
- 🔄 Language Server Protocol integration
- 🔄 Cross-reference analysis (function calls, imports)
- 🔄 Semantic code similarity detection
- 🔄 Code completion and suggestion for LLMs

The parser module represents a significant advancement in zz's code analysis capabilities, providing a foundation for intelligent code extraction that will greatly enhance LLM prompt generation quality and efficiency.

## file_helpers.zig - Consolidated File Operations

**DRY Achievement:** Eliminated 15+ duplicate file reading patterns across the codebase.

**Core Components:**
```zig
SafeFileReader     // RAII file reading with automatic cleanup
hashFile()         // xxHash-based file content hashing  
getModTime()       // Cross-platform modification time
ensureDir()        // Directory creation with parent support
```

**Features:**
- **RAII Pattern:** Automatic file handle cleanup with defer
- **Optional vs Required:** Clear distinction between optional and error-on-missing
- **Standardized Errors:** Consistent error handling across all file operations
- **Buffer Management:** Reusable buffers with size limits
- **Performance:** Direct syscalls where possible, avoiding allocations

## error_helpers.zig - Standardized Error Handling

**DRY Achievement:** Eliminated 20+ switch statement patterns for error classification.

**Core Components:**
```zig
Result(T)              // Unified success/error return types
safeFileOperation()    // Common error handling wrapper
gracefulOpenFile()     // Consistent file access with error classification
```

**Error Categories:**
- **Safe to ignore:** FileNotFound, AccessDenied, NotDir
- **Must propagate:** OutOfMemory, SystemResources  
- **Config-specific:** Missing config files use defaults

## collection_helpers.zig - Memory-Managed Collections  

**DRY Achievement:** Eliminated 30+ ArrayList initialization patterns with unified memory management.

**Core Components:**
```zig
ManagedArrayList(T)    // RAII ArrayList with automatic cleanup
ArrayListBuilder(T)    // Fluent builder pattern for collections
ScopedAllocation(T)    // Automatic memory management for slices
StringListBuilder      // Specialized string collection handling
```

**Features:**
- **RAII Cleanup:** Automatic memory management with defer patterns
- **Fluent Interface:** Builder pattern for readable collection construction
- **Capacity Retention:** Smart capacity management for performance
- **Helper Operations:** deduplicate(), filter(), map(), joinStrings()
- **Safe Popping:** popSafe() returns optional instead of panicking

## ast_walker.zig - Unified AST Traversal

**DRY Achievement:** Consolidated 5+ identical walkNode implementations into shared infrastructure.

**Core Components:**
```zig
WalkContext        // Shared context for all AST operations
BaseWalker         // Common traversal logic for all parsers
GenericVisitor     // Language-agnostic node processing
shouldExtract()    // Unified flag-based node filtering
```

**Features:**
- **Unified Interface:** All parsers use the same walkNode signature
- **Flag-Based Extraction:** Consistent shouldExtract() logic for all languages
- **Visitor Pattern:** Extensible node processing with visitor functions
- **Context Sharing:** Reduce parameter passing with shared WalkContext
- **Language Agnostic:** Generic patterns work across all supported languages

## code_analysis.zig - Advanced Code Analysis

**Features:** Call graph generation, dependency analysis, and code metrics for intelligent LLM context.

**Core Components:**
```zig
CallGraphBuilder       // Generate function dependency graphs
DependencyAnalyzer     // Track import/module relationships  
MetricsCalculator      // Code complexity analysis
```

**Capabilities:**
- **Function Dependencies:** Build call graphs showing function relationships
- **Module Dependencies:** Track import/export relationships across files
- **Complexity Metrics:** Cyclomatic complexity, depth analysis, code size
- **LLM Optimization:** Identify most relevant code for prompts

## semantic_analysis.zig - Intelligent Code Summarization

**Features:** File relevance scoring and intelligent code summarization for optimal LLM context selection.

**Core Components:**
```zig
FileRelevance      // Scoring system for LLM context selection
CodeSummarizer     // Extract key code insights
ContextSelector    // Choose relevant files for prompts
```

**Capabilities:**
- **Relevance Scoring:** Rank files by importance for LLM context
- **Smart Summarization:** Extract key insights from code structure
- **Context Selection:** Choose optimal files within token limits
- **Cross-Reference:** Track relationships between code elements

## Cross-Module Integration

- **DRY Helper Modules:** Eliminated ~500 lines of duplicate code through 6 shared modules
- **Shared patterns:** Error handling used across all modules via error_helpers.zig
- **Path utilities:** Replace stdlib for performance with path.zig optimizations
- **Traversal:** Supports both tree and prompt with unified traversal.zig
- **Memory management:** Reduces allocation pressure via collection_helpers.zig
- **Performance validation:** Measures optimization effectiveness through benchmark.zig
- **Code extraction:** Parser integrates with prompt via ast_walker.zig for intelligent content generation
- **File operations:** Consistent file I/O patterns through file_helpers.zig
- **Advanced analysis:** Code analysis and semantic analysis provide LLM optimization

## Architectural Decisions

1. **POSIX-only focus:** Eliminates cross-platform overhead
2. **Arena allocators:** Temporary allocations during traversal
3. **Capacity retention:** ArrayLists keep capacity when pooled
4. **Size-based pooling:** Different strategies by allocation size
5. **Graceful degradation:** Robust real-world operation
6. **Text-first parsing:** Fast extraction without AST overhead, tree-sitter ready architecture
7. **Language extensibility:** Simple addition of new programming languages
8. **LLM optimization:** Token-efficient extraction focused on signatures and structure