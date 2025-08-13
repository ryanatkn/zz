# CONSTRAINTS.md

**Self-imposed limitations that keep us focused**

## Core Constraints

### Zero Dependencies
**The Rule:** No external dependencies. Period.

**Why:**
- Every dependency is a liability
- We control our destiny
- Builds stay fast
- Distribution stays simple
- Security surface stays minimal

**The C way:** If you can't write it yourself, you don't need it.

### POSIX Only
**The Rule:** POSIX systems only. No Windows.

**Why:**
- One platform done right > two done poorly
- POSIX is the lingua franca of systems programming
- Real servers run Unix
- Our users use terminals, not command prompts

**Future:** When we integrate with web tooling (TypeScript parsers, Svelte components), they'll call into our POSIX binaries. The web can abstract platform differences; we won't.

### Binary Size Targets
**Current:** ~2MB release binary
**Target:** Stay under 5MB even with future features

**Old-school discipline:**
```c
/* Every byte counts */
static const char symbols[] = "├│└";  /* Not three separate strings */
```

Modern pragmatism: We'll link LLM inference when needed, but as optional features.

## Performance Budgets

### Speed Requirements
```
Operation       Budget    Current
---------       ------    -------
tree (1K files)  <50ms     ~30ms
prompt (100)     <20ms     ~15ms
cold start       <10ms      ~8ms
```

**The K&R way:** Measure twice, optimize once.

### Memory Limits
- No operation should need >100MB for typical workloads
- Streaming processing for large inputs
- Arena allocators, not malloc soup

**Future web integration:** When we parse TypeScript/Svelte, we'll stream ASTs, not load entire projects.

## Complexity Limits

### Line Count Constraints
```
Module          Max Lines   Why
------          ---------   ---
Any .zig file      1000     If it's bigger, split it
Any function        100     If it's longer, decompose it
main.zig            50      Entry points should be trivial
```

**C wisdom:** "You're not smart enough to debug code you're not smart enough to write."

### Abstraction Depth
- Max 3 levels of indirection
- No abstract interfaces without 3+ implementations
- Prefer duplication over wrong abstraction

**LLM integration philosophy:** When we add LLM features, they'll be concrete tools (like `zz explain` or `zz suggest`), not an "AI framework."

## Feature Constraints

### The "No" List
Things we'll never add:
- GUI/TUI interfaces (let web tools handle that)
- Database backends (filesystem is enough)
- Network protocols (Unix pipes are our network)
- Plugin systems (fork it if you need different)
- Configuration languages (TOML/ZON is sufficient)

### The "Maybe" List
Things that need extraordinary justification:
- New commands (each one must be essential)
- New flags (defaults should be right)
- New output formats (structured data: JSON. Human: text)
- Breaking changes (only for significant improvements)

### The "Yes" List
Things aligned with our future:
- Parser generators for web languages (TypeScript, Svelte)
- LLM integration for code understanding
- AST manipulation tools
- Performance profiling commands
- Static analysis capabilities

## Language Constraints

### Zig Only for Core
**The Rule:** Core utilities in Zig only.

**Why:**
- One language to master
- Consistent performance characteristics
- Simple build system
- C ABI when needed

**Future bridge:** When we need JS interop, we'll compile to WASM or use C ABI, not embed V8.

### Style Constraints
```zig
// Old-school C clarity
const BUFFER_SIZE = 4096;  // Not BufferSize or buffer_size

// But modern safety
defer allocator.free(buffer);  // RAII the Zig way

// Unix terseness
fn main() !void {  // Not elaborate error types
```

## Integration Philosophy

### LLMs as Tools
**Embrace:** LLMs for code understanding, generation, explanation
**Reject:** LLMs as decision makers or architects

Future `zz` commands might include:
```bash
zz explain src/main.zig      # LLM explains code
zz suggest --fix "error msg"  # LLM suggests fixes
zz review --diff HEAD~1       # LLM reviews changes
```

But always: deterministic tools with LLM assistance, not LLM tools with deterministic assistance.

### Web as Frontend
**Our role:** Fast, reliable CLI tools
**Web's role:** Rich interfaces, visual tools

Future architecture:
```
[Svelte UI] -> [TypeScript] -> [WASM/Native zz] -> [Filesystem]
```

We stay in our lane: systems programming excellence.

## Time Constraints

### Release Cadence
- No regular releases (release when ready)
- No LTS versions (latest is always best)
- No deprecation periods (break it or don't)

### Maintenance Burden
- If it takes >1 hour/week to maintain, remove it
- If it has >3 bug reports/month, redesign it
- If it hasn't been used in 6 months, delete it

## Documentation Constraints

### What to Document
**Document:**
- Public APIs
- Non-obvious algorithms
- Performance characteristics
- Integration points

**Don't Document:**
- Obvious code
- Internal implementation details
- Temporary solutions
- Personal preferences

### Documentation Style
```zig
// BAD: Javadoc verbosity
/// This function calculates the sum of two integers
/// @param a The first integer to be added
/// @param b The second integer to be added  
/// @return The sum of a and b

// GOOD: K&R terseness
// Add two integers, checking for overflow
fn add(a: i32, b: i32) !i32
```

## Growth Constraints

### Scope Creep Prevention
Every new feature must:
1. Solve a real problem we've hit 3+ times
2. Fit within existing architecture
3. Not compromise core performance
4. Be explainable in one sentence

### Team Constraints
- Small team (max 5 core contributors)
- Clear ownership (one person per module)
- Consensus not required (maintainer decides)
- Fork-friendly (disagreement? fork it)

---

*"Constraints liberate. Boundaries focus. Limits create."*

These constraints aren't limitations—they're the rails that keep us from derailing. When web integration comes, when LLM features arrive, when TypeScript parsing is needed, these constraints ensure we build them right: fast, simple, composable, Unix-native.