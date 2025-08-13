# Frequently Asked Questions (FAQ)

## General Questions

### What is zz?
zz is a high-performance command-line utility suite written in Zig. It provides fast directory tree visualization, LLM prompt generation, and performance benchmarking tools, all with zero external dependencies.

### Why is it called "zz"?
- **Z**ig-powered utilities
- **Z**ero dependencies  
- Easy to type (just two letters)
- Alphabetically last, so it doesn't conflict with other commands

### How fast is zz compared to similar tools?
zz is designed for maximum performance:
- **20-30% faster** than standard library path operations
- **40-60% faster** pattern matching for common cases
- **<50ms** to render 1,000 files in tree format
- **15-25% less memory** usage through string interning

### What platforms are supported?
zz supports all POSIX-compliant systems:
- ✓ Linux (all distributions)
- ✓ macOS (10.15+)
- ✓ FreeBSD, OpenBSD, NetBSD
- ✓ Other Unix-like systems
- 🞪 Windows (no plans for support)

### Why no Windows support?
zz is optimized specifically for POSIX systems. Supporting Windows would require:
- Compromising performance with abstraction layers
- Maintaining two separate codebases
- Testing on a platform we don't use
We chose to focus on doing one thing excellently rather than many things adequately.

## Installation Questions

### How do I install zz?
```bash
# From source (recommended)
git clone https://github.com/yourusername/zz.git
cd zz
zig build install-user

# Add to PATH
echo 'export PATH="$PATH:$HOME/.zz/bin"' >> ~/.bashrc
```

### What version of Zig do I need?
Zig 0.14.1 or later. Check with:
```bash
zig version
```

### Can I install zz with a package manager?
Not yet, but planned:
- Homebrew (macOS/Linux) - Coming in v0.2
- AUR (Arch Linux) - Community maintained
- Nix - Coming in v0.3

### How do I update zz?
```bash
cd zz
git pull
zig build install-user
```

### How do I uninstall zz?
```bash
rm -rf ~/.zz
# Remove PATH entry from ~/.bashrc or ~/.zshrc
```

## Usage Questions

### How is zz different from `tree`?
zz tree offers several advantages:
- **Faster**: Optimized traversal and rendering
- **Configurable**: `.zon` configuration files
- **Gitignore-aware**: Respects `.gitignore` by default
- **Multiple formats**: Tree and list output
- **Better filtering**: Advanced pattern matching

### How is zz different from `find` or `fd`?
zz focuses on visualization and prompt generation, not just finding files:
- **Visual output**: Tree structure display
- **LLM integration**: Prompt generation built-in
- **Performance tracking**: Integrated benchmarking
- **Different purpose**: Complement, not replacement

### Can I use zz in scripts?
Yes! zz is designed for scripting:
```bash
# Get file list
files=$(zz tree --format=list)

# Generate JSON output (planned)
zz tree --format=json | jq '.files[]'

# Use in pipelines
zz prompt "*.zig" | grep "error" | wc -l
```

### How do I ignore certain directories?
Create a `zz.zon` file:
```zon
.{
    .ignored_patterns = .{
        "node_modules",
        "target",
        ".git",
    },
}
```

Or use gitignore (enabled by default):
```gitignore
# .gitignore
node_modules/
*.tmp
build/
```

### Can I follow symlinks?
Yes, configure in `zz.zon`:
```zon
.{
    .symlink_behavior = "follow",  // or "skip" or "show"
}
```

## Tree Command Questions

### How do I limit tree depth?
```bash
zz tree . 3  # Maximum depth of 3
```

### How do I show hidden files?
```bash
# Future feature
zz tree --show-hidden

# Or in zz.zon
.{
    .show_hidden = true,
}
```

### Can I export tree output?
```bash
# Markdown
zz tree > structure.md

# List format
zz tree --format=list > files.txt

# HTML (using conversion)
zz tree | aha > tree.html
```

### Why do some directories show as `[...]`?
Directories showing as `[...]` are ignored but acknowledged:
- Matched by ignore patterns
- Listed in `.gitignore`
- No permission to read
This lets you see the structure without cluttering output.

## Prompt Command Questions

### What are glob patterns?
Glob patterns are wildcards for matching files:
- `*.zig` - All .zig files
- `**/*.zig` - All .zig files recursively
- `test?.zig` - test1.zig, test2.zig, etc.
- `*.{zig,c,h}` - Multiple extensions

### How do I include hidden files in prompts?
Use explicit patterns:
```bash
zz prompt ".*"  # All hidden files
zz prompt ".config/*"  # Specific hidden directory
```

### Can I add context to prompts?
Yes, use prepend and append:
```bash
zz prompt "*.zig" \
    --prepend="Review this Zig code:" \
    --append="Focus on memory safety"
```

### Why are some files not included?
Files might be excluded because:
1. They match ignore patterns
2. They're in `.gitignore`
3. They're hidden (need `.*` pattern)
4. The glob pattern doesn't match
5. Permission denied

Check with:
```bash
zz tree --no-gitignore  # See all files
```

## Benchmark Questions

### What do the benchmarks measure?
Current benchmarks measure:
- **Path operations**: File path joining speed
- **String pooling**: String interning efficiency
- **Memory pools**: Allocation/deallocation performance
- **Glob patterns**: Pattern matching speed

### How do I interpret benchmark results?
- **ns/op**: Nanoseconds per operation (lower is better)
- **Green ✓**: Performance improved
- **Yellow ⚠**: Performance regressed
- **Progress bars**: Relative performance
- **Percentage**: Change from baseline

### Why do benchmark results vary?
Variations can be caused by:
- CPU frequency scaling
- Other running programs
- System load
- Cache state
- Debug vs Release build

For consistent results:
```bash
# Use release build
zig build -Doptimize=ReleaseFast
./zig-out/bin/zz benchmark
```

### How do I add custom benchmarks?
See [CONTRIBUTING.md](CONTRIBUTING.md) for details on adding benchmarks.

## Configuration Questions

### Where does zz look for configuration?
zz looks for `zz.zon` in the current directory. This allows per-project configuration.

### What is ZON format?
ZON (Zig Object Notation) is Zig's configuration format, similar to JSON but with Zig syntax:
```zon
.{
    .field = "value",
    .array = .{ "item1", "item2" },
    .number = 42,
    .boolean = true,
}
```

### Can I have global configuration?
Not currently. Each project should have its own `zz.zon`. Global config is planned for v0.3.

### How do I validate my configuration?
```bash
# Future feature
zz config validate

# Currently, just try running zz
zz tree  # Will error if config is invalid
```

## Performance Questions

### Why is zz so fast?
Several optimizations:
- **Direct buffer manipulation** instead of string formatting
- **String interning** to reduce allocations
- **Fast-path optimizations** for common patterns
- **Early directory skipping** without opening
- **Arena allocators** for bulk deallocation
- **Zero dependencies** means no overhead

### How much memory does zz use?
Typical memory usage:
- Empty directory: ~100KB
- 1,000 files: ~500KB
- 10,000 files: ~3MB
- 100,000 files: ~25MB

### Can zz handle very large directories?
Yes, zz is designed for large codebases:
- Tested with 100,000+ files
- Memory usage grows linearly
- Performance remains responsive
- Use depth limiting for massive trees

## Development Questions

### How do I contribute to zz?
See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines. We welcome:
- Performance improvements
- Bug fixes
- Documentation updates
- Test coverage increases

### What's the development philosophy?
- **Performance first**: Every change must maintain or improve speed
- **Zero dependencies**: Pure Zig only
- **No backward compatibility**: Iterate quickly to best solution
- **POSIX only**: Optimize for Unix-like systems
- **Less is more**: Simple solutions over complex

### How do I run tests?
```bash
# All tests
zig build test

# Specific module
zig build test-tree

# With filter
zig test src/test.zig --test-filter "pattern"
```

### How do I debug zz?
```bash
# Build debug version
zig build

# Use debugger
gdb ./zig-out/bin/zz
lldb ./zig-out/bin/zz

# Add debug output (remove before committing)
std.debug.print("Debug: {}\n", .{value});
```

## Troubleshooting Questions

### Why do I get "command not found"?
The `~/.zz/bin` directory is not in your PATH:
```bash
echo 'export PATH="$PATH:$HOME/.zz/bin"' >> ~/.bashrc
source ~/.bashrc
```

### Why do I get "permission denied"?
Some directories require elevated permissions:
```bash
# Option 1: Skip errors
zz tree --skip-errors

# Option 2: Use sudo (if appropriate)
sudo zz tree /protected/dir
```

### Why is zz slow on network drives?
Network filesystems have higher latency:
- Limit depth: `zz tree . 2`
- Disable gitignore: `zz tree --no-gitignore`
- Copy locally first if possible

### Where can I get help?
- **Documentation**: See README.md and other docs
- **Issues**: GitHub issues for bugs
- **Discussions**: GitHub discussions for questions
- **Examples**: See [PATTERNS.md](PATTERNS.md)

## Future Questions

### Will zz support Windows?
No plans. Windows users can use:
- WSL2 (Windows Subsystem for Linux)
- Docker containers
- Virtual machines

### Will zz add feature X?
Check [ROADMAP.md](ROADMAP.md) for planned features. Request new features via GitHub issues.

### Will zz remain free?
Yes! zz is and will remain open source.

### How stable is zz's API?
- Before v1.0: May change without notice
- After v1.0: Semantic versioning
- Command-line interface: Stable after v0.5

### When will v1.0 be released?
Target: January 2026. See [ROADMAP.md](ROADMAP.md) for details.