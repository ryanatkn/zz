# Lib Module - Language Tooling Library

Core utilities and language infrastructure for zz. Performance-optimized for POSIX systems.

## Directory Structure

```
src/lib/
├── core/            # Fundamental utilities (language detection, extraction, path ops)
├── patterns/        # Pattern matching (glob, gitignore) 
├── ast/             # Enhanced AST infrastructure with traversal, transformation, query
├── languages/       # Language implementations (JSON ✅, ZON ✅, others stubbed)
├── parser/          # Stratified parser (lexical → structural → detailed)
├── grammar/         # Grammar definition system
└── test/            # Test utilities and fixtures
```

## What's Working

- **JSON & ZON Languages**: Production-ready with full lexer/parser/formatter/linter
- **Centralized AST System**: Shared infrastructure for all languages
- **Pattern Matching**: High-performance glob and gitignore handling
- **Core Utilities**: Language detection, path operations, memory management

## What's Deleted (Aggressive Cleanup)

- `analysis/` - Complex tree-sitter infrastructure 
- `benchmark.zig` - Legacy benchmark system (stubbed)
- `language/` & `parsing/` - Moved to `core/` and `patterns/`
- Legacy test files - Outdated fixture loaders

## Key Features

- **Pure Zig Architecture**: No external dependencies
- **Stratified Parser**: Three-layer system for optimal performance
- **Memory Safe**: Proper cleanup with owned_texts tracking
- **Extensible**: Easy to add new languages via common interfaces

## Documentation

For detailed information see:
- [Core utilities](core/CLAUDE.md)
- [AST system](ast/CLAUDE.md) 
- [Pattern matching](patterns/CLAUDE.md)
- Language-specific docs in respective directories
