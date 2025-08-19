# Test Fixes Needed - Complex Issues

This document tracks the remaining test failures that require deeper investigation and more complex fixes.

## Issue Categories

### 1. Lexer EOF Token Issues

**Tests Affected:**
- `lib.languages.json.lexer.test.JSON lexer - simple values` (expected 1, found 2)
- `lib.languages.json.lexer.test.JSON lexer - complex number formats` (expected 1, found 2)
- `lib.languages.json.lexer.test.JSON lexer - object and array` (expected 11, found 12)
- `lib.languages.json.lexer.test.JSON lexer - string escapes` (expected 1, found 2)
- `lib.languages.json.lexer.test.JSON lexer - JSON5 features` (expected 2, found 3)

**Problem:**
Both JSON and ZON lexers automatically add EOF tokens with empty text, causing token count mismatches.

**Investigation Needed:**
1. Should lexers generate EOF tokens automatically?
2. Should tests expect EOF tokens?
3. How does this interact with the TokenIterator which expects non-empty text?

**Possible Solutions:**
- Remove EOF token generation from lexers
- Update all tests to account for EOF tokens
- Make EOF token generation optional

### 2. TokenIterator Text Validation

**Test Affected:**
- `lib.transform.streaming.token_iterator.test.TokenIterator - JSON lexer adapter`

**Problem:**
```zig
try testing.expect(token.text.len > 0);
```
Fails because EOF tokens have empty text.

**Investigation Needed:**
1. Should EOF tokens have empty text?
2. Should TokenIterator skip empty tokens?
3. What's the contract for token text?

### 3. Configuration Loading Issues

**Test Affected:**
- `format.test.config_test.test.format config loading from zz.zon`

**Problem:**
```zig
try testing.expect(options.trailing_comma == true);
```
The trailing_comma option is not being loaded correctly from ZON config.

**Investigation Needed:**
1. Is the ZON parsing working correctly?
2. Is the field mapping correct in the config loader?
3. Are there type conversion issues?

**Debug Steps:**
1. Add debug prints to see what's being parsed
2. Check the ZON analyzer for field extraction
3. Verify the options struct mapping

### 4. ZON-Specific Issues

#### ZON Keywords Test
**Test Affected:**
- `lib.languages.zon.test.test.ZON lexer - keywords`

**Problem:**
Test expects 4 keywords from "true false null undefined" but only finds 1.

**Analysis:**
- "true"/"false" → `TokenKind.boolean_literal`
- "null" → `TokenKind.null_literal`  
- "undefined" → `TokenKind.keyword`

**Decision Needed:**
Should boolean/null literals be categorized as keywords in ZON? This is a semantic question about token categorization.

#### ZON Dependency Extraction
**Test Affected:**
- `lib.languages.zon.test.test.ZON analyzer - dependency extraction`

**Problem:**
```zig
try testing.expect(schema.dependencies.items.len >= 1);
```
Dependencies are not being extracted from the ZON content.

**Investigation Needed:**
1. What ZON content is being tested?
2. Is the dependency extraction logic working?
3. Are we looking for the right patterns?

## Priority & Approach

### High Priority
1. **EOF Token Issues** - This affects multiple tests and core functionality
2. **Configuration Loading** - Important for user-facing features

### Medium Priority  
3. **ZON Dependency Extraction** - Affects deps module functionality
4. **TokenIterator Validation** - May be related to EOF token issue

### Low Priority
5. **ZON Keywords** - Semantic categorization question, may just need test update

## Next Steps

1. **Investigate EOF token behavior** across the codebase
2. **Debug configuration loading** with detailed logging
3. **Review ZON analyzer** implementation
4. **Consider test expectations** vs. actual behavior - some tests may need updating rather than code fixes

## Notes

These issues were discovered after enabling previously disabled tests. Some may represent intentional design decisions that need test updates rather than code fixes.