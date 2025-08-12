# zz Patterns & Recipes

Common patterns and recipes for effective use of zz in real-world scenarios.

## Tree Visualization Patterns

### Project Overview

```bash
# Quick project overview (default depth)
zz tree

# Detailed view with specific depth
zz tree . 3

# Focus on source code only
echo '.{
    .ignored_patterns = .{
        "test", "tests", "spec", "docs", "examples"
    }
}' > zz.zon
zz tree src/
```

### Documentation Generation

```bash
# Generate project structure for README
zz tree --format=tree > project-structure.txt

# Create a clean structure for documentation
zz tree --format=list | grep -v test | head -20

# Export for project wiki
zz tree | sed 's/^/    /' > wiki-structure.md
```

### Code Review Preparation

```bash
# Show only changed files in tree format
git diff --name-only | xargs -I {} dirname {} | sort -u | xargs zz tree

# Focus on specific module
zz tree src/module/ --format=tree | less

# Compare two directories
diff <(zz tree dir1/) <(zz tree dir2/)
```

### CI/CD Integration

```yaml
# GitHub Actions example
- name: Validate Project Structure
  run: |
    expected=$(cat expected-structure.txt)
    actual=$(zz tree src/ --format=list)
    if [ "$expected" != "$actual" ]; then
      echo "Project structure changed!"
      exit 1
    fi
```

## Prompt Generation Patterns

### Code Review Prompts

```bash
# Review all changes
git diff --name-only | xargs zz prompt --prepend="Please review these changes:"

# Review specific file types
zz prompt "src/**/*.zig" --prepend="Review this Zig code for:" \
    --append="Focus on: memory safety, error handling, and performance"

# Review with context
zz prompt src/main.zig src/test.zig --prepend="Compare these implementations"
```

### Documentation Generation

```bash
# Generate API documentation
zz prompt "src/**/*.zig" --prepend="Generate API documentation for:" > api-docs.md

# Create user guide
zz prompt "examples/**/*.zig" --prepend="Create a user guide based on these examples:"

# Extract comments for docs
grep -h "///" src/**/*.zig | zz prompt --prepend="Format as documentation:"
```

### Learning and Analysis

```bash
# Understand codebase structure
zz prompt "src/**/main.zig" --prepend="Explain the architecture based on entry points:"

# Find patterns
zz prompt "src/**/*test*.zig" --prepend="What testing patterns are used?"

# Security audit
zz prompt "src/**/*.zig" --prepend="Audit for security issues: buffer overflows, integer overflows, unchecked errors"
```

### Migration and Refactoring

```bash
# Prepare for refactoring
zz prompt "src/old_module/*.zig" --prepend="Suggest refactoring to modern patterns:"

# Language migration
zz prompt "*.c" "*.h" --prepend="Convert this C code to Zig:"

# API migration
zz prompt "src/**/*.zig" --prepend="Update deprecated API calls from v1 to v2:"
```

## Benchmark Patterns

### Performance Testing Workflow

```bash
# Establish baseline before changes
zig build benchmark-baseline

# Make changes, then test
vim src/lib/path.zig
zig build benchmark

# If regression detected, investigate
git diff src/lib/path.zig
zig build benchmark --format=pretty
```

### Continuous Performance Monitoring

```bash
# Daily performance check
#!/bin/bash
date=$(date +%Y%m%d)
zz benchmark > benchmarks/daily/$date.md
zz benchmark --baseline=benchmarks/daily/$(date -d yesterday +%Y%m%d).md

# Weekly performance report
for day in benchmarks/daily/*.md; do
    echo "=== $(basename $day .md) ==="
    zz benchmark --baseline=$day --format=pretty | grep -E "✓|⚠"
done
```

### A/B Testing Optimizations

```bash
# Test optimization branch
git checkout main
zig build -Doptimize=ReleaseFast
zz benchmark > main.json --format=json

git checkout optimization
zig build -Doptimize=ReleaseFast  
zz benchmark > opt.json --format=json

# Compare results
jq -r '.results[] | "\(.name): \(.ns_per_op)"' main.json > main.txt
jq -r '.results[] | "\(.name): \(.ns_per_op)"' opt.json > opt.txt
paste main.txt opt.txt | column -t
```

## Configuration Patterns

### Per-Project Configuration

```zon
// Web project (JavaScript/TypeScript)
.{
    .base_patterns = "extend",
    .ignored_patterns = .{
        "node_modules",
        "dist",
        "build",
        ".next",
        ".nuxt",
        "coverage",
    },
    .hidden_files = .{
        ".DS_Store",
        "Thumbs.db",
        ".env.local",
    },
}

// Rust project
.{
    .base_patterns = "extend",
    .ignored_patterns = .{
        "target",
        "Cargo.lock",
    },
}

// Go project
.{
    .base_patterns = "extend",
    .ignored_patterns = .{
        "vendor",
        "bin",
        "*.test",
    },
}

// Machine Learning project
.{
    .base_patterns = "extend",
    .ignored_patterns = .{
        "data",
        "models",
        "checkpoints",
        ".ipynb_checkpoints",
        "__pycache__",
    },
}
```

### Environment-Specific Configs

```bash
# Development config
cp zz.dev.zon zz.zon
zz tree  # Shows test files

# Production config  
cp zz.prod.zon zz.zon
zz tree  # Hides test files

# CI config
cp zz.ci.zon zz.zon
zz tree  # Minimal output
```

## Shell Integration Patterns

### Aliases and Functions

```bash
# ~/.bashrc or ~/.zshrc

# Quick tree for current project
alias t='zz tree'
alias t2='zz tree . 2'
alias tl='zz tree --format=list'

# Prompt helpers
alias zp='zz prompt'
zpall() { zz prompt "**/*.$1"; }
zpdiff() { git diff --name-only | xargs zz prompt; }

# Benchmark shortcuts
alias bench='zig build benchmark'
alias benchbase='zig build benchmark-baseline'

# Project-specific trees
pyt() { zz tree --no-gitignore "$@"; }  # Python with all files
jst() { zz tree --ignore=node_modules "$@"; }  # JavaScript
rst() { zz tree --ignore=target "$@"; }  # Rust
```

### Workflow Functions

```bash
# Review function
review() {
    local files=$(git diff --name-only origin/main...HEAD)
    if [ -z "$files" ]; then
        echo "No changes to review"
        return
    fi
    echo "$files" | xargs zz prompt --prepend="Review changes:" | less
}

# Document function
document() {
    local module=$1
    zz prompt "src/$module/**/*.zig" \
        --prepend="Generate documentation for $module module:" \
        > "docs/$module.md"
}

# Analyze function
analyze() {
    echo "=== Project Structure ==="
    zz tree . 2
    echo -e "\n=== Code Statistics ==="
    find . -name "*.zig" | wc -l | xargs echo "Zig files:"
    find . -name "*.zig" -exec wc -l {} + | tail -1
    echo -e "\n=== Recent Changes ==="
    git log --oneline -5
}
```

### Pipeline Integration

```bash
# Pre-commit hook
#!/bin/sh
# .git/hooks/pre-commit

# Check for large files
large_files=$(zz tree --format=list | xargs -I {} stat -c "%s %n" {} 2>/dev/null | \
    awk '$1 > 1048576 {print $2}')

if [ ! -z "$large_files" ]; then
    echo "Large files detected (>1MB):"
    echo "$large_files"
    exit 1
fi

# Run benchmarks
if ! zz benchmark --format=json | jq -e '.results | all(.ns_per_op < 100000)' > /dev/null; then
    echo "Performance regression detected"
    exit 1
fi
```

## Advanced Patterns

### Parallel Processing

```bash
# Process multiple directories in parallel
dirs=(src/ test/ docs/)
for dir in "${dirs[@]}"; do
    zz tree "$dir" > "$dir.tree" &
done
wait

# Parallel prompt generation
find . -type f -name "*.zig" | \
    parallel -j4 'zz prompt {} > {.}.prompt'
```

### Incremental Documentation

```bash
# Track documentation coverage
total=$(zz tree --format=list src/ | wc -l)
documented=$(grep -l "///" $(zz tree --format=list src/) | wc -l)
echo "Documentation coverage: $documented/$total files"

# Generate missing docs
for file in $(zz tree --format=list src/); do
    if ! grep -q "///" "$file"; then
        zz prompt "$file" --prepend="Add documentation comments:" > "$file.docs"
    fi
done
```

### Custom Formatters

```bash
# JSON tree (future feature concept)
zz tree --format=json | jq '{
    name: .name,
    type: .type,
    children: .children | map({name: .name, size: .size})
}'

# CSV export
zz tree --format=list | while read path; do
    size=$(stat -c%s "$path" 2>/dev/null || echo 0)
    echo "$path,$size"
done > files.csv

# HTML tree
zz tree | awk '
    BEGIN { print "<ul>" }
    /^├──/ { gsub(/├── /, "<li>"); print }
    /^└──/ { gsub(/└── /, "<li>"); print }
    END { print "</ul>" }
' > tree.html
```

### Monitoring and Alerting

```bash
# Watch for changes
while true; do
    current=$(zz tree --format=list | md5sum)
    if [ "$current" != "$previous" ]; then
        echo "Changes detected at $(date)"
        zz tree
    fi
    previous=$current
    sleep 5
done

# Size monitoring
threshold=1000000  # 1GB
total_size=$(zz tree --format=list | xargs -I {} stat -c%s {} 2>/dev/null | \
    awk '{sum+=$1} END {print sum}')

if [ $total_size -gt $threshold ]; then
    echo "Warning: Directory size exceeds threshold: $total_size bytes"
fi
```

## Debugging Patterns

### Performance Investigation

```bash
# Find slow directories
time zz tree src/
time zz tree test/
time zz tree vendor/

# Profile pattern matching
for pattern in "*.zig" "**/*.zig" "*.{zig,c,h}"; do
    echo "Pattern: $pattern"
    time zz prompt "$pattern" > /dev/null
done

# Memory usage analysis
/usr/bin/time -v zz tree large_directory/
```

### Pattern Testing

```bash
# Test glob patterns
test_pattern() {
    local pattern=$1
    echo "Testing pattern: $pattern"
    zz prompt "$pattern" | head -5
    echo "Matched $(zz prompt "$pattern" | wc -l) files"
    echo "---"
}

test_pattern "*.zig"
test_pattern "src/**/*.zig"
test_pattern "*.{zig,c,h}"
```

## Integration Examples

### VS Code Tasks

```json
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "Show Project Tree",
            "type": "shell",
            "command": "zz tree",
            "problemMatcher": []
        },
        {
            "label": "Generate Prompt",
            "type": "shell",
            "command": "zz prompt '${file}'",
            "problemMatcher": []
        },
        {
            "label": "Run Benchmarks",
            "type": "shell",
            "command": "zz benchmark --format=pretty",
            "problemMatcher": []
        }
    ]
}
```

### Makefile Integration

```makefile
.PHONY: tree prompt bench docs

tree:
	@zz tree

prompt:
	@zz prompt "src/**/*.zig" > prompt.md

bench:
	@zig build benchmark

docs: 
	@zz tree > docs/structure.md
	@zz prompt "src/**/*.zig" --prepend="Generate docs:" > docs/api.md

check: bench
	@zz tree --format=list | wc -l | xargs echo "Files:"
	@echo "Benchmarks passed ✓"

clean:
	@rm -rf zig-cache zig-out
	@echo "Cleaned build artifacts"
```

### Docker Integration

```dockerfile
# Multi-stage build with zz for documentation
FROM zigimg/zig:latest as builder
WORKDIR /app
COPY . .
RUN zig build -Doptimize=ReleaseFast

FROM alpine:latest as docs
COPY --from=builder /app/zig-out/bin/zz /usr/local/bin/
WORKDIR /app
COPY src/ src/
RUN zz tree > /docs/structure.txt
RUN zz prompt "src/**/*.zig" > /docs/api.md

FROM alpine:latest
COPY --from=builder /app/zig-out/bin/app /usr/local/bin/
COPY --from=docs /docs /usr/share/doc/
```

## Tips and Tricks

### Performance Tips
- Use `--format=list` for large directories (faster than tree)
- Add common large directories to ignore patterns
- Build with `-Doptimize=ReleaseFast` for production use
- Use specific paths instead of `**` when possible

### Memory Tips
- Limit depth for large trees: `zz tree . 3`
- Use arena allocators in custom scripts
- Enable string pooling for repeated operations

### Productivity Tips
- Create project-specific aliases
- Use shell history search (Ctrl+R) for common patterns
- Combine with other tools: `fzf`, `ripgrep`, `jq`
- Set up editor integrations for quick access

### Debugging Tips
- Use `--format=json` for programmatic parsing
- Pipe to `less` for large outputs
- Save baselines before major changes
- Use `git bisect` with benchmarks for regression finding