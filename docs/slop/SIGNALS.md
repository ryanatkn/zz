# SIGNALS.md

**Quality signals we measure vs vanity metrics we ignore**

## Performance Signals That Matter

### Real Measurements
```bash
# Actual user experience
time zz tree /usr/local     # Cold start + execution
time zz prompt src/**/*.zig  # Real workload

# Not vanity benchmarks
"Processes 1M files/second!"  # On what filesystem?
"10x faster than X!"          # At what specifically?
```

### Memory That Counts
**Track:**
- Peak RSS for typical operations
- Memory per file processed
- Arena allocator efficiency

**Ignore:**
- Micro-allocations in cold paths
- Theoretical minimums
- Synthetic benchmark memory

### Latency Hierarchy
What users actually feel:
```
<10ms    - Instant (terminal echo)
<50ms    - Fast (ls in small dir)
<200ms   - Acceptable (git status)
>1s      - Noticeable (need feedback)
>3s      - Frustrating (losing users)
```

Old C wisdom: Make the common case fast. Web reality: Users expect instant.

## Code Quality Signals

### Meaningful Coverage
**Good coverage:**
```zig
// Testing actual failure modes
test "handles permission denied" { }
test "handles circular symlinks" { }
test "handles non-UTF8 paths" { }
```

**Theater coverage:**
```zig
// Testing that code runs
test "constructor works" { }
test "getter returns value" { }
test "2 + 2 = 4" { }
```

### Complexity Metrics
**Worth tracking:**
- Cyclomatic complexity >10 (refactor it)
- Function length >50 lines (split it)
- Nesting depth >4 (flatten it)

**Not worth tracking:**
- Lines of code (meaningless)
- Number of comments (quality > quantity)
- Commit frequency (depth > breadth)

### Build Times
The Ken Thompson test: Can you rebuild during a coffee break?
```
zig build: <5s          # Acceptable
zig build: <2s          # Good  
zig build: <1s          # Excellent

Future web builds:
npm run build: <10s     # TypeScript/Svelte reality
```

## User Signals

### Usage Patterns
**Real signals:**
```bash
# Which commands actually get used
$ history | grep "zz" | awk '{print $2 " " $3}' | sort | uniq -c
  847 zz tree
  213 zz prompt
   12 zz benchmark
    3 zz help
```

**Vanity metrics:**
- GitHub stars (popularity != quality)
- Download counts (bots exist)
- Fork count (most are abandoned)

### Error Patterns
**Track these:**
```
"file not found" -> 100/day   # Users misunderstanding
"permission denied" -> 10/day  # Environment issues
"panic: unreachable" -> 1/day  # Our bugs
```

**Fix patterns, not instances.**

### Feedback Quality
**High signal:**
- "Crashes on symlink loops" (bug report)
- "3x slower than v1.0" (performance regression)
- "Can't parse TypeScript imports" (missing feature)

**Low signal:**
- "Doesn't work" (no context)
- "Make it faster" (no measurement)
- "Add AI" (no use case)

## Development Signals

### PR Quality
**Good PR signal:**
- Fixes real issue
- Includes tests
- Performance impact measured
- Small, focused change

**Bad PR signal:**
- "Refactoring" (no behavior change)
- "Update deps" (we have none)
- "Add emoji" (see TASTE.md)
- 1000+ lines changed

### Compiler Warnings
**Zero tolerance for:**
```zig
warning: unused variable
warning: unreachable code
warning: potential null dereference
```

**Acceptable during development:**
```zig
info: TODO: implement this
info: deprecated function (if fixing next)
```

### Benchmark Stability
**Real regression:**
```
Path joining: 47μs -> 94μs  # 2x slower = investigate
```

**Noise:**
```
Path joining: 47μs -> 49μs  # 4% variance = ignore
```

Standard deviation matters more than means.

## Integration Signals (Future)

### Web Integration Health
When we add web features:
```javascript
// Good signal: Clean API boundary
const result = await zz.parse(tsCode);

// Bad signal: Tight coupling
const result = await zz.internal._parseWithState(tsCode, state, opts);
```

### LLM Integration Quality
Future LLM features should track:
- Suggestion acceptance rate
- Time saved vs manual
- Error introduction rate

Not:
- "AI-powered" marketing metrics
- Token counts
- Model size flexing

### WASM Performance
When we compile to WASM:
```
Native: 10ms
WASM:   15ms  # Good (1.5x overhead)
WASM:   100ms # Bad (10x overhead)
```

The signal: Can web tools use our parsers in real-time?

## Anti-Signals (Ignore These)

### Vanity Metrics
- GitHub stars
- Twitter mentions  
- Blog post coverage
- Conference talks
- "Trending" status

### Premature Optimization
- Micro-benchmark improvements
- Cache hit rates for cold paths
- Allocation counts in one-time init
- String comparison optimizations

### Process Theater
- Commit message length
- PR template compliance
- Documentation word count
- Test file count
- Issue label taxonomy

### Tool Scores
- Linter happiness scores
- Security scanner noise
- Complexity index ratings
- "Code quality" badges
- AI-generated metrics

## Meta Signals

### Maintenance Burden
**Healthy:**
```
Issues closed/week > Issues opened/week
PR merge time < 24 hours
Build stays green
```

**Unhealthy:**
```
Issue backlog growing
PRs sitting for weeks
Flaky tests increasing
```

### Architecture Decay
**Watch for:**
- Circular dependencies appearing
- Module boundaries blurring
- Performance gradually degrading
- Test time increasing faster than code

**The Robert Martin signal:** "The only way to go fast is to go well."

### Community Health
**Good signs:**
- Same contributors returning
- Quality of questions improving
- Users becoming contributors
- Forks creating PRs, not diverging

**Bad signs:**
- Only maintainers contributing
- Basic questions repeating
- Hostile issue discussions
- Forks never merging back

---

*"Not everything that counts can be counted, and not everything that can be counted counts."*

Measure what helps you make decisions. Ignore what doesn't. When web integration comes, when LLMs land, the signals that matter will be the same: Is it fast? Does it work? Do people use it?

The rest is noise.