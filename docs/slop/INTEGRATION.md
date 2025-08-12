# INTEGRATION.md

**How modules connect and affect each other**

## Module Dependency Graph

```
CLI Layer (entry points)
├── cli/main.zig ──> cli/runner.zig
│   ├──> tree/main.zig
│   ├──> prompt/main.zig
│   └──> benchmark/main.zig
│
Core Modules (business logic)
├── tree/
│   ├── walker.zig ──> lib/traversal.zig
│   ├── filter.zig ──> patterns/matcher.zig
│   └── formatter.zig ──> lib/path.zig
│
├── prompt/
│   ├── builder.zig ──> lib/traversal.zig
│   ├── glob.zig ──> patterns/glob.zig
│   └── fence.zig (standalone)
│
└── benchmark/
    └── main.zig ──> lib/benchmark.zig
                  ├──> lib/path.zig
                  ├──> lib/string_pool.zig
                  └──> lib/pools.zig

Shared Infrastructure
├── config/
│   ├── shared.zig (data structures)
│   ├── zon.zig ──> filesystem/interface.zig
│   └── resolver.zig ──> patterns/matcher.zig
│
├── patterns/
│   ├── matcher.zig (unified matching)
│   ├── glob.zig ──> matcher.zig
│   └── gitignore.zig ──> matcher.zig
│
├── filesystem/
│   ├── interface.zig (contracts)
│   ├── real.zig ──> interface.zig
│   └── mock.zig ──> interface.zig
│
└── lib/
    ├── traversal.zig ──> filesystem/interface.zig
    ├── path.zig (standalone, POSIX only)
    ├── string_pool.zig (standalone)
    ├── pools.zig (standalone)
    └── benchmark.zig ──> (all lib modules)
```

## Critical Integration Points

### 1. Configuration Flow
**Path:** `zz.zon` → `config/zon.zig` → `config/shared.zig` → all commands

**What changes affect:**
- Tree filtering behavior
- Prompt file selection
- Hidden file handling
- Gitignore respect

**Key insight:** Both tree and prompt use the SAME config structure

```zig
// config/shared.zig defines the structure
pub const SharedConfig = struct {
    ignored_patterns: []const []const u8,
    hidden_files: []const []const u8,
    symlink_behavior: SymlinkBehavior,
    respect_gitignore: bool,
};

// Both commands load it the same way
const config = try Config.load(allocator, filesystem);
```

### 2. Pattern Matching Pipeline
**Path:** User pattern → `patterns/matcher.zig` → actual matching

**Unified through matcher.zig:**
- Glob patterns (`*.zig`)
- Gitignore patterns (negation, directories)
- Literal matches
- Path-based patterns

**Critical:** ALL pattern matching goes through `shouldIgnorePath()` 
```zig
// This function is the chokepoint for all filtering
pub fn shouldIgnorePath(config: *const SharedConfig, path: []const u8) bool {
    // Check ignored_patterns
    // Check gitignore if enabled
    // Return unified decision
}
```

### 3. Filesystem Abstraction
**Path:** Any I/O operation → `filesystem/interface.zig` → real or mock

**Every module that does I/O:**
```zig
pub fn doWork(allocator: Allocator, filesystem: FilesystemInterface) !void {
    // filesystem parameter enables testing
}
```

**Changes here affect:**
- ALL file operations
- Test determinism
- Error handling consistency

### 4. Memory Management Hierarchy
**Arena Strategy:**
```
Main allocator (GPA or page allocator)
└── Arena per command execution
    ├── String pool (if needed)
    ├── Path cache (for tree)
    └── Temporary buffers
```

**Key insight:** Each command creates its own arena, no sharing between commands

### 5. Path Operations
**Central through `lib/path.zig`:**
- Used by tree for building paths
- Used by prompt for file paths
- Used by patterns for matching
- Performance critical - changes affect everything

**Never use `std.fmt.allocPrint` for paths!**

## Hidden Connections

### 1. Benchmark Can Load Its Own Output
```zig
// Benchmark writes markdown
try bench.writeMarkdown(writer, ...);

// Can load that same markdown for comparison
const baseline = try Benchmark.loadFromMarkdown(allocator, content);
```

### 2. Tree Output Format Affects Prompt
Tree's `[...]` for ignored directories inspired prompt's error handling:
```zig
// Tree shows:
node_modules [...]

// Prompt errors similarly:
"Error: node_modules/ is ignored"
```

### 3. Config Affects Performance
`respect_gitignore = true` adds overhead:
- Must read .gitignore files
- Must match every path against patterns
- Can slow down large traversals by 10-20%

### 4. Mock Filesystem Drives Real Implementation
Mock filesystem limitations reveal real filesystem assumptions:
- Symlink handling inconsistencies
- Permission error simulation
- Directory iteration order

## Module Communication Patterns

### 1. Data Flow Pattern
```
Input (args) → Parser → Config → Core Module → Formatter → Output (stdout)
```

### 2. Error Propagation
```
Filesystem error → traversal.zig catches → module decides → CLI reports
```
Errors bubble up but are interpreted at each level.

### 3. Memory Flow
```
CLI allocates arena → passes to module → module uses → CLI frees arena
```
Modules never free memory directly, always through arena cleanup.

## Change Impact Matrix

| If you change... | You must check... | Because... |
|-----------------|-------------------|------------|
| `config/shared.zig` | tree + prompt | Both use same config |
| `patterns/matcher.zig` | All filtering | Central matching logic |
| `lib/path.zig` | Everything | Performance critical |
| `filesystem/interface.zig` | All I/O operations | Contract changes |
| `lib/traversal.zig` | tree + prompt | Both traverse directories |
| CLI argument parsing | Help text | Must stay in sync |
| Benchmark output format | Baseline loading | Must parse own output |

## Integration Anti-Patterns to Avoid

### 1. Cross-Module State
**Bad:** Module A sets global that Module B reads
**Good:** Pass data explicitly through parameters

### 2. Circular Dependencies  
**Bad:** `tree` imports `prompt` which imports `tree`
**Good:** Extract shared code to `lib/`

### 3. Hidden Configuration
**Bad:** Module reads environment variables directly
**Good:** All config through `config/` modules

### 4. Mixed Allocation Strategies
**Bad:** Some code uses arena, some uses direct allocation
**Good:** Consistent arena usage per command

## Testing Integration Points

### 1. Config + Module Integration
```zig
test "tree respects config patterns" {
    var config = Config.forTesting();
    config.ignored_patterns = &[_][]const u8{"*.tmp"};
    
    // Test tree with this config
}
```

### 2. Filesystem + Module Integration  
```zig
test "prompt handles missing files" {
    var mock_fs = MockFilesystem.init(allocator);
    // Don't add file - test missing file handling
    
    const result = try prompt.run(allocator, mock_fs.interface(), args);
}
```

### 3. End-to-End Integration
```zig
test "CLI to output integration" {
    const args = [_][:0]const u8{"tree", "src", "2"};
    const output = try captureOutput(cli.main, args);
    try testing.expect(std.mem.indexOf(u8, output, "src/") != null);
}
```

## Future Integration Considerations

### When Adding `zz-ts` (TypeScript parser):
- Will need to share pattern matching
- Will need to share filesystem abstraction
- Should use same config format
- Output should compose with `zz prompt`

### When Adding `zz-llm` (LLM integration):
- Will consume output from other commands
- Should use same markdown generation
- Will need rate limiting/caching infrastructure
- Must respect same ignore patterns

### When Adding Web UI:
- Commands need JSON output mode
- Might need streaming/progressive output
- Error messages need structure, not just text
- Performance metrics need to be consumable

---

*Understanding these connections helps predict change impact and maintain consistency.*