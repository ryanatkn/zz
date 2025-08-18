# Lib Module - Language Tooling Library

Core utilities and language infrastructure for zz. Performance-optimized for POSIX systems.

## Directory Structure

```
src/lib/
├── char/            # Character utilities (single source of truth for all char operations)
├── core/            # Fundamental utilities (language detection, extraction, path ops)
├── patterns/        # Pattern matching (glob, gitignore patterns) 
├── ast/             # Enhanced AST infrastructure with traversal, transformation, query
├── languages/       # Language implementations (JSON ✅, ZON ✅, TS/Zig/CSS/HTML patterns)
├── parser/          # Stratified parser (lexical → structural → detailed)
├── grammar/         # Grammar definition system
├── text/            # Text processing and manipulation
├── memory/          # Memory pools and management
├── filesystem/      # Filesystem abstraction layer
└── test/            # Test utilities and fixtures
```

## What's Working

- **Character Module**: Centralized character classification and text consumption
- **Text Module**: Comprehensive text processing, delimiters, and formatting utilities
- **JSON & ZON Languages**: Production-ready with full lexer/parser/formatter/linter
- **Centralized AST System**: Shared infrastructure for all languages
- **Pattern Matching**: High-performance glob and gitignore handling
- **Language Patterns**: Each language has its own patterns.zig for language-specific patterns
- **Core Utilities**: Language detection, path operations, memory management

## Architecture Highlights

- **No Duplication**: Character operations centralized in `char/` module
- **Language Patterns**: Each language owns its patterns (typescript/patterns.zig, etc.)
- **Unified Lexing**: All lexers use char module for consistent behavior
- **Clean Separation**: Common utilities in `common/`, language-specific in each module

## Key Features

- **Pure Zig Architecture**: No external dependencies
- **Stratified Parser**: Three-layer system for optimal performance
- **Memory Safe**: Proper cleanup with owned_texts tracking
- **Extensible**: Easy to add new languages via common interfaces

## Documentation

For detailed information see:
- [Character utilities](char/CLAUDE.md)
- [Text processing](text/CLAUDE.md)
- [Core utilities](core/CLAUDE.md)
- [AST system](ast/CLAUDE.md) 
- [Pattern matching](patterns/CLAUDE.md)
- Language-specific docs in respective directories
