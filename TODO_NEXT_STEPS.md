# TODO: Next Steps - Token Consolidation Complete

## Token System Status: ✅ COMPLETE
- Renamed `StreamToken` → `Token` throughout codebase
- Eliminated dual token imports and confusion
- Implemented hybrid pattern: Token union for generic code, language extractors for specific code
- All benchmarks and tests working (730/732 passing, same as before)

## Minor Cleanup Remaining

### JSON Linter Bridge Method
- `src/lib/languages/json/linter/core.zig:205` - TODO about removing bridge method
- Current: Has both `lint(ast)` and `lintSource(source)` methods
- Consider: Unify around token stream validation

### Test Infrastructure
- `src/lib/test.zig:39` - Benchmark test disabled due to "old token infrastructure"
- May be re-enableable now that token system is unified
- Check if benchmark test works with new Token system

### Potential Optimizations
- JSON lexer performance: Currently 143μs for 10KB (target: <100μs)
- Consider token dispatch optimizations if needed
- Profile token creation vs union wrapping costs

## Architecture Considerations

### Token Creation Pattern
Current pattern in lexers:
```zig
const json_token = JsonToken{ ... };
return Token{ .json = json_token };
```

Could potentially optimize to direct construction if profiling shows bottlenecks.

### Documentation Updates
- ✅ Updated all StreamToken references to Token
- ✅ Fixed demo and validation scripts
- ✅ Cleaned up CLAUDE.md references

## Non-Critical Items

### Type Name Consistency
- `JsonToken` in tests vs language-specific types
- Consider if any further naming standardization needed
- Current approach is functional and clear

### Memory Usage
- Token system working within 24-byte target
- Stream architecture maintaining zero-allocation goals
- No known memory issues

## Status Summary
Core token consolidation work is **complete and successful**. All remaining items are optional optimizations or minor cleanup that don't affect functionality.

## More tests

- round trip formatting checks
- formatting minification option