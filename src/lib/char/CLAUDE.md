# Character Module - Single Source of Truth

Centralized character classification and text consumption utilities used by all lexers and parsers in zz.

## Architecture

**Design Philosophy:**
- **Single Source of Truth:** All character operations in one place
- **Zero Duplication:** No repeated implementations across modules
- **Performance First:** All predicates are inline functions
- **Consistent Behavior:** Same rules apply everywhere

## Module Structure

```
src/lib/char/
├── predicates.zig    # Character classification functions
├── consumers.zig     # Text consumption utilities
└── mod.zig          # Module exports
```

## Predicates (`predicates.zig`)

**Character Classification Functions:**

```zig
// Whitespace checking
isWhitespace(ch)         // space, tab, \r (NOT \n)
isWhitespaceOrNewline(ch) // space, tab, \r, \n
isNewline(ch)            // only \n

// Digit checking
isDigit(ch)              // 0-9
isHexDigit(ch)           // 0-9, a-f, A-F
isBinaryDigit(ch)        // 0-1
isOctalDigit(ch)         // 0-7

// Alphabetic checking
isAlpha(ch)              // a-z, A-Z
isAlphaNumeric(ch)       // a-z, A-Z, 0-9
isUpper(ch)              // A-Z
isLower(ch)              // a-z

// Identifier checking
isIdentifierStart(ch)    // a-z, A-Z, _, $
isIdentifierChar(ch)     // a-z, A-Z, 0-9, _, $

// Other classifications
isStringDelimiter(ch)    // ", '
isOperatorChar(ch)       // +, -, *, /, etc.
isDelimiterChar(ch)      // (, ), {, }, [, ], ;, ,, .
isControl(ch)            // Control characters
isPrintable(ch)          // Printable ASCII
```

## Consumers (`consumers.zig`)

**Text Consumption Functions:**

```zig
// Whitespace skipping
skipWhitespace(source, pos) -> usize
skipWhitespaceAndNewlines(source, pos) -> usize

// Identifier consumption
consumeIdentifier(source, pos) -> usize

// String literal consumption
consumeString(source, pos, quote, allow_escapes) -> StringResult
    .end: usize
    .terminated: bool
    .has_escapes: bool

// Number consumption
consumeNumber(source, pos) -> NumberResult
    .end: usize
    .is_float: bool
    .is_hex: bool
    .is_binary: bool
    .is_octal: bool

// Comment consumption
consumeSingleLineComment(source, pos, prefix) -> usize
consumeMultiLineComment(source, pos, start_delim, end_delim) -> BlockCommentResult
    .end: usize
    .terminated: bool
    .line_count: usize
```

## Usage Examples

### In Lexers

```zig
const char = @import("../../char/mod.zig");

fn skipWhitespace(self: *Lexer) void {
    const new_pos = char.skipWhitespace(self.source, self.position);
    self.position = new_pos;
}

fn isValidIdentifierStart(ch: u8) bool {
    return char.isIdentifierStart(ch);
}
```

### In Parsers

```zig
const char = @import("../../char/mod.zig");

// Consume a number literal
const result = char.consumeNumber(source, pos);
if (result.is_float) {
    // Handle float
} else if (result.is_hex) {
    // Handle hex
}
```

### Direct Imports

```zig
// Import specific functions
const isDigit = @import("char/mod.zig").isDigit;
const skipWhitespace = @import("char/mod.zig").skipWhitespace;

// Or import predicates/consumers namespaces
const predicates = @import("char/mod.zig").predicates;
const consumers = @import("char/mod.zig").consumers;
```

## Performance Characteristics

- **Predicates:** ~1-2ns per call (all inline)
- **Skip functions:** O(n) where n is whitespace length
- **Consume functions:** O(n) where n is token length
- **Zero allocations:** All functions work with slices
- **Cache friendly:** Sequential memory access

## Migration Guide

**Before (duplicated in each module):**
```zig
fn isDigit(ch: u8) bool {
    return ch >= '0' and ch <= '9';
}

fn skipWhitespace(self: *Lexer) void {
    while (self.position < self.source.len) {
        if (!isWhitespace(self.source[self.position])) break;
        self.position += 1;
    }
}
```

**After (using char module):**
```zig
const char = @import("../../char/mod.zig");

// Direct use
if (char.isDigit(ch)) { ... }

// Position update
self.position = char.skipWhitespace(self.source, self.position);
```

## Consumers Used By

- `parser/lexical/scanner.zig` - Scanner uses char predicates
- `parser/lexical/tokenizer.zig` - Tokenizer uses char predicates
- `languages/json/lexer.zig` - JSON lexer uses all utilities
- `languages/zon/lexer.zig` - ZON lexer uses all utilities
- `parser/lexical/utils.zig` - Re-exports for compatibility

## Design Decisions

1. **Whitespace vs Newline:** Separate functions for clarity
   - `isWhitespace()` doesn't include `\n` 
   - Use `isWhitespaceOrNewline()` when needed

2. **Identifier Rules:** Support common languages
   - `$` included for JavaScript compatibility
   - `_` universally supported

3. **Return Positions:** Functions return end position
   - Easier to chain operations
   - Clear what was consumed

4. **Result Structs:** Rich information for complex operations
   - Know if string was terminated
   - Know number format (hex, binary, etc.)
   - Count lines in comments

## Testing

All functions have comprehensive tests in their respective files:
```bash
zig build test -Dtest-filter="src/lib/char/predicates.zig"
zig build test -Dtest-filter="src/lib/char/consumers.zig"
```

## Future Enhancements

1. **Unicode Support:** UTF-8 character classification
2. **Custom Rules:** Configurable identifier rules per language
3. **SIMD Optimization:** Vectorized whitespace skipping
4. **Streaming API:** Incremental consumption for large files

The char module ensures consistent, efficient character handling across all of zz's language processing.