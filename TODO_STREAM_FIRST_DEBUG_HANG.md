# TODO_STREAM_FIRST_DEBUG_HANG.md - Fix Stream Formatting Hang Issue

## Status: ACTIVE - Critical Bug

**Issue**: Stream formatting works for simple values (`42`) but hangs infinitely for JSON objects (`{}`, `{"key":"value"}`)

## Problem Description

The `--stream` flag for the format command has been implemented but has a critical hanging issue:
- ✅ `echo '42' | zz format --stdin --stream` works
- ❌ `echo '{}' | zz format --stdin --stream` hangs forever
- ❌ `echo '{"test":1}' | zz format --stdin --stream` hangs forever

## Root Cause Analysis

### What We Know
1. **Simple tokens work**: Numbers, strings work fine
2. **Object/array tokens cause hangs**: Anything with `{` `}` or `[` `]` hangs
3. **EOF handling was improved**: Changed from `self.state == .start` to any state for EOF detection
4. **Basic flow works**: JSON lexer → DirectStream → Formatter loop

### What We Don't Know
1. **Exact hang location**: Is it in lexer, stream, or formatter?
2. **Token sequence**: What exact tokens are generated for `{}`?
3. **Buffer state**: Is the buffer properly being consumed?
4. **Loop termination**: Why doesn't the `while (try token_stream.next()) |token|` loop exit?

## Investigation Plan

### Phase 1: Detailed Logging
Add comprehensive logging to trace execution:

```zig
// In JsonStreamLexer.next()
std.debug.print("[JsonLexer] next() called, state={}, buffer_empty={}\n", .{self.state, self.buffer.isEmpty()});
std.debug.print("[JsonLexer] buffer content: '{s}'\n", .{self.buffer.remaining()});

// In formatWithStream loop  
std.debug.print("[FormatLoop] Got token: {}, count={}\n", .{token.json.kind, count});

// In JsonFormatter.writeToken
std.debug.print("[Formatter] Processing: {}\n", .{json_token.kind});
```

### Phase 2: Minimal Reproduction
Create the smallest possible test case:
1. Test with just `{` - does it hang?
2. Test with just `}` - does it hang? 
3. Test with `{}` character by character

### Phase 3: Buffer Investigation
Check if the issue is in RingBuffer:
- Is `isEmpty()` working correctly?
- Is `pop()` actually consuming characters?
- Are characters being double-consumed?

### Phase 4: Stream Pipeline Debug
Verify each stage:
1. JsonStreamLexer.next() returns proper tokens + EOF + null
2. toDirectStream() properly wraps the lexer
3. DirectStream.next() calls through to lexer correctly
4. Loop exits when DirectStream.next() returns null

## Files to Investigate

### Core Files
- `src/lib/languages/json/stream_lexer.zig` - EOF detection logic
- `src/lib/stream/direct_stream_sources.zig` - GeneratorStream implementation
- `src/format/main.zig` - formatWithStream loop

### Test Files
- Create test in `src/lib/languages/json/stream_lexer.zig` that reproduces hang
- Add test that traces token sequence for `{}`

## Expected Fix

Likely one of these issues:
1. **Buffer not being consumed**: `makeSimpleToken` not properly calling `buffer.pop()`
2. **EOF not detected**: `buffer.isEmpty()` returns false when it should be true
3. **State machine issue**: Parser gets stuck in a state that never reaches EOF
4. **DirectStream issue**: GeneratorStream not properly handling null returns

## Testing Strategy

```bash
# Test cases that should work after fix:
echo '{}' | zz format --stdin --stream
echo '[]' | zz format --stdin --stream  
echo '{"key":"value"}' | zz format --stdin --stream
echo '[1,2,3]' | zz format --stdin --stream

# Should continue working:
echo '42' | zz format --stdin --stream
echo '"string"' | zz format --stdin --stream
echo 'true' | zz format --stdin --stream
```

## Current Code State

- [x] JsonStreamLexer has EOF handling (returns EOF, then null)
- [x] ZonStreamLexer has EOF handling (returns EOF, then null) 
- [x] Format command has --stream flag
- [x] Basic pipeline is connected
- [ ] **CRITICAL**: Hanging issue not resolved

## Next Session Action Items

1. **Add detailed logging** to trace exact execution flow
2. **Create minimal test** that reproduces the hang
3. **Identify root cause** through systematic debugging
4. **Implement fix** once root cause is found
5. **Test thoroughly** with various JSON inputs
6. **Remove debug logging** after fix is confirmed

## Success Criteria

✅ All test cases above work without hanging
✅ Stream formatting produces same output as regular formatting  
✅ Performance is good (no significant slowdown vs regular formatting)
✅ Memory usage is reasonable (no leaks)