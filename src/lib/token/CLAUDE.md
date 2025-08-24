# Token Module - Lightweight Token Representation

## Overview
Unified token system with tagged union dispatch achieving 1-2 cycle performance (vs 3-5 for vtable). Core of the stream-first lexer architecture.

## Core Types

### Token (24 bytes)
Tagged union for zero-overhead dispatch:
```zig
pub const Token = union(enum) {
    json: JsonToken,     // 16 bytes
    zon: ZonToken,       // 16 bytes
    typescript: TsToken, // 16 bytes (future)
    // ... other languages
};
```

### Language Tokens (16 bytes each)
Compact representation per language:
```zig
pub const JsonToken = struct {
    span: Span,          // 8 bytes
    kind: TokenKind,     // 1 byte
    depth: u8,           // 1 byte
    flags: TokenFlags,   // 1 byte
    _padding: [5]u8,     // 5 bytes
};
```

### TokenKind
Unified categories across languages:
- **Structural**: brace_open, bracket_open, paren_open
- **Values**: string, number, boolean, null
- **Operators**: comma, colon, semicolon
- **Identifiers**: identifier, keyword

## Performance
- **Dispatch**: 1-2 cycles (tagged union)
- **Size**: 16 bytes per language token
- **Token**: 24 bytes with tag
- **Comparison**: 3-5 cycles saved vs vtable

## Generic Composition
```zig
// Create custom token types
pub fn SimpleToken(comptime T: type) type {
    return struct {
        token: T,
        metadata: TokenMetadata,
    };
}
```

## Usage
```zig
// Pattern matching on token type
switch (token) {
    .json => |json_token| processJson(json_token),
    .zon => |zon_token| processZon(zon_token),
    // ...
}

// Direct field access
const span = switch (token) {
    inline else => |t| t.span,
};
```

## Fact Extraction
Tokens can generate facts:
```zig
pub fn extractFacts(token: Token, store: *FactStore) !void {
    const fact = Fact{
        .subject = packSpan(token.getSpan()),
        .predicate = .is_token,
        .object = .{ .atom = token.getKind() },
    };
    try store.append(fact);
}
```

## Integration
- Produced by LexerBridge (temporary)
- Will be directly produced by stream lexers (Phase 4)
- Consumed by parsers and fact extractors
- Streamable via TokenStream