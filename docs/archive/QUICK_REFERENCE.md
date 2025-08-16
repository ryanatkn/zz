# zz Quick Reference

## Command Overview

```bash
zz <command> [options] [arguments]
```

| Command | Description | Example |
|---------|-------------|---------|
| `tree` | Show directory structure | `zz tree src/` |
| `prompt` | Generate LLM prompts | `zz prompt "*.zig"` |
| `benchmark` | Run performance tests | `zz benchmark --format=pretty` |
| `help` | Show detailed help | `zz help` |
| `-h` | Show brief help | `zz -h` |
| `--help` | Show detailed help | `zz --help` |

## Tree Command

### Basic Usage
```bash
zz tree                    # Current directory
zz tree src/              # Specific directory
zz tree . 3               # Limit depth to 3
zz tree --format=list     # List format output
zz tree -f list           # Same as above (short flag)
```

### Options
| Option | Description | Example |
|--------|-------------|---------|
| `--format=FORMAT`, `-f FORMAT` | Output format (tree/list) | `--format=list`, `-f tree` |
| `--show-hidden` | Show hidden files | `zz tree --show-hidden` |
| `--no-gitignore` | Include gitignored files | `zz tree --no-gitignore` |
| `[depth]` | Maximum depth | `zz tree . 2` |

### Output Symbols
```
├── Regular file/directory
└── Last item in directory
[...] Ignored directory
```

## Prompt Command

### Basic Usage
```bash
zz prompt file.txt                    # Single file
zz prompt "*.zig"                     # Glob pattern
zz prompt "src/**/*.zig"              # Recursive glob
zz prompt src/                        # Directory
```

### Options
| Option | Description | Example |
|--------|-------------|---------|
| `--prepend=TEXT` | Add text before | `--prepend="Review:"` |
| `--append=TEXT` | Add text after | `--append="Thanks!"` |
| `--allow-empty-glob` | Warn on empty glob | `--allow-empty-glob` |
| `--allow-missing` | Warn on missing files | `--allow-missing` |

### Glob Patterns
| Pattern | Matches | Example |
|---------|---------|---------|
| `*` | Any characters | `*.zig` → `main.zig` |
| `?` | Single character | `test?.zig` → `test1.zig` |
| `**` | Recursive | `**/*.zig` → all .zig files |
| `{a,b}` | Alternatives | `*.{zig,c}` → `.zig` or `.c` |
| `[abc]` | Character class | `[a-z].txt` → `a.txt`, `b.txt` |
| `[!abc]` | Negated class | `[!0-9].txt` → non-digit |
| `\*` | Escape special | `file\*.txt` → `file*.txt` |

## Benchmark Command

### Basic Usage
```bash
zz benchmark                          # Run all benchmarks
zz benchmark --format=pretty          # Colored output
zz benchmark --only=path,string       # Specific tests
zz benchmark --skip=glob              # Skip tests
```

### Options
| Option | Description | Default |
|--------|-------------|---------|
| `--format=FORMAT` | Output format | `markdown` |
| `--iterations=N` | Base iterations | `1000` |
| `--baseline=FILE` | Compare with file | `benchmarks/baseline.md` |
| `--no-compare` | Skip comparison | `false` |
| `--only=LIST` | Run specific | all |
| `--skip=LIST` | Skip specific | none |
| `--warmup` | Include warmup | `false` |

### Output Formats
- `markdown` - Tables for documentation
- `json` - Machine-readable
- `csv` - Spreadsheet import
- `pretty` - Colored terminal output

### Output Symbols (Pretty Format)
```
✓ Performance improved (green)
⚠ Performance regressed (yellow)
? New benchmark (cyan)
[====------] Progress bar
```

## Configuration (zz.zon)

### Basic Structure
```zon
.{
    .base_patterns = "extend",           // or custom array
    .ignored_patterns = .{
        "node_modules",
        "target",
    },
    .hidden_files = .{
        ".DS_Store",
    },
    .symlink_behavior = "skip",          // skip/follow/show
    .respect_gitignore = true,
}
```

### Pattern Types
| Setting | Purpose | Example |
|---------|---------|---------|
| `base_patterns` | How to handle defaults | `"extend"` or array |
| `ignored_patterns` | Directories to skip | `"node_modules"` |
| `hidden_files` | Files to hide completely | `".DS_Store"` |
| `symlink_behavior` | How to handle symlinks | `"skip"` |
| `respect_gitignore` | Use .gitignore | `true` |

## Build Commands

### Development
```bash
zig build                    # Debug build
zig build test              # Run tests
zig build run -- tree       # Run directly
```

### Installation
```bash
zig build install-user      # Install to ~/.zz/bin
zig build install           # System install
```

### Optimization
```bash
zig build -Doptimize=ReleaseFast   # Maximum speed
zig build -Doptimize=ReleaseSafe   # With safety checks
zig build -Doptimize=ReleaseSmall  # Minimum size
```

### Benchmarking
```bash
zig build benchmark              # Run and save
zig build benchmark-baseline     # Create baseline
zig build benchmark-stdout       # Display only
```

## Shell Integration

### Aliases (.bashrc/.zshrc)
```bash
alias t='zz tree'
alias t2='zz tree . 2'
alias tl='zz tree --format=list'
alias zp='zz prompt'
alias bench='zz benchmark --format=pretty'
```

### Functions
```bash
# Prompt all files of type
zpall() { zz prompt "**/*.$1"; }

# Tree without gitignore
treeall() { zz tree --no-gitignore "$@"; }

# Quick benchmark check
benchcheck() {
    zz benchmark --format=pretty | grep -E "✓|⚠"
}
```

### Completions (Example)
```bash
complete -W "tree prompt benchmark help" zz
```

## Common Workflows

### Code Review
```bash
# Review changed files
git diff --name-only | xargs zz prompt

# Review specific module
zz prompt "src/module/**/*.zig"
```

### Documentation
```bash
# Generate structure
zz tree > project-structure.md

# Create prompt for docs
zz prompt "src/**/*.zig" --prepend="Document:"
```

### Performance Check
```bash
# Quick check
zz benchmark --format=pretty

# Detailed comparison
zz benchmark --baseline=old.md
```

### Project Analysis
```bash
# Overview
zz tree . 2

# Find large directories
zz tree --format=list | xargs du -h | sort -h

# Count files by type
zz tree --format=list | rev | cut -d. -f1 | rev | sort | uniq -c
```

## Performance Tips

### Speed
- Use `--format=list` for large directories
- Limit depth with number argument
- Add large dirs to ignored_patterns
- Use Release build for production

### Memory
- Limit depth for huge trees
- Use specific paths vs `**`
- Enable string pooling
- Close other programs

### Accuracy
- Use Release mode for benchmarks
- Increase iterations for stability
- Run multiple times and average
- Close CPU-intensive programs

## Troubleshooting

### Common Issues
| Problem | Solution |
|---------|----------|
| Command not found | Add `~/.zz/bin` to PATH |
| Permission denied | Use `sudo` or skip with patterns |
| Slow on network | Limit depth, disable gitignore |
| Memory error | Reduce scope, add ignores |
| Benchmark variance | Use Release build, close programs |

### Debug Commands
```bash
# Check version
zig version

# Verify installation
which zz
zz help

# Test basic operation
echo test > test.txt
zz prompt test.txt
rm test.txt

# Check configuration
cat zz.zon
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Error (general) |
| 1 | Benchmark regression detected |
| 2 | Invalid arguments |
| 3 | File not found |
| 4 | Permission denied |

## Environment Variables

| Variable | Purpose | Example |
|----------|---------|---------|
| `PATH` | Find zz binary | `export PATH="$PATH:~/.zz/bin"` |
| `NO_COLOR` | Disable colors (future) | `NO_COLOR=1 zz benchmark` |
| `ZZ_DEBUG` | Debug output (future) | `ZZ_DEBUG=1 zz tree` |

## Links

- [Full Documentation](README.md)
- [Architecture](ARCHITECTURE.md)
- [Troubleshooting](TROUBLESHOOTING.md)
- [Patterns & Recipes](PATTERNS.md)