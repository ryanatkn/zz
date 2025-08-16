# ECS Architecture Migration

// TODO measure this before switching over

## Status: Planning

Performance-critical ECS for file processing, AST operations, and parallel traversal.

## Core Components

- **Entities**: File handles, AST nodes, parse tasks
- **Components**: Path, Content, AST, Status, Dependencies
- **Systems**: Parser, Formatter, Traverser, Cache, Extractor

## Key Systems

```zig
// File Processing Pipeline
FileLoader -> Parser -> Extractor -> Formatter -> Cache

// AST Operations
ASTBuilder -> Validator -> Transformer -> Optimizer

// Parallel Traversal  
DirectoryScanner -> FileFilter -> ContentProcessor -> ResultAggregator
```

## Performance Targets

- **File processing**: 10k+ files/sec
- **AST operations**: 1M+ nodes/sec  
- **Memory usage**: <100MB for large codebases
- **Cache efficiency**: >95% hit rate

## Implementation Plan

1. **Entity/Component foundation** - Core ECS primitives
2. **File system integration** - Directory traversal as ECS pipeline
3. **AST processing** - Tree-sitter operations as components
4. **Parallel execution** - Worker pools and job scheduling
5. **Memory optimization** - Component pooling and recycling

## Integration Points

- Replace `src/lib/traversal.zig` with ECS traversal system
- Migrate AST operations to component-based architecture
- Parallel prompt generation using ECS job system
- Cache system as ECS components with LRU eviction

## Benefits

- **Parallelism**: Natural task decomposition
- **Memory efficiency**: Component pooling and reuse
- **Modularity**: Clean separation of concerns
- **Performance**: Cache-friendly data layout
- **Scalability**: Easy addition of new processing stages