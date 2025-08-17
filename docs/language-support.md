# Language Support

> ⚠️ AI slop code and docs, is unstable and full of lies

## Supported Languages with Complete AST Integration

- **Zig** - Full AST support for functions, types, tests, docs
- **CSS** - Selectors, properties, variables, media queries  
- **HTML** - Elements, attributes, semantic structure, event handlers
- **JSON** - Structure validation, key extraction, schema analysis
- **TypeScript** - Functions, interfaces, types (.ts files only, no .tsx)
- **Svelte** - Multi-section components (script/style/template) with section-aware parsing

## AST-Based Code Extraction

The prompt module provides real tree-sitter AST parsing for all supported languages with precise extraction capabilities:

### Extraction Flags

- `--signatures`: Function/method signatures via AST
- `--types`: Type definitions (structs, enums, unions) via AST
- `--docs`: Documentation comments via AST nodes
- `--imports`: Import statements (text-based currently)
- `--errors`: Error handling patterns (text-based currently)
- `--tests`: Test blocks via AST
- `--structure`: Structural outline of the code
- `--full`: Complete source (default for backward compatibility)

### Composable Extraction

Combine flags for targeted extraction:
```bash
zz prompt src/ --signatures --types
zz prompt "**/*.ts" --signatures --docs --imports
```

### Language Detection

Automatic detection based on file extension:
- `.zig` → Zig parser
- `.ts` → TypeScript parser
- `.css` → CSS parser
- `.html` → HTML parser
- `.json` → JSON parser
- `.svelte` → Svelte parser

### Graceful Fallback

For unsupported languages, the system falls back to text extraction, ensuring all files can be processed.

## Language-Specific Features

### TypeScript
- Interfaces and type aliases
- Function signatures with types
- Class definitions and methods
- Import/export statements
- Generic type parameters

### CSS
- Selector matching and specificity
- CSS variables and custom properties
- Media queries and @-rules
- Nested rules (when using preprocessors)
- Animation and keyframe definitions

### HTML
- Semantic element structure
- Attribute extraction
- Event handler detection
- Meta tags and head content
- Form element analysis

### JSON
- Schema validation
- Key path extraction
- Type inference
- Nested structure analysis
- Array element inspection

### Svelte
- Multi-section parsing (script/style/template)
- Component props extraction
- Reactive statements ($:)
- Store subscriptions
- Event dispatchers

### Zig
- Function definitions with signatures
- Struct, enum, and union types
- Test blocks
- Doc comments
- Comptime expressions

## Code Formatting Support

The format module provides language-aware formatting:

- **JSON:** Smart indentation, line-breaking, optional trailing commas, key sorting
- **CSS:** Selector formatting, property alignment, media query indentation
- **HTML:** Tag indentation, attribute formatting, whitespace preservation
- **Zig:** Integration with external `zig fmt` tool
- **TypeScript/Svelte:** Basic support (placeholders for future enhancement)

### Format Options

```bash
zz format config.json                    # Output formatted JSON to stdout
zz format config.json --write            # Format file in-place
zz format "src/**/*.json" --check        # Check if files are formatted
echo '{"a":1}' | zz format --stdin       # Format from stdin
zz format "*.css" --indent-size=2        # Custom indentation
```

## Adding New Language Support

See [AST Integration Guide](./ast-integration.md#adding-new-language-support) for instructions on adding support for new languages.