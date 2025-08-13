# ANTIPATTERNS.md

**What we explicitly avoid and why**

## Code Antipatterns

### Over-Abstraction
**Don't:**
```zig
const AbstractFactoryBuilderInterface = struct {
    factory: *const FactoryInterface,
    builder: *const BuilderInterface,
    // ... 50 more lines of abstraction
};
```

**Do:**
```zig
const Config = struct {
    ignored_patterns: []const u8,
};
```

We write code for humans to read. Abstractions should emerge from actual needs, not anticipated ones.

### Clever Code
**Don't:**
```zig
// Look how smart I am with this one-liner!
const x = if (a) |v| v else b orelse c ?? d;
```

**Do:**
```zig
const x = if (a) |value| {
    return value;
} else if (b) |value| {
    return value;
} else {
    return c orelse d;
}
```

Clear beats clever. Every time.

### Performance Theater
**Don't:**
- Micro-optimize before measuring
- Add caching "just in case"
- Use unsafe operations for hypothetical gains
- Optimize the 1% case while ignoring the 99%

**Do:**
- Measure first, optimize second
- Focus on algorithmic improvements
- Keep it simple until proven slow
- Optimize the hot path, not everything

### Feature Creep
**Don't:**
```bash
zz tree --json --xml --yaml --toml --with-icons --animate --3d-mode
```

**Do:**
```bash
zz tree
zz tree --format=json  # Only when genuinely needed
```

Every feature is a liability. Default to no.

## Architecture Antipatterns

### Framework Addiction
We don't need:
- Dependency injection containers
- Event buses for simple callbacks
- Plugin systems for 3 features
- Configuration frameworks for 10 settings

We use:
- Direct function calls
- Simple structs
- Built-in language features
- Plain text configs

### Premature Generalization
**Don't** build:
- A "renderer interface" when you only have terminal output
- A "storage abstraction" when you only use the filesystem
- A "command framework" for 5 commands
- Generic solutions for specific problems

**Do** build:
- The thing you need right now
- Abstractions after you have 3+ real use cases
- Specific solutions that work well

### Backward Compatibility Theater
**Don't:**
- Keep broken APIs forever
- Accumulate deprecated functions
- Maintain compatibility layers for ancient versions
- Let legacy decisions handicap the future

**Do:**
- Break things when it improves them
- Remove deprecated code aggressively
- Document breaking changes clearly
- Move forward, not backward

## Process Antipatterns

### Documentation Fetishism
**Don't:**
```zig
/// This function adds two numbers together
/// @param a The first number to add
/// @param b The second number to add  
/// @returns The sum of a and b
fn add(a: i32, b: i32) i32 {
    return a + b;
}
```

**Do:**
Document only what's not obvious from reading the code.

### Test Coverage Theater
**Don't:**
- Aim for 100% coverage
- Test getters and setters
- Write tests that test the test
- Mock everything until tests prove nothing

**Do:**
- Test behavior, not implementation
- Focus on edge cases and failure modes
- Write tests that would catch real bugs
- Keep tests simple and readable

### PR Ceremony
**Don't:**
- Require lengthy templates
- Demand screenshot for CLI tools
- Bike-shed on variable names
- Review for style over substance

**Do:**
- Focus on correctness and performance
- Keep reviews focused and quick
- Trust contributors' judgment on small things
- Merge and iterate

## Communication Antipatterns

### Marketing Speak
**Don't say:**
- "Blazing fast"
- "Game-changing"
- "Revolutionary"
- "Best-in-class"
- "Enterprise-grade"

**Do say:**
- "20% faster"
- "Improved"
- "New"
- "Works well"
- "Tested at scale"

### Defensive Writing
**Don't:**
"Perhaps we might consider potentially exploring the possibility of maybe..."

**Do:**
"We should..." or "We won't..."

Be direct. Have opinions. Take positions.

### Emoji Pollution
**Don't:**
```
🚀 Launching new feature! 🎉
✨ Fixed the bug! 💫
🔥 Hot new release! 🔥
```

**Do:**
```
Added tree command
Fixed path traversal bug
Version 1.2.0
```

Professionals don't need decoration.

## Tool Antipatterns

### Flag Proliferation
**Don't:**
```bash
--very-verbose-flag-name-that-describes-everything
--no-really-actually-definitely-force
--experimental-unstable-beta-feature-flag
```

**Do:**
```bash
-v, --verbose
-f, --force
# Experimental features should be stable or not exist
```

### Configuration Complexity
**Don't:**
- YAML with 10 levels of nesting
- JSON with schema validation
- INI with custom extensions
- Environment variables for everything

**Do:**
- Simple key-value when possible
- One config file, not five
- Sensible defaults that work
- Minimal required configuration

### Output Verbosity
**Don't:**
```
[INFO] Starting application...
[DEBUG] Checking configuration...
[INFO] Configuration loaded successfully!
[DEBUG] Initializing subsystems...
[INFO] Ready to process your request!
[INFO] Processing: filename.txt
[SUCCESS] ✨ Completed successfully! ✨
```

**Do:**
```
filename.txt
```

Output only what matters.

## Meta Antipatterns

### Trend Chasing
**Don't:**
- Rewrite in the latest language
- Adopt every new best practice
- Follow every programming fad
- Cargo-cult from popular projects

**Do:**
- Stick with what works
- Adopt improvements that solve real problems
- Learn from others but think for yourself
- Value stability over novelty

### Complexity Worship
**Don't:**
- Admire complex solutions
- Add layers for their own sake
- Measure value by lines of code
- Confuse complicated with sophisticated

**Do:**
- Admire simple solutions
- Remove layers when possible
- Measure value by problems solved
- Recognize that simple is sophisticated

---

*"The best code is no code. The best abstraction is no abstraction. The best feature is no feature."*

These antipatterns aren't rules—they're smells. When you see them, stop and think: is there a simpler way?