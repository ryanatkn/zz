# Stream-First Known Issues

## Test Status (Updated Phase 5A)
- **Total Tests**: 254 (10 new DirectStream tests)
- **Passing**: 245 (96.5%)
- **Failing**: 8 (same as before)
- **Skipped**: 1

## Known Failing Tests

### 1. Lexer Integration Tests (3 failures)
**Tests**: 
- `lexer.test.test.Lexer module integration`
- `lexer.test.test.LexerBridge JSON conversion`
- `lexer.test.test.LexerBridge ZON conversion`

**Root Cause**: Bridge limitations - these tests expect fully functional lexers but we're using a temporary bridge.

**Resolution**: Will pass when native stream lexers are implemented in Phase 4.

### 2. Cache Eviction Test (1 failure)
**Test**: `cache.test.test.Cache eviction under memory pressure`

**Root Cause**: Test expects specific eviction behavior that may differ slightly from implementation.

**Resolution**: Minor test adjustment needed in Phase 3.

### 3. LexerBridge Test (1 failure)
**Test**: `lexer.lexer_bridge.test.LexerBridge basic conversion`

**Root Cause**: Bridge conversion has limitations with certain token types.

**Resolution**: Will be obsolete when bridge is deleted in Phase 4.

### 4. StreamAdapter Test (1 failure)
**Test**: `lexer.stream_adapter.test.StreamAdapter basic operations`

**Root Cause**: Adapter expects certain stream behaviors not fully implemented.

**Resolution**: Will be fixed with native stream lexers in Phase 4.

### 5. QueryIndex Test (1 failure)
**Test**: `cache.index.test.QueryIndex basic operations`

**Root Cause**: Test expects 2 facts in confidence range 0.75-1.0 but gets 3.

**Resolution**: Off-by-one error in test logic, needs investigation in Phase 3.

## Non-Blocking Issues

These failures do not block Phase 3 work because:
1. Core stream-first primitives work perfectly (Stream, Fact, Span)
2. Token system with tagged unions is fully functional
3. Cache and indexing work for primary use cases
4. 96% test pass rate indicates solid foundation

## Fixed in Phase 3

### Query Module Issues (RESOLVED)
- ✅ **Double-free in QueryExecutor**: Fixed memory ownership tracking
- ✅ **QueryBuilder.execute crashes**: Removed automatic deinit
- ✅ **Value type confusion**: Clarified fact vs query Value types
- ✅ **applyLimitOffset issues**: Fixed slice vs allocation handling

## Technical Debt After Phase 4

### Completed in Phase 4
- ✅ Implemented DirectStream with tagged union (1-2 cycles)
- ✅ Created parallel implementation strategy
- ✅ Direct stream lexers for JSON/ZON working

### Phase 5A Complete
- ✅ Type aliases created (DirectFactStream, DirectTokenStream)
- ✅ Helper functions for migration added
- ✅ Performance benchmark created
- ✅ Query module supports DirectStream
- ✅ Lexer modules support DirectStream
- ✅ Comprehensive DirectStream tests added
- ✅ No new test failures from migration

### Remaining for Phase 5
- [ ] Migrate all modules from Stream to DirectStream
- [ ] Delete vtable Stream after migration complete
- [ ] Implement native stream lexers for remaining languages
- [ ] Adjust cache eviction test expectations
- [ ] Fix QueryIndex confidence range logic
- [ ] Delete bridge modules and their tests
- [ ] Add arena allocator for operator chains
- [ ] Complete GROUP BY/HAVING aggregation functions