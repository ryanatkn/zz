# Progressive Parser Known Issues

## Phase 1 Status (Module Restructuring)

### Completed ✅
- **Lexer Infrastructure**: Created clean `lib/lexer/` with pure re-exports
- **Parser Infrastructure**: Created optional `lib/parser/` layer  
- **Token Module**: Reorganized to pure re-exports
- **Transform Module**: Created pipeline infrastructure
- **Module Organization**: All mod.zig files are now pure re-exports

### Pending Work 🚧

#### Language Implementations
- JSON needs to implement new LexerInterface
- ZON needs to implement new LexerInterface
- Other languages (TypeScript, CSS, HTML, Zig) need migration

#### Import Path Issues
- AST module references need updating (using ast_old paths)
- Fact module imports may need adjustment
- Stream module compatibility with new interfaces

#### Test Failures
- 21 test failures related to module boundaries
- TokenIterator tests failing due to import changes
- Stream lexer tests need updating

## Known Issues

### 1. Circular Dependencies
- **Issue**: Some modules have circular import dependencies
- **Affected**: lexer ↔ token, parser ↔ ast
- **Solution**: Use forward declarations or interface separation

### 2. Missing AST Module
- **Issue**: Parser references `../ast/node.zig` which doesn't exist in new structure
- **Status**: Using ast_old for now
- **Solution**: Create new AST module or update imports

### 3. Fact Module Integration
- **Issue**: Transform module references fact module that may need updates
- **Status**: Fact module exists but integration untested
- **Solution**: Verify fact module compatibility

### 4. Stream Compatibility
- **Issue**: DirectStream vs Stream usage inconsistent
- **Status**: Both implementations coexist
- **Solution**: Migrate fully to DirectStream for performance

### 5. Language Support Contracts
- **Issue**: Languages don't yet implement new interfaces
- **Affected**: All language modules
- **Solution**: Update each language incrementally

## Migration Path

### Immediate (Phase 1 Completion)
1. Fix AST module references
2. Update JSON to implement LexerInterface
3. Update ZON to implement LexerInterface
4. Fix test failures

### Short-term (Phase 2)
1. Migrate remaining languages
2. Remove lexer_old module
3. Unify Stream implementations
4. Add incremental support

### Long-term (Phase 3-4)
1. Implement viewport optimization
2. Add speculative parsing
3. Complete fact projections
4. Performance benchmarking

## Performance Considerations

### Current State
- Token dispatch: 1-2 cycles (StreamToken)
- Module indirection: Added 1 level (pure re-exports)
- Memory: No regression expected

### Target Metrics
- Lexer streaming: <1ms/KB
- Parser boundaries: <5ms for 1000 lines
- Format operation: <1ms/KB
- Memory usage: <200KB per MB source

## Breaking Changes

### API Changes
1. Lexers must now implement `LexerInterface`
2. Parsers consume tokens, not raw source
3. Transform pipelines replace direct formatting
4. Facts are optional projections

### Import Changes
```zig
// Old
const Lexer = @import("lib/lexer_old/mod.zig").Lexer;

// New
const LexerInterface = @import("lib/lexer/mod.zig").LexerInterface;
```

## Testing Strategy

### Unit Tests
- Each module has isolated tests
- Mock implementations for interfaces
- Property-based testing for transforms

### Integration Tests
- End-to-end lexer → parser → transform
- Format command with new architecture
- Performance regression tests

### Known Test Issues
- `lib.token.test.test.TokenIterator basic operations` - Import error
- Stream lexer tests - Module boundary issues
- Transform tests - Not yet implemented

## Documentation Updates Needed

1. Update CLAUDE.md in each module
2. Update main README with new architecture
3. Create migration guide for language implementers
4. Document performance characteristics

## Next Steps

1. **Fix critical issues**: AST module, test failures
2. **Complete JSON/ZON**: Implement new interfaces
3. **Update format command**: Use new pipeline
4. **Benchmark**: Measure performance vs old architecture
5. **Clean up**: Remove deprecated code

## Notes

- Performance is the top priority - no regressions allowed
- Maintain backward compatibility during migration
- Delete old code aggressively once migrated
- Document all architectural decisions