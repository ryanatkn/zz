# Lexer Module - Unified Lexer Infrastructure

## Purpose
Common lexer infrastructure for all language implementations. Provides unified interface for streaming and batch tokenization.

## Architecture
- **Pure Infrastructure** - No language implementations here
- **Streaming First** - Zero-allocation token streaming
- **Optional Incremental** - Editor support when needed
- **Token-Centric** - Tokens are the fundamental IR

## Files
- `mod.zig` - Pure re-exports only
- `interface.zig` - Unified LexerInterface all languages implement
- `streaming.zig` - TokenStream for zero-allocation streaming
- `incremental.zig` - Edit/TokenDelta for incremental updates
- `buffer.zig` - Buffer management for streaming
- `context.zig` - Lexer context and error handling

## Usage
```zig
// Language implementations create a LexerInterface
const lexer = JsonLexer.init(allocator);
const interface = createInterface(&lexer);

// Stream tokens (zero allocation)
var stream = interface.streamTokens(source);
while (stream.next()) |token| {
    // Process token
}

// Or batch tokenize (allocates array)
const tokens = try interface.batchTokenize(allocator, source);
defer allocator.free(tokens);
```

## Design Principles
- Tokens are always required (fundamental IR)
- Streaming is the default (batch is convenience)
- Incremental updates are optional
- No language-specific code in this module