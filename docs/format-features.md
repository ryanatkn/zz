# Format Module Features

Language-aware code formatting with AST-based transformation and modular architecture.

## Supported Languages

### Full AST-Based Formatting

Languages with complete AST-driven formatting:

#### JSON
- Smart indentation with configurable depth
- Intelligent line-breaking decisions
- Optional trailing commas
- Key sorting (alphabetical or custom)
- Compact vs pretty printing
- Preserves or normalizes string quotes

#### CSS
- Selector formatting with proper nesting
- Property alignment options
- Media query indentation
- Vendor prefix organization
- Color format normalization
- Minification support

#### HTML
- Tag indentation with nesting awareness
- Attribute formatting (single line vs multi-line)
- Whitespace preservation in pre/code blocks
- Self-closing tag handling
- Comment formatting

#### Zig
- Full AST-based formatting (modular architecture)
- C-style `format_*.zig` pattern
- Container formatting (struct/enum/union)
- Function and parameter formatting
- Statement and expression formatting
- Comment preservation

#### TypeScript/JavaScript
- Full AST-based formatting (modular architecture)
- Function and arrow function formatting
- Class and interface formatting
- Import/export organization
- JSX/TSX support
- Type annotation formatting

#### Svelte
- Multi-section awareness (script/style/markup)
- Reactive statement formatting
- Component prop formatting
- Slot and event handling

### External Tool Integration

#### Zig (Alternative)
- Integration with external `zig fmt` tool
- Fallback when AST formatter unavailable

## C-Style Modular Architecture

The formatter uses a clean C-style naming convention for better organization:

### File Naming Pattern

All formatter modules follow the `format_{feature}.zig` pattern:

```
src/lib/languages/typescript/
├── formatter.zig           # Main orchestration (62 lines)
├── format_class.zig        # Class declaration formatting
├── format_function.zig     # Function formatting
├── format_interface.zig    # Interface formatting
├── format_parameter.zig    # Parameter formatting
├── format_type.zig         # Type alias formatting
├── format_import.zig       # Import/export formatting
└── typescript_utils.zig    # Language utilities

src/lib/languages/zig/
├── formatter.zig           # Main orchestration (37 lines)
├── node_dispatcher.zig     # AST node routing
├── format_function.zig     # Function formatting
├── format_parameter.zig    # Parameter formatting
├── format_declaration.zig  # Declaration formatting
├── format_body.zig         # Container body formatting
├── format_statement.zig    # Statement formatting
├── format_container.zig    # Struct/enum/union formatting
├── format_import.zig       # @import formatting
├── format_variable.zig     # Variable formatting
├── format_test.zig         # Test block formatting
└── zig_utils.zig          # Language utilities
```

### Struct Naming Convention

Simple, language-agnostic names without prefixes:

```zig
// Before: TypeScriptClassFormatter
// After: FormatClass

pub const FormatClass = struct {
    pub fn formatClass(...) !void { ... }
};
```

## Formatting Options

### Indentation

```bash
$ zz format --indent-size=2         # 2 spaces (default: 4)
$ zz format --indent-style=tab      # Use tabs
$ zz format --indent-style=space    # Use spaces (default)
```

### Line Width

```bash
$ zz format --line-width=80         # 80 character limit
$ zz format --line-width=100        # 100 characters (default)
$ zz format --line-width=120        # 120 characters
```

### Language-Specific Options

#### JSON Options
```bash
$ zz format --trailing-comma         # Add trailing commas
$ zz format --sort-keys              # Sort object keys
$ zz format --compact                # Minimal whitespace
```

#### JavaScript/TypeScript Options
```bash
$ zz format --quote-style=single     # Use single quotes
$ zz format --quote-style=double     # Use double quotes
$ zz format --semicolons=always      # Always add semicolons
$ zz format --semicolons=never       # Remove semicolons (ASI)
```

#### CSS Options
```bash
$ zz format --hex-case=lower         # Lowercase hex colors
$ zz format --hex-case=upper         # Uppercase hex colors
$ zz format --compact-css            # Single-line rules
```

## Operation Modes

### Format Mode (Default)

Output formatted code to stdout:

```bash
$ zz format config.json              # View formatted output
$ zz format "src/**/*.ts"            # Format all TypeScript files
```

### Write Mode

Format files in-place:

```bash
$ zz format config.json --write      # Modify file directly
$ zz format "**/*.css" --write       # Format all CSS files
```

### Check Mode

Verify if files are properly formatted (CI-friendly):

```bash
$ zz format "src/**/*.zig" --check   # Exit 1 if not formatted
$ zz format . --check                # Check all files
```

Returns:
- Exit code 0: All files formatted correctly
- Exit code 1: One or more files need formatting

### Stdin Mode

Format input from stdin:

```bash
$ echo '{"a":1}' | zz format --stdin
$ cat ugly.json | zz format --stdin > pretty.json
```

## AST-Based Techniques

### Tree-Sitter Integration

- Full AST parsing for semantic understanding
- Preserves code semantics while reformatting
- Handles malformed code gracefully
- Language-specific node handling

### Smart Formatting Decisions

#### Line Breaking
- Breaks long lines at semantic boundaries
- Preserves logical grouping
- Respects operator precedence

#### Indentation
- Context-aware indentation
- Continuation line handling
- Block nesting recognition

#### Whitespace
- Consistent spacing around operators
- Proper alignment of similar constructs
- Removal of trailing whitespace

## Performance Features

### AST Caching
- Parsed ASTs cached for multiple passes
- Shared cache across formatting operations
- LRU eviction for memory management

### Parallel Processing
- Multiple files formatted concurrently
- Thread pool for CPU utilization
- Lock-free data structures

### Memory Efficiency
- Arena allocators for temporary data
- String interning for common tokens
- Streaming output for large files

## Error Handling

### Graceful Degradation
- Falls back to original format on parse errors
- Preserves unparseable sections
- Clear error messages with location info

### Validation
- Ensures formatted output is valid syntax
- Round-trip testing (format → parse → format)
- Semantic equivalence checking

## Integration Examples

### Pre-commit Hook

```bash
#!/bin/sh
# .git/hooks/pre-commit
files=$(git diff --cached --name-only --diff-filter=ACMR | grep -E '\.(zig|ts|json)$')
if [ -n "$files" ]; then
    echo "$files" | xargs zz format --check || {
        echo "Files need formatting. Run: zz format --write"
        exit 1
    }
fi
```

### CI Pipeline

```yaml
# .github/workflows/format.yml
- name: Check formatting
  run: |
    zz format "src/**/*.{zig,ts,json}" --check
```

### Editor Integration

```json
// VS Code settings.json
{
  "editor.formatOnSave": true,
  "[zig]": {
    "editor.defaultFormatter": "zz.format"
  }
}
```

## Implementation Details

- **Core Infrastructure**: `src/lib/parsing/formatter.zig` - Language dispatch
- **Language Formatters**: `src/lib/languages/{lang}/format_*.zig` - Modular formatters
- **CLI Integration**: `src/format/main.zig` - Command handling
- **Glob Support**: Same GlobExpander as prompt module
- **Memory Management**: LineBuilder utility for efficient string building

## Configuration

Format settings in `zz.zon`:

```zon
.format = .{
    .indent_size = 4,
    .indent_style = .space,
    .line_width = 100,
    .preserve_newlines = true,
    .trailing_comma = false,
    .sort_keys = false,
},
```

## Future Enhancements

- Additional language support (Python, Rust, Go)
- Format configuration files (`.zzfmt`)
- Incremental formatting for large files
- Format-on-type for editor integration
- Custom formatting rules via plugins