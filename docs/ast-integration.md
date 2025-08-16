# AST Integration Framework

## Unified NodeVisitor Pattern

All language parsers implement a consistent `walkNode()` interface using the NodeVisitor pattern for extensible AST traversal:

```zig
// Example: CSS AST extraction
pub fn walkNode(allocator: std.mem.Allocator, root: *const AstNode, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
    var extraction_context = ExtractionContext{
        .allocator = allocator,
        .result = result,
        .flags = flags,
        .source = source,
    };
    
    var visitor = NodeVisitor.init(allocator, cssExtractionVisitor, &extraction_context);
    try visitor.traverse(root, source);
}
```

## Language-Specific Implementations

- **HTML Parser**: Element detection, structure analysis, event handler extraction
- **JSON Parser**: Structural nodes, key extraction, schema analysis, type detection
- **Svelte Parser**: Section-aware parsing (script/style/template), reactive statements, props extraction
- **CSS Parser**: Selector matching, rule extraction, variable detection, media queries
- **TypeScript Parser**: Enhanced with dependency analysis and import extraction
- **Zig Parser**: Maintains existing tree-sitter integration while conforming to unified interface

## Mock AST Framework

- Complete AST abstraction layer using `AstNode` structure
- Generic pointer support for future tree-sitter integration
- Mock implementations for testing without external dependencies
- Visitor pattern supports both real and mock AST traversal

## Incremental Processing with AST Cache

The incremental processing system includes sophisticated AST cache management:

```zig
// FileTracker with AST cache support
pub const FileTracker = struct {
    allocator: std.mem.Allocator,
    files: std.HashMap([]const u8, FileState, std.hash_map.StringContext, 80),
    dependency_graph: DependencyGraph,
    change_detector: ChangeDetector,
    ast_cache: ?*AstCache, // Optional AST cache for invalidation
};
```

### Smart Cache Invalidation

- **File Hash-based Keys**: AST cache entries keyed by file hash + extraction flags
- **Selective Invalidation**: `invalidateByFileHash()` removes only entries for changed files
- **Cascade Invalidation**: Automatically invalidates dependent files when imports change
- **Dependency Tracking**: Uses dependency graph to identify affected files

### Cache Key Generation

```zig
// Generate cache key for file with extraction flags
pub fn getAstCacheKey(self: *FileTracker, file_path: []const u8, extraction_flags_hash: u64) ?AstCacheKey {
    if (self.files.get(file_path)) |file_state| {
        return AstCacheKey.init(
            file_state.hash,
            1, // parser version
            extraction_flags_hash
        );
    }
    return null;
}
```

### Performance Benefits

- **Incremental Parsing**: Only re-parse files that have actually changed
- **Cache Efficiency**: High cache hit rate for unchanged files with different extraction flags
- **Memory Management**: LRU eviction with configurable memory limits
- **Dependency Optimization**: Cascade invalidation prevents stale cache entries

## Extraction Flags

The AST extraction system supports fine-grained control through extraction flags:

- `--signatures`: Function/method signatures via AST
- `--types`: Type definitions (structs, enums, unions) via AST
- `--docs`: Documentation comments via AST nodes
- `--imports`: Import statements (text-based currently)
- `--errors`: Error handling patterns (text-based currently)
- `--tests`: Test blocks via AST
- `--structure`: Structural outline of the code
- `--full`: Complete source (default for backward compatibility)

Flags can be combined for targeted extraction: `--signatures --types --docs`

## Adding New Language Support

To add support for a new language:

1. Create parser in `src/lib/parsers/<language>.zig`
2. Create extractor in `src/lib/extractors/<language>.zig`
3. Implement `walkNode()` interface with NodeVisitor pattern
4. Add language detection in `src/lib/language/detection.zig`
5. Create test fixtures in `src/lib/test/fixtures/<language>/`
6. Update language support documentation