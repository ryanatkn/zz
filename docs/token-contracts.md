# Token Contracts - Language-Specific TokenKind Requirements

**Created**: 2025-08-19  
**Purpose**: Document exact TokenKind values each language lexer must emit for consistent parser behavior

## Overview

All language lexers must use the foundation `TokenKind` enum defined in `src/lib/parser/foundation/types/predicate.zig`. This document specifies which token types each language must emit for consistent parser integration.

## Foundation TokenKind Reference

```zig
pub const TokenKind = enum {
    // Literals
    string_literal,     // "hello", 'world'
    number_literal,     // 123, 45.67, 0xFF
    boolean_literal,    // true, false  
    null_literal,       // null

    // Identifiers
    identifier,         // variable names, function names

    // Operators
    operator,           // +, -, *, /, etc.

    // Delimiters  
    left_paren,        // (
    right_paren,       // )
    left_brace,        // {
    right_brace,       // }
    left_bracket,      // [
    right_bracket,     // ]
    comma,             // ,
    colon,             // :
    semicolon,         // ;

    // Keywords (language-specific)
    keyword,           // if, else, function, etc.

    // Whitespace & Comments
    whitespace,        // spaces, tabs
    newline,           // \n, \r\n
    comment,           // // or /* */

    // Special
    eof,              // end of file
    unknown,          // fallback for unrecognized
};
```

## Language-Specific Contracts

### JSON Language Contract

**Required TokenKind Values:**
- `string_literal` - JSON strings ("hello")
- `number_literal` - JSON numbers (123, 45.67)  
- `boolean_literal` - JSON booleans (true, false)
- `null_literal` - JSON null
- `left_brace` - Object start {
- `right_brace` - Object end }
- `left_bracket` - Array start [
- `right_bracket` - Array end ]
- `comma` - Value separator ,
- `colon` - Key-value separator :
- `whitespace` - Spaces, tabs (optional if trimmed)
- `newline` - Line breaks (optional if trimmed)
- `eof` - End of input

**Forbidden TokenKind Values:**
- `keyword` - JSON has no keywords
- `operator` - JSON has no operators
- `identifier` - JSON has no bare identifiers

**Special Rules:**
- String tokens must include quotes in token text ("hello" not hello)
- Number tokens must be valid JSON numbers
- Boolean/null tokens must be exactly "true", "false", "null"

### ZON Language Contract

**Required TokenKind Values:**
- `string_literal` - ZON strings ("hello", 'char')
- `number_literal` - ZON numbers (123, 45.67, 0xFF)
- `boolean_literal` - ZON booleans (true, false)
- `null_literal` - ZON null
- `identifier` - Field names, type names
- `left_brace` - Struct/object start {
- `right_brace` - Struct/object end }
- `left_bracket` - Array start [
- `right_bracket` - Array end ]
- `left_paren` - Tuple start (
- `right_paren` - Tuple end )
- `comma` - Value separator ,
- `colon` - Type annotation :
- `operator` - Assignment = and field access .
- `whitespace` - Spaces, tabs (optional if trimmed)
- `newline` - Line breaks (optional if trimmed)
- `comment` - Line comments // (if preserve_comments = true)
- `eof` - End of input

**Special Rules:**
- Field names (.name) should be tokenized as operator + identifier
- Assignment (=) should use `operator` token type
- Character literals ('x') should use `string_literal` 
- Comments only emitted if preserve_comments option is true

### TypeScript Language Contract (Planned)

**Required TokenKind Values:**
- `string_literal` - String literals ("hello", 'world', \`template\`)
- `number_literal` - Numeric literals (123, 45.67, 0xFF)
- `boolean_literal` - Boolean literals (true, false)
- `null_literal` - Null literal
- `identifier` - Variable/function/type names
- `keyword` - TypeScript keywords (function, class, interface, etc.)
- `operator` - Operators (+, -, =>, etc.)
- All delimiter types (braces, brackets, parens, comma, colon, semicolon)
- `whitespace`, `newline`, `comment` as appropriate
- `eof` - End of input

### CSS Language Contract (Planned)

**Required TokenKind Values:**
- `string_literal` - CSS strings ("Helvetica", 'Arial')
- `number_literal` - CSS numbers (10px, 1.5em, 100%)
- `identifier` - Selectors, properties, values
- `left_brace` - Rule block start {
- `right_brace` - Rule block end }
- `left_bracket` - Attribute selector [
- `right_bracket` - Attribute selector ]
- `left_paren` - Function calls (
- `right_paren` - Function calls )
- `colon` - Property separator :
- `semicolon` - Declaration separator ;
- `comma` - Multi-value separator ,
- `whitespace`, `newline`, `comment`
- `eof` - End of input

## EOF Token Standardization

**All lexers must emit EOF token:**
- **Position**: EOF token span should be (input.len, input.len)
- **Text**: EOF token text should be empty string ""
- **Kind**: Must be `TokenKind.eof`
- **Placement**: Always last token in stream

**Example EOF Token:**
```zig
const eof_token = Token.simple(
    Span.init(input.len, input.len),
    .eof,
    "",
    0
);
```

## Testing Requirements

**All lexers must pass:**
1. **Token Kind Test**: Emit only documented TokenKind values
2. **EOF Test**: Always end with proper EOF token
3. **Round-trip Test**: Concatenated token.text equals original input
4. **Position Test**: Token spans cover entire input with no gaps

**Standard Test Corpus:**
Each language should test these scenarios:
- Empty input (only EOF)
- Single token of each type
- Complex nested structures
- Whitespace handling
- Comment handling (if applicable)
- Error recovery for malformed input

## Migration Guide

**For existing lexers:**
1. Review current `TokenKind` usage against this contract
2. Update any non-conforming token types
3. Ensure EOF token is always emitted
4. Add missing token type tests
5. Verify streaming integration works

**For new lexers:**
1. Start with language contract from this document
2. Implement required TokenKind values only
3. Add streaming support via TokenIterator adapters
4. Follow standard test corpus
5. Document any language-specific extensions

## Performance Requirements

**All lexers must:**
- Complete tokenization of 10KB input in <10ms
- Support streaming via TokenIterator adapters
- Use string slices (not allocations) where possible
- Handle malformed input gracefully

## Future Extensions

**Planned additions:**
- HTML token contract (tags, attributes, text content)
- Zig token contract (keywords, operators, literals)
- Svelte token contract (component syntax)

**Contract versioning:**
- Breaking changes require major version bump
- New optional token types are backward compatible
- Lexer interface changes affect all languages

---

**Note**: This contract ensures all language lexers can integrate seamlessly with TokenIterator streaming, AST parsers, and tooling infrastructure. Deviating from these contracts will break parser expectations and streaming integration.