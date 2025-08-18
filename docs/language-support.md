# Language Support

## Current Language Implementation Status

### ✅ Production-Ready Languages

#### JSON (100% Complete)
- **Lexer**: High-performance streaming tokenization (<0.1ms for 10KB)
- **Parser**: AST-based with error recovery (<1ms for 10KB)
- **Formatter**: Configurable pretty-printing (<0.5ms for 10KB)
- **Linter**: 7 built-in validation rules
- **Analyzer**: Schema extraction, TypeScript interface generation
- **Infrastructure**: Uses centralized AST factory, traversal, and query systems

#### ZON (100% Complete)
- **Lexer**: All Zig literal types supported
- **Parser**: Native AST construction with proper memory management
- **Formatter**: Comment preservation, configurable indentation
- **Validator**: Schema validation with 9 built-in rules
- **Serializer**: Bidirectional struct <-> ZON conversion
- **Infrastructure**: Fully integrated with centralized AST system

### 🚧 Stub Implementations (Awaiting Development)

#### TypeScript
- **Status**: Basic structure ready
- **Planned**: Full lexer, parser, formatter using stratified parser
- **Note**: .ts files only, no .tsx support yet

#### CSS
- **Status**: Stub module with interface implementation
- **Planned**: Selector parsing, property validation, media queries
- **Existing**: Basic formatter structure

#### HTML
- **Status**: Stub module ready
- **Planned**: DOM tree construction, attribute parsing
- **Existing**: Basic element detection

#### Zig
- **Status**: Stub implementation
- **Planned**: Integration with stratified parser, delegates to `zig fmt`
- **Note**: Full language support for primary language

#### Svelte
- **Status**: Stub for multi-language support
- **Planned**: Script/style/template region detection
- **Note**: Most complex due to embedded languages

## Unified Language Architecture

### Language Interface (`src/lib/languages/interface.zig`)

All languages implement the same contract:

```zig
pub const LanguageSupport = struct {
    language: Language,
    lexer: Lexer,
    structure: ?StructureParser,
    parser: Parser,
    formatter: Formatter,
    linter: ?Linter,
    analyzer: ?Analyzer,
};
```

### Language Registry (`src/lib/languages/registry.zig`)

Centralized language dispatch with caching:

```zig
const registry = try LanguageRegistry.init(allocator);
const support = try registry.getSupport(.json);
const formatted = try support.formatter.format(ast, options);
```

### Common Infrastructure (`src/lib/languages/common/`)

Shared utilities for all languages:
- **tokens.zig**: Common token types (operators, keywords)
- **patterns.zig**: Shared parsing patterns
- **formatting.zig**: Common formatting utilities
- **analysis.zig**: Shared analysis tools with AST traversal

## Pure Zig Implementation

### No Tree-sitter Dependencies

The project has completely eliminated tree-sitter:
- ❌ **Removed**: All FFI code, C bindings, external parsers
- ✅ **Replaced**: Pure Zig stratified parser architecture
- ✅ **Benefits**: Better performance, easier debugging, complete control

### Stratified Parser Architecture

Three-layer parsing system:
1. **Lexical Layer**: Fast tokenization
2. **Structural Layer**: Boundary detection
3. **Detailed Layer**: Full AST construction

## Code Extraction Capabilities

### Extraction Flags

The system supports intelligent code extraction (currently for JSON/ZON, planned for others):

- `--signatures`: Function/method signatures
- `--types`: Type definitions (structs, enums, interfaces)
- `--docs`: Documentation comments
- `--structure`: Code organization without implementations
- `--imports`: Import/include statements
- `--errors`: Error handling patterns
- `--tests`: Test functions
- `--full`: Complete content (default)

### Language Detection

Automatic detection based on file extension:
- `.zig` → Zig language module
- `.ts`, `.js` → TypeScript module
- `.css` → CSS module
- `.html` → HTML module
- `.json` → JSON module
- `.zon` → ZON module
- `.svelte` → Svelte module

## Performance Targets

All languages aim for these benchmarks:

| Operation | Target | JSON Status | ZON Status |
|-----------|--------|-------------|------------|
| Lexing | <0.1ms/10KB | ✅ Achieved | ✅ Achieved |
| Parsing | <1ms/10KB | ✅ Achieved | ✅ Achieved |
| Formatting | <0.5ms/10KB | ✅ Achieved | ✅ Achieved |
| Full Pipeline | <2ms/10KB | ✅ Achieved | ✅ Achieved |

## Testing Infrastructure

### Language Test Structure
```
src/lib/languages/<lang>/
├── mod.zig      # Module exports
├── lexer.zig    # Tokenization
├── parser.zig   # AST construction
├── formatter.zig # Code formatting
├── test.zig     # Comprehensive tests
└── README.md    # Documentation
```

### Test Coverage
- **JSON**: 698 lines of tests, 100% API coverage
- **ZON**: ~1000 lines of tests, comprehensive coverage
- **Others**: Awaiting implementation

## Future Development

### Priority Order
1. **CSS** - Migrate existing formatter, add parser
2. **HTML** - Basic DOM parsing
3. **TypeScript** - Full implementation with type analysis
4. **Zig** - Primary language support
5. **Svelte** - Complex multi-language handling

### Planned Features
- Language Server Protocol (LSP) support
- Cross-language analysis (imports, dependencies)
- Incremental parsing for editor integration
- Custom language plugin system

## Migration Guide

### From Tree-sitter to Pure Zig

For developers adding new languages:

1. Create module in `src/lib/languages/<lang>/`
2. Implement `LanguageSupport` interface
3. Use centralized AST infrastructure
4. Add to language registry
5. Write comprehensive tests

### Using the Language System

```zig
// Get language support
const support = try registry.getSupport(.json);

// Parse source code
const tokens = try support.lexer.tokenize(source);
const ast = try support.parser.parse(tokens);

// Format the AST
const formatted = try support.formatter.format(ast, .{
    .indent_size = 4,
    .trailing_comma = true,
});

// Run linting
if (support.linter) |linter| {
    const diagnostics = try linter.lint(ast, rules);
}
```

The language support system provides a clean, unified interface for all language processing in zz, with production-ready JSON and ZON implementations demonstrating the architecture's effectiveness.