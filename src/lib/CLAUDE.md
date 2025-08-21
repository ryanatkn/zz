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
├── test/            # Test utilities and fixtures
│
# Stream-First Architecture (Phase 1-2 Complete)
├── stream/          # ✅ Generic streaming infrastructure (zero-allocation)
├── fact/            # ✅ Facts as universal data unit (24 bytes)
├── span/            # ✅ Efficient span management (8 bytes packed)
├── token/           # ✅ StreamToken with tagged unions (1-2 cycle dispatch)
├── lexer/           # ⚠️ TEMPORARY bridge to old lexers (delete in Phase 4)
├── cache/           # ✅ Fact caching with LRU eviction
└── query/           # 🎯 Phase 3 - SQL-like query engine (planned)
```

## What's Working

### Original Architecture
- **Character Module**: Centralized character classification and text consumption
- **Text Module**: Comprehensive text processing, delimiters, and formatting utilities
- **JSON & ZON Languages**: Production-ready with full lexer/parser/formatter/linter
- **Centralized AST System**: Shared infrastructure for all languages
- **Pattern Matching**: High-performance glob and gitignore handling
- **Language Patterns**: Each language has its own patterns.zig for language-specific patterns
- **Core Utilities**: Language detection, path operations, memory management

### Stream-First Architecture (NEW)
- **Stream Module**: Zero-allocation generic streaming with 8.9M ops/sec
- **Fact Module**: Universal data unit at exactly 24 bytes, 100M facts/sec creation
- **Span Module**: Packed spans at 8 bytes with 200M ops/sec
- **Token Module**: Tagged union dispatch in 1-2 cycles (vs 3-5 for vtable)
- **Cache Module**: Multi-indexed fact cache with LRU eviction
- **Memory Module**: Arena pools and atom tables for zero-allocation paths
- **Test Coverage**: 207+ tests passing (96% pass rate)

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

### Original Modules
- [Character utilities](char/CLAUDE.md)
- [Text processing](text/CLAUDE.md)
- [Core utilities](core/CLAUDE.md)
- [AST system](ast/CLAUDE.md) 
- [Pattern matching](patterns/CLAUDE.md)
- Language-specific docs in respective directories

### Stream-First Modules
- [Stream infrastructure](stream/README.md)
- [Fact system](fact/README.md)
- [Span primitives](span/README.md)
- [Token architecture](token/README.md)
- [Lexer bridge](lexer/CLAUDE.md) - TEMPORARY
- [Cache system](cache/CLAUDE.md)

### Architecture Documents
- [Stream-First Architecture](../../TODO_STREAM_FIRST_ARCHITECTURE.md)
- [Design Principles](../../TODO_STREAM_FIRST_PRINCIPLES.md)
- [Phase 2 Status](../../TODO_STREAM_FIRST_PHASE_2.md)
- [Phase 3 Plan](../../TODO_STREAM_FIRST_PHASE_3.md)
- [Known Issues](../../TODO_STREAM_FIRST_KNOWN_ISSUES.md)
