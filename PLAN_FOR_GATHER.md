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


---

Here's a critique:

````md
# Critique of the `zz gather` proposal

Nice spec — the LOD idea is strong and fits the project goals (performance, UX for LLMs, precise CLI tools). Below I give a focused, practical critique: what’s good, what’s risky or underspecified, and concrete suggestions you can act on immediately (config, data models, CLI flags, tests, and implementation tactics). I assume an incremental, performance-first rollout consistent with the rest of `zz`.

---

## Quick summary — what I like

* The LOD abstraction is clean and intuitive; mapping it to use-cases (architecture, debug, perf) is excellent.
* Language-aware extraction + semantic compression is the right approach vs naive truncation.
* Integration with existing `prompt`/`tree` modules and `zz.zon` config fits the project architecture.
* Emphasis on performance, streaming results, and incremental refinement matches the repo’s principles.

---

## Biggest issues & risks (high priority)

### 1. **Ambiguous / brittle LOD semantics**

`LOD 0..4` is easy to say but underspecified: does `LOD 2` always include doc comments? What about inline comments? Private vs public? Tests? Generated code? Different languages have different semantics (e.g., Zig `comptime`, Svelte markup+script).
**Risk:** inconsistent outputs across languages and user confusion.

**Fix:** define *profiles* (named presets) in addition to numeric LODs, and expose boolean flags for orthogonal axes (comments, tests, private, bodies). Example: `--lod=api` or `--lod=2 --include-docs --include-tests=false`.

---

### 2. **Overly optimistic performance targets**

* `<10ms per file AST generation` and `<5ms extraction` are ambitious without profiling or language-specific constraints. Tree-sitter, full semantic analysis, or complex Zig parsing may exceed that for large files.
  **Risk:** unrealistic promises -> users unhappy.

**Fix:** collect microbenchmarks per language and per-operation in phase 0; express targets as *best-effort* and provide graceful degradation (e.g., fallback to faster heuristics). Add timeouts and `--max-per-file-ms` controls.

---

### 3. **Parser strategy under-specified**

You say “use proper parsers (not regex)” — but don’t pick a clear default for third-party languages. Building or pinning custom parsers is costly; linking to `std.zig.parse` for Zig might be tempting but can be version-dependent and fragile.

**Fix:** adopt a plugin architecture with:

* primary: language-specific AST via **tree-sitter** where stable,
* native: Zig’s std parser for Zig if it’s stable and available,
* fallback: lightweight heuristics (token-level) for unknown languages.

Document which languages get which strategy and how to add a parser plugin.

---

### 4. **LLM integration dangers**

Local LLM summarization is presented as optional, but the plan needs to address privacy, secret leakage, configurable redaction, and cost/latency. Defaulting to sending whole files to an LLM is unsafe.

**Fix:** require explicit opt-in (`--llm`), add pre-send filters: secret detector, max-chars, allowlist/denylist, and scrub sensitive files by default (e.g., anything matching `.secret`, `*.key`). Add "dry-run" to preview what would be sent.

---

### 5. **Caching, incremental updates, and correctness**

You list caching but not the invalidation strategy. AST caching requires robust keys (file content hash, parse options, language version). Without that you risk stale LOD outputs.

**Fix:** canonical cache key = `(repo-root, git-commit-or-HEAD-hash, file-path, file-content-hash, parser-version, extraction-options-hash)`. Support a `--force-reparse` flag and a small on-disk cache in `~/.zz/gather-cache`.

---

### 6. **Relevance & importance heuristics are unspecified**

You propose rules: relevance, distance, importance. But how to compute them? Simple heuristics (filename patterns, imports, call graph) vs ML-based scoring is a big design choice.

**Fix (MVP):**

* Heuristics: pattern matches (glob), import/dependency distance (call/import graph traversal up to N hops), file size/complexity, recent git-changes frequency.
* Later: optional embedding-based ranking (index file-level embeddings for semantic matches).

---

## Concrete improvements and specifications (actionable)

### A. LOD / Config model (suggested)

Provide *both* numeric LOD and named profiles + flags.

Example `zz.zon` snippet:

```zon
.gather = .{
    .default_profile = "dev",
    .profiles = .{
        dev = .{ .lod = 2, .include_private = true, .include_tests = true, .include_docs = true },
        api  = .{ .lod = 1, .include_private = false, .include_tests = false, .include_docs = true },
        debug = .{ .lod = 3, .include_private = true, .include_tests = true, .include_docs = true, .bodies = "selective" },
    },
    .lod_rules = .{
        // pattern -> profile override
        .pattern_matches = .{ .glob = "src/**/auth/**", .profile = "debug" },
    },
};
```

Expose CLI flags: `--profile`, `--lod`, `--include-docs/--no-docs`, `--include-tests/--no-tests`, `--max-lines-per-file=N`, `--max-bytes-per-file=N`.

---

### B. Output format & streaming API

Support two canonical output formats:

1. **NDJSON** with one object per file (makes streaming easy).
2. **Markdown** (for human use), using your semantic XML tags like `<File path="...">`.

**NDJSON schema (recommended fields):**

```json
{
  "path": "src/foo.zig",
  "lod": 2,
  "profile": "api",
  "ast_node_summary": "...",      // short string
  "content_snippet": "...",
  "fingerprint": { "sha256": "...", "size": 1234 },
  "meta": { "language": "zig", "lines": 120, "modified": 169... },
  "anchors": [ { "name":"processData", "start": 12, "end": 42, "lod": 2 } ],
  "extraction_time_ms": 4
}
```

Streaming: write NDJSON to stdout; if `--format=markdown` convert in a second pass or stream converted blocks. Use `--stream` flag to indicate partial output and `--keep-order` if required.

---

### C. Relevance computation (MVP algorithm)

0. Build file graph from imports/exports (language-specific quick parsing).
1. Seed set = files matching user pattern.
2. Score files by:

   * `score += 100` for direct match,
   * `score += 50 / distance` for import distance (breadth-first up to N hops),
   * `score += file_complexity_metric` (lines, cyclomatic),
   * `score -= size_penalty` if huge binary or generated.
3. Convert score -> LOD using rules (configurable thresholds).

Keep it deterministic and cheap.

---

### D. Caching & incremental parsing

* Cache AST & LOD outputs keyed by hashed tuple above.
* Use file mtime and git commit to detect invalidation; prefer content hash to be safe.
* Invalidate on config change (config-hash part of key).
* Provide `zz gather --invalidate-cache` and `--warm-cache` to precompute.

---

### E. Security & privacy

* Default: **do not** run LLM transforms unless `--llm` provided.
* Add `--redact-secrets` default-on using simple detectors (regex for keys, tokens, RSA headers), with an opt-out.
* Add `--auditable-log` to write which files would be sent to any external model.

---

### F. Testing & QA

* Golden tests per language: input file -> LOD-level output snapshot.
* Property tests: composition (if LOD 4 includes LOD 3 content where applicable).
* Fuzz parsers with malformed source and generated files.
* End-to-end tests on small/medium real repos (monorepo + single-package).
* Benchmarks for parse/extract per file for each supported language.

---

### G. CLI UX suggestions

Add these flags/commands:

* `zz gather [pattern] [--profile|--lod|--interactive]`
* `--format={ndjson,markdown,html}`
* `--stream` (write partial NDJSON as each file is processed)
* `--focus=PATH` (force high LOD for this path)
* `--max-files` / `--max-bytes`
* `--cache-dir=~/.zz/gather-cache`
* `--no-llm` (explicit default)
* `zz gather inspect <file>:<anchor>` to get precise anchor mapping and original lines

Interactive mode should be optional and use the cached artifacts, not reparse everything on each expand/collapse.

---

## Implementation & architecture notes (detailed)

### Parsers

* **Tree-sitter**: strong for JS/TS, Python, many languages; good for uniform ASTs and fast parsing. Recommend as default for external languages.
* **Zig native parse**: use cautiously. If relying on `std.zig.parse`, pin Zig versions and add adaptors. Consider writing a light Zig AST extractor (function/type/doc comment index) that uses token scanning if the std parser isn't stable.
* **Svelte/HTML-like**: need combined parsing (markup + script). Expose language-aware extractors that can traverse embedded script blocks.

### Memory & parallelism

* Use a worker pool sized to `num_cpus - 1` for parsing/extraction. Use lock-free output queue or channel to stream NDJSON.
* Keep per-thread arenas; avoid global locking for string pools where possible.
* For very large codebases, provide `--shard` option to limit scope.

### Anchors & line mapping

* Store start/end byte offsets and line numbers for every extracted anchor (function, type). Essential for debugging and for allowing downstream tools to open exact locations.

### Data store / indexing (future)

* Optionally produce a compact index (file-level metadata + embeddings) for fast semantic search. Persist to `~/.zz/gather-index/{repo-hash}.idx`.

---

## Metrics & realistic targets (suggested)

* Replace absolute numbers with measured baselines per-language. Example:

  * Target: parse+extract average 3–30 ms for small files (<1k lines); allow >100ms for very large files.
  * Memory: target 500MB for 10k files is fine but add a streaming mode that keeps memory <100MB by not caching full ASTs.

Measure with the repo’s benchmarking tools and add microbenchmarks per parser.

---

## Roadmap & MVP recommendation

Make an MVP that is useful quickly and safe:

1. **MVP** (4–6 weeks realistic with 1–2 devs): NDJSON output, numeric LODs with simple profiles, tree-sitter for TS/JS, lightweight Zig extractor (token-level), caching by file-hash, CLI flags for profile/lod/stream, tests + benchmarks.
2. **Phase 2**: Zig full AST integration, smarter heuristics for relevance (call graph), anchors & line mapping, richer config.
3. **Phase 3**: LLM summarization opt-in, embedding index, interactive mode.

---

## Small nitpicks in the spec

* The sample config `.gather.lod_rules.pattern_matches = 4` is terse — prefer pattern -> rule objects.
* `Transformer.llm` code samples assume a `LlamaModel` API — design a small adapter interface to support multiple backends and fallbacks.
* `Progressive Loading: Results stream as processed` — clarify streaming format (NDJSON recommended).
* “Integration: Seamless Claude Code workflows” — be explicit how permissions & data flow are handled.

---

## Example NDJSON snippet (concrete)

```json
{"path":"src/db/connection.zig","lod":3,"profile":"debug","language":"zig","fingerprint":{"sha256":"..."},"anchors":[{"name":"connectionPool","start":120,"end":300,"lod":3}],"content_snippet":"pub fn connect(...) !Connection { /* elided */ }"}
```

---

## Final recommendation (short)

* **Do the LOD presets + boolean axes** instead of only numeric LODs.
* **Start with tree-sitter + lightweight Zig token extractor** for MVP.
* **Make NDJSON the primary streaming format** and support Markdown rendering as a convenience.
* **Harden caching, secret redaction, and opt-in LLM use** before enabling transformations by default.
* **Measure, then promise**: convert those targets into measured SLOs per language.
````