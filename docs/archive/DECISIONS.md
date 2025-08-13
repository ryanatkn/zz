# DECISIONS.md

**Architectural Decision Records - Why things are the way they are**

## ADR-001: Zero Dependencies
**Date:** Project inception  
**Decision:** No external dependencies whatsoever  
**Rationale:** 
- Every dependency is code we don't control
- Dependencies increase attack surface
- Build times stay fast
- Distribution stays simple

**Alternatives considered:**
- Using ripgrep as library (would save time but adds 2MB binary size)
- Using clap for argument parsing (nice API but unnecessary complexity)
- Using serde for serialization (powerful but we only need simple formats)

**Consequences:**
- We write our own argument parser
- We implement our own pattern matching
- We handle our own serialization
- More code to maintain, but complete control

---

## ADR-002: POSIX Only, No Windows
**Date:** Project inception  
**Decision:** Support only POSIX-compliant systems  
**Rationale:**
- One platform done well > two done poorly
- Windows has fundamentally different path handling, permissions, line endings
- Our users are developers on Unix-like systems
- Reduces complexity significantly

**Alternatives considered:**
- Full Windows support (would double testing burden)
- Windows via WSL only (confusing support story)
- Cygwin/MinGW support (half-measures that please no one)

**Consequences:**
- Clean path handling code
- Simpler filesystem operations
- Can use Unix-specific optimizations
- Windows users must use WSL or containers

---

## ADR-003: Filesystem Abstraction for Testing
**Date:** 2024-01-05  
**Decision:** All filesystem operations go through an interface  
**Rationale:**
- Enables deterministic testing without real I/O
- Can test error conditions (permission denied, disk full)
- Tests run faster without filesystem access
- No test artifacts left in working directory

**Alternatives considered:**
- Real filesystem with temp directories (slower, less deterministic)
- Mocking at the system call level (too low level)
- No abstraction (untestable edge cases)

**Consequences:**
- Every module takes a `FilesystemInterface` parameter
- Mock filesystem implementation for tests
- Small runtime overhead (negligible in practice)
- Much better test coverage

---

## ADR-004: Modular Binary Strategy
**Date:** 2024-01-12  
**Decision:** Core `zz` stays small, features in separate binaries  
**Rationale:**
- Keeps core tool fast and focused
- Optional features don't bloat main binary
- Each tool can be excellent at its purpose
- Follows Unix philosophy of composition

**Alternatives considered:**
- Monolithic binary with everything (would grow to 50MB+)
- Plugin system (complex, dynamic loading issues)
- Feature flags at compile time (complex build matrix)

**Consequences:**
- `zz` stays under 5MB
- `zz-ts`, `zz-web`, `zz-llm` as separate tools
- Clean composition via pipes and files
- Users only install what they need

---

## ADR-005: Direct Buffer Manipulation for Paths
**Date:** 2024-01-08  
**Decision:** Don't use `std.fmt.allocPrint` for path operations  
**Rationale:**
- 20-30% performance improvement measured
- Path joining is a hot path operation
- Predictable memory allocation pattern
- Simple operation doesn't need format strings

**Alternatives considered:**
- Using std.fmt.allocPrint (simpler but slower)
- Using a string builder pattern (more complex, not faster)
- Stack-based buffers (size limitations)

**Consequences:**
- Custom `joinPath` function in `lib/path.zig`
- Must manually handle separator logic
- Slightly more code but measurable performance win
- ~47μs per operation vs ~65μs with stdlib

---

## ADR-006: String Interning with PathCache
**Date:** 2024-01-09  
**Decision:** Intern commonly used path components  
**Rationale:**
- 15-25% memory reduction on large directory trees
- Many path components repeated (src/, test/, .zig)
- Improves cache locality
- Reduces allocator pressure

**Alternatives considered:**
- No string pooling (simpler but more memory)
- Global string pool (threading complications)
- Reference counting (unnecessary complexity)

**Consequences:**
- `PathCache` in tree operations
- Must carefully manage lifetime
- Excellent cache hit rates (95%+)
- More complex but worth it for large trees

---

## ADR-007: No Background Colors in Output
**Date:** 2024-01-11  
**Decision:** Only use foreground colors in terminal output  
**Rationale:**
- Background colors interfere with terminal themes
- Reduce accessibility for users with color preferences
- Look unprofessional in logs
- Violate principle of minimal visual noise

**Alternatives considered:**
- Backgrounds for emphasis (too flashy)
- Configurable color schemes (unnecessary complexity)
- No colors at all (loses useful semantic information)

**Consequences:**
- Clean, readable output in any terminal
- Semantic colors only (red=error, green=success, etc.)
- Works well with both light and dark themes
- Professional appearance

---

## ADR-008: Benchmark Output to Stdout
**Date:** 2024-01-10  
**Decision:** Benchmark command outputs to stdout, not files  
**Rationale:**
- Follows Unix philosophy
- User controls where output goes
- Composable with other tools
- No surprise file writes

**Alternatives considered:**
- Auto-save to timestamp files (surprising behavior)
- Required output file flag (annoying for quick runs)
- Both stdout and file (confusing semantics)

**Consequences:**
- Clean CLI interface
- Users redirect to files when needed
- Build commands can add convenience wrappers
- Works with pipes and process substitution

---

## ADR-009: Test Naming Convention
**Date:** 2024-01-06  
**Decision:** Test names describe what breaks, not what works  
**Rationale:**
- Failed test name immediately tells you the problem
- More informative in CI logs
- Encourages thinking about failure modes
- Natural documentation of edge cases

**Alternatives considered:**
- Testing what works (less informative when it fails)
- BDD-style "should" naming (verbose)
- Numbered test cases (unmaintainable)

**Consequences:**
- Test names like "handles missing file" not "file exists test"
- Better debugging from test output alone
- Tests document edge cases and error handling
- Slight mental shift for contributors

---

## ADR-010: No Emoji in Code or Output
**Date:** 2024-01-12  
**Decision:** No emoji except simple Unicode symbols (✓, ⚠)  
**Rationale:**
- Professional tools don't need decoration
- Emoji are attention-seeking and distracting
- Different rendering across terminals
- Simple symbols convey meaning without noise

**Alternatives considered:**
- Rich emoji for "modern" feel (unprofessional)
- ASCII only (loses some useful symbols)
- Configurable emoji (unnecessary complexity)

**Consequences:**
- Clean, professional output
- Consistent rendering everywhere
- Focus on information, not decoration
- Taken seriously as a development tool

---

*Note: This document records significant decisions. Minor implementation choices are documented in code comments where relevant.*