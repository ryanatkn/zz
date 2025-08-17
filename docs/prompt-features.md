# Prompt Module Features

The prompt module generates LLM-optimized prompts from codebases with sophisticated AST-based extraction and glob pattern support.

## AST-Based Code Extraction

The prompt module uses **real tree-sitter AST parsing** for all supported languages, not text matching. This enables precise, semantic code extraction.

### Extraction Flags

Extract specific code elements with AST node traversal:

- `--signatures`: Function/method signatures via AST
- `--types`: Type definitions (structs, enums, unions) via AST
- `--docs`: Documentation comments via AST nodes
- `--imports`: Import statements (text-based currently)
- `--errors`: Error handling patterns (text-based currently)
- `--tests`: Test blocks via AST
- `--full`: Complete source (default for backward compatibility)

### Composable Extraction

Combine multiple flags for targeted extraction:

```bash
$ zz prompt --signatures --types "*.zig"        # Functions and types only
$ zz prompt --docs --tests "src/**/*.ts"        # Documentation and tests
$ zz prompt --imports --signatures "*.py"       # Dependencies and API surface
```

### Language Support

- **Full AST Support**: Zig, TypeScript, CSS, HTML, JSON, Svelte
- **Language Detection**: Automatic based on file extension
- **Graceful Fallback**: Falls back to text extraction for unsupported languages
- **Extensible Architecture**: Ready for future language grammars

## Glob Pattern Support

Powerful file matching with Unix-style glob patterns:

### Basic Patterns

- **Wildcards**: `*.zig`, `test?.zig`
- **Recursive**: `src/**/*.zig` (all .zig files under src/)
- **Brace Expansion**: `*.{zig,md,txt}`, `src/*.{c,h}`
- **Character Classes**: 
  - `log[0-9].txt` matches log0.txt through log9.txt
  - `file[a-zA-Z].txt` matches any single letter
  - `test[!0-9].txt` matches test with non-digit

### Optimized Common Patterns

These patterns are specially optimized for performance:
- `*.{zig,c,h}` - Systems programming files
- `*.{js,ts,jsx,tsx}` - TypeScript files
- `*.{md,txt,rst}` - Documentation files
- `*.{json,yaml,yml,toml}` - Configuration files

### Pattern Features

- **Automatic Deduplication**: Multiple patterns matching the same file only include it once
- **Order Preservation**: Files appear in the order first matched
- **Ignore Integration**: Respects .gitignore and zz.zon patterns

## Directory Support

Process entire directory trees efficiently:

```bash
$ zz prompt src/                     # Recursively process all files
$ zz prompt src/ --signatures        # Extract signatures from entire tree
$ zz prompt . --types                # Extract types from current directory
```

### Directory Features

- **Recursive Processing**: Automatically processes subdirectories
- **Ignore Patterns**: Skips hidden directories and common ignore patterns
  - `.git`, `.hg`, `.svn` - Version control
  - `node_modules`, `vendor` - Dependencies
  - `.zig-cache`, `target`, `build` - Build artifacts
- **Early Skip Optimization**: Directories are skipped before traversal for performance
- **Pattern Integration**: Seamlessly combines with glob patterns and explicit files

## Smart Code Fencing

Intelligent Markdown code block generation:

- **Auto-detection**: Automatically determines required fence length
- **Nested Blocks**: Handles code containing ``` markers correctly
- **Syntax Highlighting**: Preserves language hints for syntax coloring
- **Clean Output**: Ensures proper escaping without breaking formatting

## Output Format

Structured output optimized for LLM consumption:

### Semantic XML Tags

Files are wrapped in semantic XML tags for context:

```xml
<File path="src/main.zig">
// File contents here
</File>
```

### Markdown Formatting

- Clean markdown with proper code fences
- Language hints for syntax highlighting
- Structured headers for file boundaries
- Configurable via templates

### Configuration

Ignore patterns configured via `zz.zon`:

```zon
.prompt = .{
    .ignore_patterns = .{
        "**/*.test.zig",
        "**/node_modules/**",
        "build/**",
    },
},
```

## Error Handling

Strict by default with clear, actionable error messages:

### Default Behavior

- **No Auto-patterns**: Errors if no files specified (no automatic `*.zig`)
- **Strict Validation**: Errors on missing files or empty globs
- **Explicit Ignore Detection**: Errors when explicitly requested files are ignored

### Permissive Options

- `--allow-empty-glob`: Convert empty glob errors to warnings
- `--allow-missing`: Convert missing file errors to warnings
- `--allow-ignored`: Process explicitly ignored files anyway

### Text-Only Mode

Using `--prepend` or `--append` without files is valid for text-only output:

```bash
$ zz prompt --prepend "Project context: Web app" --append "Questions: ..."
```

### Error Message Types

Clear distinction between error sources:

- **Glob Pattern Errors**: Pattern matched no files (can be silenced)
- **Explicit File Errors**: Named file doesn't exist (always an error)
- **Ignore Conflicts**: Explicitly requested file is in ignore list
- **Permission Errors**: Cannot read file due to permissions

## Performance Optimizations

- **AST Caching**: Parsed ASTs are cached for repeated access
- **Parallel Processing**: Multiple files processed concurrently
- **Early Directory Skipping**: Ignored directories skipped before traversal
- **Memory Pooling**: Reuses allocations across file processing
- **Streaming Output**: Results streamed to avoid memory buildup

## Advanced Usage

### Multi-pattern Extraction

```bash
# Extract different elements from different files
$ zz prompt --signatures "src/**/*.zig" \
            --types "include/**/*.h" \
            --docs "README.md"
```

### Pipeline Integration

```bash
# Pipe to LLM tools
$ zz prompt --signatures "*.zig" | llm "Explain this API"

# Save for documentation
$ zz prompt --docs --types "src/**/*.ts" > api-docs.md
```

### CI/CD Integration

```bash
# Generate documentation in CI
$ zz prompt --docs --signatures "src/**/*" > docs/api.md
$ git diff --exit-code docs/api.md || echo "Docs need update"
```

## Implementation Details

- **Module Location**: `src/prompt/`
- **Core Logic**: `builder.zig` - Prompt building with filesystem abstraction
- **Pattern Handling**: `glob.zig` - Glob pattern expansion
- **Fence Detection**: `fence.zig` - Smart fence length calculation
- **Configuration**: `config.zig` - Prompt-specific settings
- **Tests**: Comprehensive test suite with mock filesystem