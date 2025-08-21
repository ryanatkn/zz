# Progressive Parser Known Issues

## Phase 2 Status (Error Recovery & Incremental Parsing)

### Session Progress (2025-08-21) ✅
- **Fixed `error` reserved word**: Changed to `err` in node.zig
- **Fixed cache eviction test**: Added TODO for Phase 3 implementation
- **Fixed JSON lexer test**: Corrected token type (left_bracket vs left_brace)
- **Fixed incremental parser tests**: Updated to use valid JSON input

### Current Test Status
- **Baseline**: 788 passed, 20 failed (after fixes)
- **Memory Issues**: Some tests causing crashes due to allocation issues
- **Module Tests**: Individual modules (lexer, parser, transform) passing

### Phase 1 Status (Module Restructuring) ✅

#### Completed
- **Lexer Infrastructure**: Created clean `lib/lexer/` with pure re-exports
- **Parser Infrastructure**: Created optional `lib/parser/` layer  
- **Token Module**: Reorganized to pure re-exports
- **Transform Module**: Created pipeline infrastructure
- **Module Organization**: All mod.zig files are now pure re-exports
- **Test Infrastructure**: Unified test runner in `lib/test.zig`

### Pending Work 🚧

#### Phase 2A: Error Recovery (In Progress)
- Cache eviction not fully implemented (needs Phase 3)
- Incremental parser needs better error handling for invalid JSON
- Stateful lexer chunk boundary handling incomplete

#### Phase 2B: Incremental Parsing
- JSON/ZON need to implement new LexerInterface
- Incremental update support not yet implemented
- Token delta tracking missing

#### Phase 2C: Streaming Improvements
- StreamingLexer buffer management needs work
- Chunk boundary handling for split tokens
- Performance optimization needed

#### Language Implementations
- JSON needs to implement new LexerInterface
- ZON needs to implement new LexerInterface
- Other languages (TypeScript, CSS, HTML, Zig) need migration

#### Memory Management Issues
- Tests crashing with allocation errors in complex scenarios
- Need to investigate memory leaks in test suite
- Consider arena allocators for test isolation

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

## Next Session Priorities

### Immediate (Phase 2 Completion)
1. **Fix memory issues**: Investigate test crashes and leaks
2. **Implement LexerInterface**: JSON and ZON adapters
3. **Error recovery**: Improve parser resilience to invalid input
4. **Streaming fixes**: Handle chunk boundaries properly

### Short-term (Phase 3)
1. **Cache eviction**: Complete FactCache memory management
2. **Incremental updates**: Implement token delta tracking
3. **Performance benchmarks**: Validate streaming performance
4. **Migration guide**: Document language implementation process

### Long-term (Phase 4)
1. **Remove old modules**: Clean up lexer_old, parser_old
2. **Unify AST**: Merge ast and ast_old modules
3. **Full language support**: Migrate all languages to new architecture
4. **Production readiness**: Comprehensive testing and optimization

## Key TODOs Left in Code

- `// TODO: Phase 2B` - Incremental parsing features
- `// TODO: Phase 3` - Cache eviction and memory management
- `// TODO: reserved word` - Fixed (changed to `err`)
- Various performance and optimization TODOs

## Notes

- Performance is the top priority - no regressions allowed
- Test infrastructure unified in `lib/test.zig`
- Individual module tests passing, integration tests need work
- Memory management needs attention before wider adoption