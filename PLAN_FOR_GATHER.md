# Plan for `zz gather` Command

## Vision

`zz gather` transforms codebases into intelligently compressed representations with variable Levels of Detail (LOD), similar to how video games dynamically adjust visual fidelity based on distance and importance. This enables AI assistants and developers to work with exactly the right amount of context - from high-level architecture overviews to detailed implementation specifics.

## Core Concept: Levels of Detail (LOD)

### The Problem
Current tools provide either everything (full source) or nothing (file names). Real understanding requires different zoom levels:
- **LOD 0**: File structure only (like `tree`)
- **LOD 1**: Declarations and signatures (public API surface)
- **LOD 2**: Declarations + doc comments + types
- **LOD 3**: Full implementations with selective elision
- **LOD 4**: Complete source code

### The Solution
Language-aware parsing that extracts semantic structure, allowing dynamic detail adjustment based on:
- **Relevance**: More detail for files matching the query pattern
- **Distance**: Less detail for files further from the focus area
- **Importance**: More detail for frequently-used or complex code
- **Context**: Adaptive detail based on the analysis goal

## Design Principles

### 1. Language-Aware Extraction
Use proper parsers (not regex) to understand code structure:
- **Zig**: Parse AST to extract `pub fn`, `const`, structs, etc.
- **TypeScript**: Extract interfaces, type declarations, function signatures
- **Svelte**: Component props, exported functions, stores
- **Markdown**: Heading structure, first/last sentences, code blocks

### 2. Semantic Compression
Not just text truncation, but meaningful reduction:
```zig
// LOD 1: Declaration only
pub fn processData(input: []const u8) !Result

// LOD 2: Declaration + docs
/// Processes input data with error handling
pub fn processData(input: []const u8) !Result

// LOD 3: Declaration + structure
pub fn processData(input: []const u8) !Result {
    // validation logic...
    // transformation logic...
    // return result
}

// LOD 4: Full implementation
pub fn processData(input: []const u8) !Result {
    if (input.len == 0) return error.EmptyInput;
    const validated = try validate(input);
    const transformed = try transform(validated);
    return Result{ .data = transformed };
}
```

### 3. Contextual Intelligence
Adjust detail based on gathering context:
- **Architecture Review**: High-level structure, public APIs
- **Bug Investigation**: Full detail around error handling
- **Performance Analysis**: Focus on hot paths and algorithms
- **Documentation**: Signatures and doc comments
- **Refactoring**: Type relationships and dependencies

## Implementation Strategy

### Phase 1: Core Infrastructure
**Timeline**: 2-3 weeks

#### Language Parser Integration
```zig
pub const Parser = union(enum) {
    zig: ZigParser,
    typescript: TypeScriptParser,
    markdown: MarkdownParser,
    plaintext: PlaintextParser,
    
    pub fn parse(self: Parser, source: []const u8) !AST { ... }
    pub fn extractLOD(self: Parser, ast: AST, level: u8) ![]const u8 { ... }
};
```

#### LOD Configuration
```zon
.gather = .{
    .default_lod = 2,
    .lod_rules = .{
        .pattern_matches = 4,      // Full detail for matches
        .context_files = 3,        // Good detail for context
        .peripheral_files = 1,     // Minimal for periphery
    },
    .language_settings = .{
        .zig = .{ .include_tests = false },
        .typescript = .{ .include_private = false },
    },
}
```

### Phase 2: Zig Language Support
**Timeline**: 1-2 weeks

- Parse Zig AST using std.zig.parse
- Extract function signatures, type definitions, constants
- Preserve doc comments and attributes
- Handle comptime constructs appropriately

### Phase 3: TypeScript/JavaScript Support
**Timeline**: 2-3 weeks

- Integrate tree-sitter or similar parser
- Extract interfaces, types, classes, functions
- Handle JSDoc comments
- Support React/Svelte component patterns

### Phase 4: Intelligent Transformation
**Timeline**: 3-4 weeks

#### Local LLM Integration (Optional)
```zig
pub const Transformer = struct {
    llm: ?LlamaModel,
    
    pub fn summarize(self: Transformer, text: []const u8) ![]const u8 {
        if (self.llm) |model| {
            return model.complete("Summarize: " ++ text);
        }
        return fallbackSummarize(text);
    }
};
```

#### Smart Markdown Processing
- Extract document structure
- Summarize paragraphs to key sentences
- Preserve code blocks at appropriate LOD
- Generate outline with expandable sections

## Usage Examples

### Basic LOD Control
```bash
# High-level overview (LOD 1)
zz gather "error handling" --lod=1

# Detailed analysis (LOD 3)
zz gather "performance critical" --lod=3

# Mixed detail based on relevance
zz gather "authentication" --lod=auto
```

### Context-Aware Gathering
```bash
# Architecture documentation
zz gather --context=architecture --format=markdown
# Output: Public APIs, type relationships, module structure

# Bug investigation
zz gather "null pointer" --context=debug --include-stack-trace
# Output: Full detail around error sites, simplified elsewhere

# Performance profiling
zz gather --context=performance --focus=hot-paths
# Output: Full algorithms, elided boilerplate
```

### Progressive Disclosure
```bash
# Start with overview
zz gather "database layer" --lod=1 > overview.md

# Drill into specific area
zz gather "database.connection" --lod=3 > detailed.md

# Full source for critical section
zz gather "database.connection.pool" --lod=4 > full.md
```

## Advanced Features (Future)

### Dynamic LOD Adjustment
```bash
# Interactive mode with progressive loading
zz gather --interactive
> show database module at LOD 2
> expand connection pool to LOD 4
> collapse logging to LOD 1
```

### Semantic Queries
```bash
# Find all error handling patterns
zz gather --semantic "error handling patterns"

# Extract all public APIs
zz gather --semantic "public interface"

# Get architectural boundaries
zz gather --semantic "module boundaries"
```

### AI-Powered Summarization
```bash
# Use local LLM for intelligent compression
zz gather --llm=llama-7b --summarize

# Custom transformation prompts
zz gather --transform="Extract security-relevant code"
```

## Success Metrics

### Performance Targets
- **Parsing Speed**: <10ms per file for AST generation
- **LOD Extraction**: <5ms per file per level
- **Memory Usage**: <500MB for 10K file codebase
- **LLM Integration**: <100ms per transformation (local)

### Quality Metrics
- **Compression Ratio**: 10:1 at LOD 1, 3:1 at LOD 2
- **Semantic Preservation**: 95% of API surface captured at LOD 2
- **Relevance Score**: 90% of gathered content directly relevant to query

### User Experience
- **Progressive Loading**: Results stream as processed
- **Incremental Refinement**: Adjust LOD without re-parsing
- **Format Flexibility**: Multiple output formats (MD, JSON, HTML)
- **Integration**: Seamless Claude Code workflows

## Technical Challenges

### Parser Integration
- **Challenge**: Integrating multiple language parsers efficiently
- **Solution**: Plugin architecture with lazy loading

### Performance at Scale
- **Challenge**: Parsing thousands of files quickly
- **Solution**: Parallel processing, incremental parsing, caching

### Semantic Understanding
- **Challenge**: Determining "importance" and "relevance"
- **Solution**: Heuristics initially, ML models long-term

### LLM Integration
- **Challenge**: Running local models efficiently
- **Solution**: llama.cpp integration, model quantization, GPU acceleration

## Implementation Priority

1. **Core LOD Framework** - Establish the multi-level extraction system
2. **Zig Parser** - Native language support first
3. **Basic Gathering** - Pattern matching with LOD control
4. **TypeScript Parser** - Most requested external language
5. **Smart Summarization** - Fallback heuristics before LLM
6. **LLM Integration** - Optional enhancement for power users

## Open Questions

1. **LOD Granularity**: Should we support fractional LODs (2.5) or custom per-construct rules?
2. **Caching Strategy**: How aggressively should we cache parsed ASTs?
3. **Parser Dependencies**: Build our own or integrate existing tools?
4. **LLM Requirements**: Support multiple models or standardize on llama.cpp?
5. **Streaming Output**: How to progressively stream results while maintaining structure?

## Conclusion

`zz gather` with LOD represents a paradigm shift in code exploration - from "show me everything" to "show me what matters at the right level of detail." This approach makes large codebases tractable for both human developers and AI assistants, enabling more intelligent and context-aware development workflows.

The key innovation is treating code as a multi-resolution structure rather than flat text, allowing dynamic zoom levels that preserve semantic meaning while reducing cognitive load. This positions `zz` as not just a fast filesystem tool, but as an intelligent code understanding platform.