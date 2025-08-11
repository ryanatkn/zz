# Glob Pattern Reference

## Overview
The `zz prompt` command supports advanced glob patterns for flexible file selection. Patterns are processed from left to right, with special characters providing powerful matching capabilities.

## Basic Wildcards

### `*` - Match Any Characters
Matches zero or more characters (except `/` and leading `.`)
```bash
*.zig           # All .zig files in current directory
test_*.zig      # Files starting with test_ and ending with .zig
*               # All non-hidden files
```

### `?` - Match Single Character
Matches exactly one character
```bash
?.zig           # Single character filenames: a.zig, b.zig
test?.zig       # test1.zig, test2.zig, but not test10.zig
file.???        # file with 3-character extension
```

## Recursive Patterns

### `**` - Recursive Directory Match
Matches zero or more directories recursively
```bash
src/**/*.zig    # All .zig files under src/, at any depth
**/*.test.zig   # All test files in any subdirectory
**/config.*     # All config files with any extension, anywhere
```

## Brace Expansion

### `{a,b,c}` - Alternatives
Expands to multiple patterns
```bash
*.{zig,rs,go}           # Matches .zig, .rs, or .go files
{main,test,lib}.zig     # main.zig, test.zig, or lib.zig
src/{cli,tree}/*.zig    # Files in src/cli/ or src/tree/
```

### Nested Braces
Braces can be nested for complex patterns
```bash
*.{zig,{md,txt}}        # Expands to: *.zig, *.md, *.txt
{src,test}/**/*.{zig,rs} # All .zig and .rs files under src/ or test/
file.{backup.{old,new},temp} # file.backup.old, file.backup.new, file.temp
```

**Note:** Maximum 32 alternatives per brace group

## Character Classes

### `[abc]` - Character Set
Matches any single character in the set
```bash
log[0-9].txt    # log0.txt through log9.txt
file[abc].zig   # filea.zig, fileb.zig, filec.zig
test[1-5].log   # test1.log through test5.log
```

### `[a-z]` - Character Range
Matches any character in the range
```bash
[a-z]*.zig      # Files starting with lowercase letter
log[A-Z].txt    # logA.txt through logZ.txt
v[0-9].[0-9]    # Version patterns: v1.0, v2.5, etc.
```

### `[!abc]` or `[^abc]` - Negated Set
Matches any character NOT in the set
```bash
log[!0-9].txt   # log files with non-numeric suffix
file[^a-z].zig  # file not followed by lowercase letter
```

### Multiple Ranges and Characters
```bash
[a-zA-Z0-9]     # Alphanumeric characters
[a-z0-9_-]      # Lowercase, digits, underscore, hyphen
```

## Escape Sequences

### `\` - Escape Special Characters
Use backslash to match literal special characters
```bash
file\*.txt      # Matches literal "file*.txt"
test\?.zig      # Matches literal "test?.zig"
log\[1\].txt    # Matches literal "log[1].txt"
path\\to\\file  # Matches literal backslashes
data\{a,b\}.csv # Matches literal "data{a,b}.csv"
```

## Hidden Files

### Default Behavior
- `*` does NOT match files starting with `.`
- Use `.*` to explicitly match hidden files

```bash
*           # All visible files
.*          # All hidden files
.*.zig      # Hidden .zig files
.{bashrc,zshrc,profile} # Specific hidden config files
```

## Complex Examples

### Project File Selection
```bash
# All source and test files
"src/**/*.{zig,test.zig}"

# Configuration files at any level
"**/{config,settings,preferences}.{json,yaml,toml}"

# Numbered log files from multiple directories
"{logs,archive,backup}/log[0-9][0-9].txt"

# All code files except tests
"src/**/*.zig" "!src/**/*.test.zig"
```

### Escaping in Different Contexts
```bash
# Files with special characters in names
"report\[draft\].md"       # report[draft].md
"data\*backup\*.csv"        # data*backup*.csv
"file\ with\ spaces.txt"    # file with spaces.txt
```

## Shell Quoting

When using glob patterns on the command line, quote them to prevent shell expansion:
```bash
./zz prompt "src/**/*.zig"         # Correct - zz handles the glob
./zz prompt src/**/*.zig           # Wrong - shell expands the glob
```

## Performance Tips

1. **Be Specific**: Use directory prefixes when possible
   - Good: `src/**/*.zig`
   - Slower: `**/*.zig`

2. **Limit Depth**: Use specific paths instead of `**` when you know the structure
   - Good: `src/tree/*.zig`
   - Slower: `src/**/tree/*.zig`

3. **Order Patterns**: Put more specific patterns first
   - Good: `main.zig src/*.zig **/*.zig`

## Limitations

- Maximum 32 alternatives in a single brace expansion
- No support for extended glob patterns (`!(pattern)`, `?(pattern)`, etc.)
- Patterns are case-sensitive
- No tilde expansion (`~/` doesn't expand to home directory)

## See Also

- Run `./zz help` for command-line usage
- Check README.md for general documentation
- See CLAUDE.md for implementation details