# Parser Module - Optional Parsing Infrastructure

## Purpose
Optional parser layer that consumes tokens to produce AST. Not all operations need parsing - many work directly on tokens.

## Architecture
- **Token Consumer** - Parsers consume tokens from lexers
- **Optional Layer** - Only invoked when AST is needed
- **Boundary Detection** - Fast structural analysis without full parse
- **Incremental Support** - Updates for editor scenarios

## Files
- `mod.zig` - Pure re-exports only
- `interface.zig` - ParserInterface all parsers implement
- `recursive.zig` - Recursive descent infrastructure
- `structural.zig` - Boundary detection algorithms
- `recovery.zig` - Error recovery strategies
- `viewport.zig` - Viewport optimization for editors
- `cache.zig` - Boundary caching system
- `context.zig` - Parse context and error tracking

## Usage
```zig
// Tokens are required input
const tokens = try lexer.batchTokenize(allocator, source);

// Parser consumes tokens to produce AST (optional)
const parser = JsonParser.init(allocator);
const ast = try parser.parseAST(tokens);

// Or just detect boundaries (faster)
const boundaries = try parser.detectBoundaries(tokens);
```

## Design Principles
- Parser is optional (not all operations need AST)
- Consumes tokens (never operates on raw text)
- Boundary detection for fast structural analysis
- Incremental updates preserve unaffected AST nodes