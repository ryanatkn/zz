# Ideas for Next Steps

## ✅ COMPLETED: Basic Extraction Infrastructure
**What we've accomplished:**
- Tree-sitter dependency integrated via Zig package manager
- Basic extraction flags implemented (--signatures, --types, --docs, etc.)
- Simple text-based extraction working for Zig
- All tests passing, documentation updated
- Backward compatible (defaults to --full)
- Created `src/lib/c.zig` for centralized C imports (ready for language grammars)

## 1. Complete Tree-sitter AST Integration (High Priority)
**Impact: Precise, language-aware extraction instead of text matching**

### Implement Tree-sitter Queries
**Current state:** Using simple text matching (grep-like)
**Goal:** Use tree-sitter's AST for precise extraction

```zig
// src/lib/parser.zig enhancement needed
pub fn extractWithTreeSitter(self: *Parser, source: []const u8, flags: ExtractionFlags) ![]const u8 {
    const parser = ts.Parser.create();
    defer parser.destroy();
    
    const language = try self.getTreeSitterLanguage();
    try parser.setLanguage(language);
    
    const tree = try parser.parseString(source, null);
    defer tree.destroy();
    
    // Use tree-sitter queries for extraction
    const query = try self.buildQuery(flags);
    const cursor = try ts.QueryCursor.create();
    defer cursor.destroy();
    
    // Extract matching nodes...
}
```

### Add Language Grammars
**Current:** Only Zig with text matching
**Infrastructure ready:** `src/lib/c.zig` prepared for grammar imports

```zig
// src/lib/c.zig is ready for:
pub const ts_zig = @cImport({
    @cInclude("tree-sitter-zig.h");
});

// Then in parser.zig:
const c = @import("c.zig");
const language = c.ts_zig.tree_sitter_zig();
try parser.setLanguage(language);
```

**Next steps:**
1. Add tree-sitter-zig as a dependency
2. Link the C library in build.zig
3. Import via c.zig
4. Replace text matching with AST queries

### Fix Test Module Issues
- Resolve `extraction_test.zig` module path problem
- Add comprehensive AST-based extraction tests
- Benchmark extraction performance vs full source

## 2. Advanced Extraction Features (Medium Priority)
**Impact: Surgical precision in code extraction**

### Pattern-Based Focus
```bash
# Extract everything about database connections
zz prompt src/ --match="database|connection|query" --context=3

# Extract error handling patterns
zz prompt src/ --match="error|catch|try|panic" --depth=function
```

### Semantic Extraction
```bash
# Extract all public APIs
zz prompt src/ --semantic=public-api

# Extract dependency graph
zz prompt src/ --semantic=imports --format=dot

# Extract all TODO/FIXME comments with context
zz prompt src/ --semantic=todos --context=5
```

### Relevance Scoring
- Implement TF-IDF scoring for relevance to query
- Use import/dependency distance for context
- Add `--relevance-threshold` to filter noise

## 3. Performance Optimizations (High Priority)
**Impact: 10-100x speedup for large codebases**

### Parallel Processing
- Parse files in parallel using worker threads
- Stream output as files are processed
- Add progress indicator for large operations

### Caching Strategy
```zon
.prompt = .{
    .cache_dir = "~/.zz/cache/ast",
    .cache_ttl_seconds = 3600,
    .cache_key = "content-hash",  // or "mtime" for speed
}
```

### Memory Optimization
- Use memory-mapped files for large codebases
- Implement streaming parsers for huge files
- Add `--max-memory` limit with graceful degradation

## 4. Output Format Enhancements (Medium Priority)
**Impact: Better integration with tools and workflows**

### Structured Output
```bash
# JSON with metadata
zz prompt src/ --format=json --include-stats
{
  "files": [...],
  "stats": {
    "total_files": 42,
    "extraction_time_ms": 234,
    "tokens_extracted": 5678
  }
}

# NDJSON for streaming
zz prompt src/ --format=ndjson --stream
```

### Interactive Mode
```bash
zz prompt --interactive
> load src/
Loaded 42 files (2.3MB)
> show functions matching "parse"
Found 7 functions...
> extract parseConfig at LOD 3
```

## 5. Smart Profiles and Presets (Low Priority)
**Impact: Better UX for common workflows**

### Task-Oriented Profiles
```bash
# Automatic profile selection based on task
zz prompt src/ --task=code-review
# Extracts: public APIs, complex functions, recent changes

zz prompt src/ --task=security-audit  
# Extracts: auth code, crypto, input validation, SQL queries

zz prompt src/ --task=performance
# Extracts: loops, algorithms, allocations, benchmarks
```

### Custom Profiles in Config
```zon
.prompt.profiles = .{
    .company_standard = .{
        .flags = .{ "signatures", "types", "docs" },
        .skip_tests = true,
        .max_file_size = 100000,
    },
}
```

## 6. Integration Features (Medium Priority)
**Impact: Seamless workflow integration**

### Git Integration
```bash
# Extract only changed files
zz prompt --git-diff=HEAD~5

# Extract files changed in PR
zz prompt --git-pr=123
```

### Editor Integration
- VSCode extension to run extraction from editor
- Neovim plugin for quick extraction
- Sublime Text package

### CI/CD Integration
```yaml
# GitHub Action
- uses: zz-cli/extract-action@v1
  with:
    files: 'src/**/*.zig'
    flags: '--signatures --types'
    output: 'api-docs.md'
```

## 7. Intelligence Features (Low Priority, High Impact)
**Impact: Next-level code understanding**

### Local LLM Integration (Optional)
```bash
# Summarize complex functions
zz prompt src/ --summarize --llm=ollama:codellama

# Generate descriptions
zz prompt src/ --describe-types --llm=local
```

### Code Complexity Analysis
```bash
# Show only complex code needing review
zz prompt src/ --complexity-threshold=10

# Extract code with high cyclomatic complexity
zz prompt src/ --filter=complex
```

### Semantic Search
```bash
# Find conceptually similar code
zz prompt --search="validate user input"

# Find implementations of a pattern
zz prompt --find-pattern="singleton"
```

## 8. Developer Experience (High Priority)
**Impact: Delightful to use**

### Better Error Messages
- Show exactly what was being extracted when errors occur
- Suggest fixes for common issues
- Add `--debug` flag for troubleshooting

### Dry Run and Preview
```bash
# Show what would be extracted without doing it
zz prompt src/ --signatures --dry-run
Would extract:
  142 function signatures
  31 type definitions
  Estimated output: 15KB

# Preview first N results
zz prompt src/ --signatures --preview=5
```

### Progress and Statistics
```bash
# Rich progress display
zz prompt "**/*.zig" --signatures --progress
[████████████████░░░░] 78% | 234/300 files | 2.3s elapsed | 0.7s remaining

# Post-extraction statistics
Extracted 1,234 signatures from 300 files in 3.2s
Output size: 45KB (compressed from 2.3MB, 95% reduction)
```

## 9. Testing and Quality (High Priority)
**Impact: Reliability and confidence**

### Comprehensive Test Suite
- Golden tests for each language
- Property-based testing for extraction
- Fuzzing for parser robustness
- Performance regression tests

### Benchmarking Suite
```bash
# Add extraction benchmarks
zig build benchmark
Extraction Benchmarks:
  Full source:      2.3ms/file
  Signatures only:  0.4ms/file (83% faster)
  With AST cache:   0.1ms/file (96% faster)
```

## 10. Documentation and Examples (Medium Priority)
**Impact: Adoption and understanding**

### Cookbook Examples
- "Extracting API documentation"
- "Preparing code for AI review"
- "Creating minimal bug reproductions"
- "Analyzing large codebases"

### Video Tutorials
- "5-minute intro to intelligent extraction"
- "Advanced extraction techniques"
- "Integration with AI tools"

## Priority Matrix (Updated)

### ✅ Completed
1. ~~Tree-sitter dependency integration~~
2. ~~Basic extraction flags (8 types)~~
3. ~~Text-based extraction for Zig~~
4. ~~Documentation and help updates~~
5. ~~Test infrastructure (mostly)~~

### Must Have (Next Week)
1. Implement actual tree-sitter AST queries
2. Add tree-sitter-zig grammar
3. Fix extraction_test.zig module issues
4. Add performance benchmarks for extraction
5. Create tree-sitter query files (.scm)

### Should Have (This Month)
1. TypeScript/JS support with grammars
2. Pattern-based extraction (`--match`)
3. AST caching for performance
4. JSON/NDJSON output format
5. Rust and Go language support

### Nice to Have (Next Quarter)
1. Interactive mode
2. Local LLM integration
3. Semantic search
4. Editor plugins
5. Cloud caching service

## Technical Debt to Address
- Refactor parser.zig to use proper tree-sitter queries
- Add proper error handling for malformed code
- Implement streaming for large file handling
- Create language-agnostic extraction interface
- Add telemetry for usage patterns (opt-in)

## Experimental Ideas
- **WebAssembly build**: Run zz in the browser
- **Language server**: Provide extraction as LSP service
- **Distributed extraction**: Process massive codebases across machines
- **AI-guided extraction**: Use embeddings to find relevant code
- **Extraction macros**: User-defined extraction patterns

## Success Metrics
- Extraction speed: <5ms per file for signatures
- Memory usage: <100MB for 10K file codebase  
- Output reduction: 80-95% size reduction with key info preserved
- Language support: 20+ languages within 6 months
- User adoption: 1000+ GitHub stars within a year

## Next Immediate Steps (Concrete Actions)

### Week 1: Complete Tree-sitter Integration
```bash
# 1. Add tree-sitter-zig grammar (find correct repo)
# Note: Need to find Zig grammar with C bindings
# https://github.com/tree-sitter/zig-tree-sitter 
#  zig fetch --save git+https://github.com/tree-sitter-grammars/tree-sitter-zig.git (is this right?)

# 2. Update src/lib/c.zig to import the grammar
# Uncomment and update the ts_zig section

# 3. Create query files for extraction
mkdir src/queries
cat > src/queries/zig.scm << 'EOF'
; Function signatures
(function_declaration
  name: (identifier) @function.name) @function

; Type definitions  
(struct_declaration) @type
(enum_declaration) @type

; Constants and variables
(variable_declaration
  name: (identifier) @constant.name) @constant
EOF

# 4. Update parser.zig to use real AST
# Replace extractSimple() with extractWithTreeSitter()

# 4. Add extraction benchmarks
zig build benchmark --only=extraction
```

### Week 2: Expand Language Support
```bash
# Add TypeScript grammar and queries
zig fetch --save=tree_sitter_typescript https://github.com/tree-sitter/tree-sitter-typescript

# Test on real projects
zz prompt node_modules/**/*.ts --signatures
```

### Week 3: Performance & Polish
- Implement AST caching with content hashing
- Add streaming NDJSON output
- Create extraction cookbook
- Fix extraction_test.zig module path issue

## Current State Summary

**What Works Today:**
```bash
# These all work with text-based extraction:
zz prompt src/*.zig --signatures    # Extract function signatures
zz prompt src/*.zig --types --docs   # Types with documentation
zz prompt src/*.zig --errors --tests # Error handling and tests
zz prompt src/*.zig                  # Default: full source (--full)
```

**Architecture Ready:**
```
src/
├── lib/
│   ├── parser.zig         # Extraction logic (text-based for now)
│   └── c.zig              # Centralized C imports (ready for grammars)
├── prompt/
│   ├── config.zig         # ExtractionFlags configuration
│   └── builder.zig        # Integrated with parser
└── cli/
    └── help.zig           # Documents all extraction flags
```

**What's Next (Concrete):**
1. Find and add tree-sitter-zig grammar with C bindings
2. Implement AST-based extraction in parser.zig
3. Create .scm query files for each extraction type
4. Add TypeScript, Rust, Go grammars
5. Benchmark: target <5ms per file with AST

**The Big Picture:**
- **Today:** Text matching (fast but imprecise)
- **Next Week:** AST parsing for Zig (precise extraction)
- **Next Month:** 5+ languages with full AST support
- **Goal:** The definitive tool for intelligent code extraction

The foundation is solid. The infrastructure is ready. Now we implement.