# ERGONOMICS.md

**How we design for human use**

## Command-Line Interface

### Argument Design

**Good arguments:**
```bash
zz tree             # No args needed for common case
zz tree src         # Positional for obvious inputs  
zz tree src 2       # Natural ordering
zz tree --format=json   # Clear key=value for options
```

**Bad arguments:**
```bash
zz tree --directory=src --max-depth=2 --output-format=json
zz tree -dtsSxvf src    # Alphabet soup
zz tree --enable-feature --disable-other-feature --toggle-third-feature
```

**Principles:**
- Zero configuration for the 80% case
- Positional args for primary inputs
- Flags only when behavior changes significantly
- Short flags only for frequently-used options
- Long flags should be readable, not verbose

### Error Messages

**Good errors:**
```
Error: src/missing.zig not found
Error: Permission denied: /root/protected
Error: Invalid glob pattern: *.{zig,
       Missing closing brace
```

**Bad errors:**
```
ERROR: An error occurred during file system traversal operation
Error: ENOENT
Error: ❌ Oopsie! Something went wrong! 😢
Fatal: Unhandled exception in module tree.walker at line 47
```

**Principles:**
- State what went wrong
- State where it went wrong
- Suggest how to fix it (when obvious)
- No stack traces unless debugging
- No cute messages or emoji

### Output Formatting

**Parseable by humans:**
```
src/
├── main.zig
├── lib.zig
└── test.zig
```

**Parseable by machines:**
```
./src/main.zig
./src/lib.zig
./src/test.zig
```

**Not parseable by anyone:**
```
[2024-01-01T00:00:00Z] INFO: Found file: main.zig (size: 1234 bytes, perms: 0644)
```

**Principles:**
- Default output for humans
- Structured output (JSON) available via flag
- Consistent formatting within each mode
- No mixing presentation and data
- Scriptable via standard Unix tools

## Progressive Disclosure

### Simple by Default
```bash
# Just works
zz tree

# Discover more as needed
zz tree --help

# Power user features behind flags
zz tree --format=json --no-gitignore
```

### Respect Muscle Memory

**Honor Unix conventions:**
```bash
-h, --help      # Not --info or --usage
-v, --version   # Not --about
-q, --quiet     # Not --silent
-              # Read from stdin
--              # End of options
```

**Common patterns:**
```bash
command [options] [files...]    # Standard ordering
command --foo=value              # Explicit key=value
command --foo value              # Space-separated also works
```

## Performance Perception

### Responsive Feedback

**Good:**
- Immediate output start (streaming)
- Progress only for operations >2 seconds
- Silent success, verbose failure

**Bad:**
- Loading spinners for fast operations
- Progress bars that jump to 100%
- Verbose output drowning signal

### Predictable Performance

Users build mental models:
- Small directories: instant
- Large directories: ~100ms  
- Huge directories: ~1s

Don't violate expectations:
- Don't cache when unnecessary (confusing)
- Don't defer work (surprising delays)
- Don't optimize rarely-used paths

## Composability

### Unix Philosophy

**Good citizen:**
```bash
zz tree | grep ".zig"           # Filterable
zz prompt *.zig > context.md    # Redirectable
find . -name "*.zig" | xargs zz prompt  # Pipeable
```

**Bad citizen:**
```bash
zz tree --grep=".zig"           # Reimplementing grep
zz prompt --output=context.md   # Reimplementing shell
zz prompt --find="*.zig"        # Reimplementing find
```

### Exit Codes

**Meaningful codes:**
- 0: Success
- 1: Error (general)
- 2: Usage error
- 127: Command not found (respect convention)

**Not:**
- Custom codes for every error type
- Success with non-zero codes
- Error with zero codes

## Consistency

### Internal Consistency

All commands in `zz` should:
- Use same flag names for same concepts
- Format output similarly
- Handle errors identically
- Share configuration format

### External Consistency

Respect platform conventions:
- File paths use OS separator
- Line endings match platform
- Case sensitivity follows filesystem
- Colors respect terminal capabilities

## Discoverability

### Help Text

**Useful help:**
```
Usage: zz tree [directory] [depth] [options]

Show directory structure as a tree

Arguments:
  directory    Directory to display (default: current)
  depth        Maximum depth to traverse

Options:
  --format=FORMAT   Output format (tree, list, json)
  --no-gitignore    Don't filter gitignored files

Examples:
  zz tree              # Current directory
  zz tree src 2        # src/ directory, 2 levels
  zz tree --format=json > tree.json
```

**Not useful:**
```
zz tree - displays a tree

Options: --help, --version, --format, --no-gitignore, --depth, ...

For more information, see the man page.
```

### Error Recovery

**Guide users:**
```bash
$ zz tree /restricted
Error: Permission denied: /restricted
Try: zz tree . or a directory you have access to

$ zz prompt
Error: No files specified
Usage: zz prompt <files...>
Example: zz prompt "*.zig" or zz prompt src/
```

## Workflow Integration

### Editor/IDE friendly
- Clean output for tool integration
- Machine-readable formats available
- Proper exit codes for scripting
- No interactive prompts by default

### CI/CD friendly
- Deterministic output
- No terminal-specific features by default
- Proper exit codes for success/failure
- Quiet mode for automated runs

### Shell friendly
- Completion scripts where helpful
- Standard input/output/error usage
- Signal handling (Ctrl-C works)
- No state between invocations

## Anti-Ergonomics to Avoid

### Surprising Behavior
- Hidden configuration files changing behavior
- Environment variables overriding explicit flags
- Different behavior in pipes vs terminal
- Stateful commands that remember previous runs

### Frustrating Interactions
- Required flags with no defaults
- Positional arguments that must be flags
- Order-dependent flags
- Modal interfaces in non-interactive tools

### Cognitive Load
- Too many ways to do the same thing
- Inconsistent naming between related features
- Deep nesting of subcommands
- Configuration that requires documentation

---

*"The tool should fit the hand, not the other way around."*

Good ergonomics make the right thing easy and the wrong thing hard. Every interaction should feel natural, not learned.