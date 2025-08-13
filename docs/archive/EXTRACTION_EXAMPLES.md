# Code Extraction Examples

The `zz prompt` command now supports intelligent code extraction with multiple flags that can be combined for precise control.

## Basic Examples

### Extract only function signatures
```bash
$ zz prompt src/main.zig --signatures
```
Output: Just the function declarations without bodies

### Extract types and structures
```bash
$ zz prompt src/**/*.zig --types
```
Output: All type definitions, structs, and constants

### Extract documentation
```bash
$ zz prompt src/lib/*.zig --docs
```
Output: All documentation comments (///, //!)

## Combined Extraction

### API Documentation
```bash
$ zz prompt src/**/*.zig --signatures --types --docs
```
Output: Complete API surface with documentation

### Error Analysis
```bash
$ zz prompt src/**/*.zig --errors --tests
```
Output: All error handling code and related tests

### Import Graph
```bash
$ zz prompt src/**/*.zig --imports
```
Output: All import statements to understand dependencies

## Real-World Use Cases

### Preparing code for AI review
```bash
# Get high-level structure for understanding
$ zz prompt src/ --signatures --types

# Then drill into specific areas
$ zz prompt src/prompt/*.zig --full
```

### Creating API documentation
```bash
$ zz prompt src/lib/*.zig --signatures --types --docs > api.md
```

### Analyzing error handling
```bash
$ zz prompt src/**/*.zig --errors | grep "error\."
```

### Finding all tests
```bash
$ zz prompt src/**/*.zig --tests
```

## Default Behavior

Without any extraction flags, `--full` is assumed (backward compatible):
```bash
$ zz prompt src/main.zig
# Same as: zz prompt src/main.zig --full
```

## Language Support

Currently, extraction works best with Zig files. For other languages, the tool falls back to full source extraction until tree-sitter integration is complete.

## Performance

Extraction is fast - typically 5-10ms per file for signature extraction vs full source. This enables working with large codebases efficiently.

## Future Enhancements

- Full tree-sitter AST queries for precise extraction
- Support for TypeScript, Rust, Go, Python, and more
- Pattern-based extraction with `--match`
- Semantic extraction like `--public-only`
- JSON output format for tool integration