# Unicode Module - Unicode Processing and Validation

Centralized Unicode validation, classification, and escape handling following RFC 3629 (UTF-8), RFC 2781 (UTF-16), RFC 5198 (Network Unicode), RFC 8259 (JSON), and RFC 9839 (Unicode Character Repertoire Subsets).

## Overview

The Unicode module provides reusable Unicode functionality for all language implementations in zz, ensuring consistent behavior and compliance across parsers and formatters. It implements strict validation according to RFC 9839 for problematic Unicode code points.

## Module Structure

```
src/lib/unicode/
├── mod.zig        # Module exports and core types
├── validation.zig # Unicode validation (RFC 9839)
├── codepoint.zig  # Code point classification
├── escape.zig     # Escape sequence parsing/formatting
├── utf8.zig       # UTF-8 encoding/decoding
├── test/          # Test suite
│   ├── mod.zig           # Test aggregator
│   ├── integration.zig   # End-to-end tests  
│   ├── security.zig      # Security/attack tests
│   └── rfc_compliance.zig # RFC edge cases
└── CLAUDE.md      # This documentation
```

## Core Features

### Validation Modes

The module supports three validation modes for Unicode content:

```zig
pub const UnicodeMode = enum {
    strict,     // Reject problematic code points (default)
    sanitize,   // Replace problematic with U+FFFD
    permissive, // Allow everything, validate on output
};
```

**Strict Mode (Default):**
- Rejects control characters (except tab, newline)
- Rejects carriage return (enforces Unix line endings)
- Rejects BOM at string start (per RFC 5198)
- Rejects surrogates (U+D800-U+DFFF)
- Rejects noncharacters (U+FDD0-U+FDEF, last 2 of each plane)

**Sanitize Mode:**
- Same detection as strict mode
- Replaces problematic code points with U+FFFD (Replacement Character)
- Allows carriage return (doesn't enforce Unix line endings)

**Permissive Mode:**
- No validation during parsing
- Only checks for valid UTF-8 encoding
- Escapes problematic code points on serialization

### Code Point Classification

Based on RFC 9839, code points are classified as:

- **Control Characters:** C0 (U+0000-U+001F), C1 (U+0080-U+009F), DEL (U+007F)
- **Useful Controls:** Tab (U+0009), Newline (U+000A)
- **Carriage Return:** U+000D (separate classification for Unix line ending enforcement)
- **Surrogates:** U+D800-U+DFFF (invalid in UTF-8)
- **Noncharacters:** U+FDD0-U+FDEF and last two code points of each plane

### Escape Sequence Support

The module handles various escape sequence formats:

```zig
pub const Format = enum {
    json_style,     // \uXXXX (4 hex digits, surrogate pairs for supplementary)
    zon_style,      // \xXX (2 hex) or \u{XXXX} (variable with braces)
    c_style,        // \xXX (2 hex digits only)
    rust_style,     // \u{X} to \u{XXXXXX} (variable with braces)
    python_style,   // \xXX, \uXXXX, or \UXXXXXXXX
};
```

## Usage Examples

### Basic Validation

```zig
const unicode = @import("lib/unicode/mod.zig");

// Validate a string
const result = unicode.validateString("Hello\x00World", .strict);
if (!result.valid) {
    std.debug.print("Invalid at position {}: {s}\n", .{
        result.position.?,
        result.message.?,
    });
}

// Quick byte validation
if (unicode.validateByte(0x00, .strict)) |error_code| {
    std.debug.print("Invalid: {s}\n", .{error_code.getMessage()});
}
```

### Escape Sequence Parsing

```zig
// Parse Unicode escape sequences
const escape_result = unicode.parseUnicodeEscape("u0041"); // \u0041
if (escape_result.valid) {
    std.debug.print("Code point: U+{X:0>4}\n", .{escape_result.code_point.?});
}

// Distinguish between incomplete and invalid
const incomplete = unicode.parseUnicodeEscape("u00"); // Missing digits
const invalid = unicode.parseUnicodeEscape("uGGGG"); // Invalid hex
```

### Code Point Classification

```zig
const codepoint = @import("lib/unicode/codepoint.zig");

const class = codepoint.classifyCodePoint(0xD800);
switch (class) {
    .surrogate => std.debug.print("Surrogate - invalid in UTF-8\n", .{}),
    .control_character => std.debug.print("Control character\n", .{}),
    .noncharacter => std.debug.print("Noncharacter\n", .{}),
    .valid => std.debug.print("Valid for interchange\n", .{}),
    else => {},
}
```

### UTF-8 Handling

```zig
const utf8 = @import("lib/unicode/utf8.zig");

// Validate UTF-8
const validation = utf8.validateUtf8("Hello, 世界!");
if (!validation.valid) {
    std.debug.print("Invalid UTF-8 at position {}\n", .{validation.position.?});
}

// Decode code points
const decode_result = utf8.decodeCodePoint("😀");
if (decode_result.valid) {
    std.debug.print("Code point: U+{X:0>4}\n", .{decode_result.code_point.?});
    std.debug.print("Bytes consumed: {}\n", .{decode_result.bytes_consumed});
}
```

### String Sanitization

```zig
// Replace problematic characters with U+FFFD
const sanitized = try unicode.validation.sanitizeString(
    allocator,
    "Hello\x00World\x08Test"
);
defer allocator.free(sanitized);
// Result: "Hello�World�Test" (� = U+FFFD)
```

### Escape Formatting

```zig
// Format code points as escape sequences
const json_escape = try unicode.formatEscape(allocator, 0x1F600, .json_style);
defer allocator.free(json_escape);
// Result: "\uD83D\uDE00" (surrogate pair)

const rust_escape = try unicode.formatEscape(allocator, 0x1F600, .rust_style);
defer allocator.free(rust_escape);
// Result: "\u{1f600}"
```

## Performance Characteristics

- **Byte validation:** O(1) constant time lookup
- **String validation:** O(n) single pass
- **UTF-8 decoding:** O(1) per code point
- **Escape parsing:** O(k) where k is escape length
- **Classification:** O(1) range checks

## Error Handling

The module provides detailed error information:

```zig
pub const ErrorCode = enum {
    control_character_in_string,
    carriage_return_in_string,
    surrogate_in_string,
    noncharacter_in_string,
    invalid_escape_sequence,
    incomplete_unicode_escape,
    invalid_unicode_escape,
    invalid_utf8_sequence,
    incomplete_utf8_sequence,
    overlong_utf8_sequence,
};
```

Each error code has a human-readable message accessible via `getMessage()`.

## RFC Compliance

### RFC 9839 - Unicode Character Repertoire Subsets
- Identifies problematic code points for data interchange
- Implements recommended validation for control characters
- Provides options for handling noncharacters and surrogates

### RFC 8259 - JSON Data Interchange Format
- Validates escape sequences according to JSON specification
- Handles surrogate pairs for supplementary plane characters
- Enforces valid Unicode in string literals

## Testing

The module includes comprehensive tests for:
- Control character detection (C0, C1, DEL)
- Surrogate validation (U+D800-U+DFFF)
- Noncharacter detection
- Escape sequence parsing (complete vs incomplete vs invalid)
- UTF-8 validation and decoding
- Mode comparison (strict vs sanitize vs permissive)
- Unix line ending enforcement

Run tests with:
```bash
zig build test -Dtest-filter="src/lib/unicode"
```

## RFC Compliance

The Unicode module follows established RFCs for standards-compliant Unicode handling:

### RFC 3629 - UTF-8 Encoding ✅
- **Full Compliance:** Proper UTF-8 validation with security checks
- **Security:** Rejects invalid start bytes (C0, C1, F5-FF) that could enable attacks
- **Overlong Protection:** Detects and rejects overlong encodings
- **Range Validation:** Enforces valid Unicode range (U+0000-U+10FFFF)
- **Surrogate Rejection:** Properly rejects surrogates in UTF-8 (invalid per spec)

### RFC 2781 - UTF-16 Surrogate Pairs ✅
- **JSON Escape Support:** Generates surrogate pairs for supplementary plane characters
- **Proper Encoding:** Converts U+1F600 → `\uD83D\uDE00` for JSON compatibility
- **Security:** Treats unpaired surrogates as invalid

### RFC 5198 - Network Unicode (Partial) ⚠️
Net-Unicode defines text interchange for protocols. Our implementation:
- ✅ **UTF-8 Encoding:** Uses UTF-8 as required
- ✅ **C1 Control Rejection:** Rejects C1 controls (U+0080-U+009F) 
- ✅ **No BOM:** Rejects BOM per RFC recommendation
- ⚠️ **Line Endings:** Enforces Unix (LF) instead of CRLF (stricter than RFC)
- ❌ **NFC Normalization:** Not implemented (would require Unicode tables)

*Note: Our Unix-only line ending policy is stricter than RFC 5198's CRLF requirement, which is appropriate for a POSIX-focused tool.*

### RFC 9839 - Unicode Character Subsets ✅
Implements detection of "problematic code points":
- ✅ **Surrogates:** U+D800-U+DFFF (invalid in UTF-8)
- ✅ **Control Characters:** C0 (U+0000-U+001F), C1 (U+0080-U+009F), DEL (U+007F)
- ✅ **Useful Controls:** Allows tab (U+0009), newline (U+000A) 
- ✅ **Carriage Return:** Special handling for Unix line ending enforcement
- ✅ **Noncharacters:** U+FDD0-U+FDEF and plane endings (U+FFFE, U+FFFF, etc.)

*Note: We implement the spirit of RFC 9839 through validation modes rather than formal subsets.*

## Security Considerations

Following RFC security recommendations:

1. **Overlong Sequence Protection** (RFC 3629): Prevents security bypasses through alternate encodings
2. **Invalid Start Byte Rejection**: Blocks malformed sequences that could cause parser confusion
3. **Surrogate Validation**: Prevents UTF-16 surrogates in UTF-8 context
4. **Control Character Filtering**: Reduces attack surface from problematic control codes
5. **Replacement Character Usage**: Uses U+FFFD for sanitization per Unicode recommendations

## Implementation Notes

- **RFC 9839 Formal Subsets:** Not currently implemented (Unicode Scalars, XML Characters, Unicode Assignables). May add support in the future.
- **No NFC Normalization:** Would require large Unicode tables; can be added later if needed
- **BOM Policy:** Reject UTF-8 BOM per RFC 5198 and modern best practices
- **Unix Line Endings:** Stricter than RFC 5198 but appropriate for POSIX systems

## Future Enhancements

1. **Normalization:** Unicode normalization forms (NFC, NFD, NFKC, NFKD) if needed
2. **Grapheme Clusters:** Proper handling of combining characters
3. **Bidirectional Text:** Support for RTL/LTR text handling
4. **Case Folding:** Unicode-aware case conversion
5. **Script Detection:** Identify writing systems in text

The Unicode module provides RFC-compliant Unicode handling across all of zz's language implementations, prioritizing security and interoperability while maintaining simplicity.