# TODO_STREAMING_LEXER_PHASE_2.md - Language-Specific Tokens & TypeScript/Zig Implementation

## Phase 2: Language-Specific Token System & Core Language Support (Days 3-5)

### Overview
Build on Phase 1's foundation to implement language-specific token types, complete TypeScript and Zig stateful lexers, and establish the token transformation pipeline for rich semantic information.

### Prerequisites (Phase 1 ✅ Complete)
- Stateful lexer infrastructure with all contexts
- JSON reference implementation working
- Streaming adapters architecture established
- Character utilities integrated

### Goals
- **Rich Token Types**: Language-specific tokens with full semantic information
- **TypeScript Lexer**: Complete with JSX, templates, regex support
- **Zig Lexer**: Complete with comptime, raw strings, doc comments
- **Token Transformation**: Pipeline from language tokens to generic tokens
- **Performance**: Maintain <50ns per token, <5% streaming overhead

## Implementation Tasks

### Task 1: Language-Specific Token System (2 hours)

#### 1.1 Create Token Type Definitions
```zig
// src/lib/languages/json/tokens.zig
pub const JsonToken = union(enum) {
    object_start: TokenData,
    object_end: TokenData,
    array_start: TokenData,
    array_end: TokenData,
    property_name: struct {
        data: TokenData,
        value: []const u8,
    },
    string_value: struct {
        data: TokenData,
        value: []const u8,
        has_escapes: bool,
    },
    number_value: struct {
        data: TokenData,
        is_float: bool,
        is_scientific: bool,
    },
    boolean_value: struct {
        data: TokenData,
        value: bool,
    },
    null_value: TokenData,
    comma: TokenData,
    colon: TokenData,
};

// src/lib/languages/typescript/tokens.zig
pub const TypeScriptToken = union(enum) {
    keyword: struct {
        data: TokenData,
        kind: KeywordKind,
    },
    identifier: struct {
        data: TokenData,
        text: []const u8,
    },
    template_literal: struct {
        data: TokenData,
        parts: []TemplatePart,
    },
    jsx_element: struct {
        data: TokenData,
        tag: []const u8,
        self_closing: bool,
    },
    // ... more TypeScript-specific tokens
};

// src/lib/languages/zig/tokens.zig
pub const ZigToken = union(enum) {
    keyword: struct {
        data: TokenData,
        kind: ZigKeyword,
    },
    builtin: struct {
        data: TokenData,
        name: []const u8,
    },
    doc_comment: struct {
        data: TokenData,
        text: []const u8,
    },
    comptime_block: struct {
        data: TokenData,
    },
    raw_string: struct {
        data: TokenData,
        content: []const u8,
    },
    // ... more Zig-specific tokens
};
```

#### 1.2 Token Conversion Layer
```zig
// src/lib/transform/streaming/token_converter.zig
pub fn convertToGenericToken(comptime T: type, token: T) Token {
    return switch (@TypeOf(token)) {
        JsonToken => convertJsonToken(token),
        TypeScriptToken => convertTypeScriptToken(token),
        ZigToken => convertZigToken(token),
        else => @compileError("Unsupported token type"),
    };
}
```

### Task 2: TypeScript Stateful Lexer (3 hours)

#### 2.1 Core TypeScript Lexer
```zig
// src/lib/languages/typescript/stateful_lexer.zig
pub const StatefulTypeScriptLexer = struct {
    state: StatefulLexer.State,
    allocator: std.mem.Allocator,
    jsx_depth: u16 = 0,
    template_depth: u16 = 0,
    
    // TypeScript-specific contexts
    const TsContext = enum {
        normal,
        in_jsx_tag,
        in_jsx_attribute,
        in_template_literal,
        in_template_expression,
        in_regex,
        in_type_annotation,
    };
    
    pub fn processChunk(self: *Self, chunk: []const u8, chunk_pos: usize, allocator: std.mem.Allocator) ![]TypeScriptToken {
        // Handle:
        // - Template literals with ${} expressions
        // - JSX tags and attributes
        // - Regex literals with proper context detection
        // - Type annotations after :
        // - Decorators @
        // - Async/await keywords
    }
};
```

#### 2.2 JSX Support
- Detect `<` in expression context vs comparison
- Track JSX tag depth for proper nesting
- Handle self-closing tags `/>`
- Parse JSX attributes and expressions `{}`

#### 2.3 Template Literal Support
- Track template literal boundaries `` ` ``
- Parse `${}` expression interpolations
- Handle nested templates
- Preserve raw string content

### Task 3: Zig Stateful Lexer (3 hours)

#### 3.1 Core Zig Lexer
```zig
// src/lib/languages/zig/stateful_lexer.zig
pub const StatefulZigLexer = struct {
    state: StatefulLexer.State,
    allocator: std.mem.Allocator,
    
    // Zig-specific state
    const ZigContext = enum {
        normal,
        in_comptime,
        in_doc_comment,
        in_raw_string,
        in_multiline_string,
        in_builtin_call,
    };
    
    pub fn processChunk(self: *Self, chunk: []const u8, chunk_pos: usize, allocator: std.mem.Allocator) ![]ZigToken {
        // Handle:
        // - Doc comments ///
        // - Comptime blocks
        // - Raw strings r"..."
        // - Multiline strings \\
        // - Builtin functions @
        // - Error unions and optionals
    }
};
```

#### 3.2 Zig-Specific Features
- Parse builtin functions `@import`, `@TypeOf`
- Handle error union syntax `!` and `catch`
- Track comptime context
- Parse inline assembly

### Task 4: Token Pipeline Integration (2 hours)

#### 4.1 Unified Token Iterator
```zig
// src/lib/transform/streaming/unified_token_iterator.zig
pub const UnifiedTokenIterator = struct {
    pub const LexerKind = union(enum) {
        json: *StatefulJsonLexer,
        typescript: *StatefulTypeScriptLexer,
        zig: *StatefulZigLexer,
        zon: *StatefulZonLexer,
    };
    
    lexer: LexerKind,
    converter: TokenConverter,
    
    pub fn next(self: *Self) ?Token {
        // Get language-specific token
        // Convert to generic token
        // Return unified result
    }
};
```

#### 4.2 Streaming Adapter Updates
- Update JSON adapter to use JsonToken
- Create TypeScript streaming adapter
- Create Zig streaming adapter
- Update performance gates

### Task 5: Testing & Validation (2 hours)

#### 5.1 TypeScript Test Suite
```zig
test "TypeScript - template literals" {
    const input = "`Hello ${name}, you are ${age} years old`";
    // Verify correct tokenization across chunks
}

test "TypeScript - JSX elements" {
    const input = "<Button onClick={() => alert('Hi')}>Click</Button>";
    // Verify JSX parsing
}

test "TypeScript - complex nesting" {
    const input = "const x = <div>{`${user.name}`}</div>";
    // Verify nested constructs
}
```

#### 5.2 Zig Test Suite
```zig
test "Zig - comptime blocks" {
    const input = "comptime { var x = 42; }";
    // Verify comptime context
}

test "Zig - raw strings" {
    const input = 
        \\const regex = r"^\d+$";
    // Verify raw string parsing
}

test "Zig - builtin functions" {
    const input = "const T = @TypeOf(x);";
    // Verify builtin parsing
}
```

#### 5.3 Performance Benchmarks
- TypeScript: <100ns per token
- Zig: <75ns per token
- Memory: <100KB for 1MB input
- Chunk boundary overhead: <2%

### Task 6: Documentation (1 hour)

#### 6.1 API Documentation
- Document token type definitions
- Usage examples for each lexer
- Migration guide from batch lexers

#### 6.2 Architecture Documentation
- Token conversion pipeline
- Language-specific features
- Performance characteristics

## File Structure After Phase 2

```
src/lib/
├── languages/
│   ├── json/
│   │   ├── tokens.zig              # NEW: JSON token types
│   │   └── stateful_lexer.zig      # Enhanced with JsonToken
│   ├── typescript/
│   │   ├── tokens.zig              # NEW: TypeScript token types
│   │   ├── stateful_lexer.zig      # NEW: TypeScript stateful lexer
│   │   └── streaming_adapter.zig   # NEW: TypeScript adapter
│   ├── zig/
│   │   ├── tokens.zig              # NEW: Zig token types
│   │   ├── stateful_lexer.zig      # NEW: Zig stateful lexer
│   │   └── streaming_adapter.zig   # NEW: Zig adapter
│   └── zon/
│       ├── tokens.zig              # NEW: ZON token types
│       └── stateful_lexer.zig      # NEW: ZON stateful lexer
└── transform/streaming/
    ├── token_converter.zig          # NEW: Token conversion pipeline
    └── unified_token_iterator.zig  # NEW: Unified token iteration
```

## Success Criteria

### Functional Requirements
- [ ] TypeScript lexer handles all TS/TSX features
- [ ] Zig lexer handles all Zig language features
- [ ] Token conversion preserves all semantic information
- [ ] Chunk boundaries handled correctly for all languages
- [ ] All existing tests continue passing

### Performance Requirements
- [ ] TypeScript: <100ns per token
- [ ] Zig: <75ns per token
- [ ] Memory usage: <100KB for 1MB input
- [ ] Streaming overhead: <5%
- [ ] Zero allocations in hot paths

### Quality Requirements
- [ ] 100% test coverage for new code
- [ ] No memory leaks
- [ ] Clean API design
- [ ] Comprehensive documentation

## Risk Mitigation

### Technical Risks
1. **JSX ambiguity** - Use lookahead and context tracking
2. **Template literal nesting** - Stack-based depth tracking
3. **Performance regression** - Continuous benchmarking
4. **Memory growth** - Bounded buffers, regular cleanup

### Mitigation Strategies
- Incremental implementation with tests
- Performance gates on every commit
- Memory profiling during development
- Fuzzing for edge cases

## Dependencies
- Phase 1 completion ✅
- Char module utilities ✅
- AST infrastructure (existing) ✅

## Next Steps (Phase 3)
- CSS/HTML stateful lexers
- Svelte component support
- Markdown with code blocks
- Unified parser interface
- Semantic analysis framework

## Timeline
- **Day 3**: Token system + TypeScript lexer core
- **Day 4**: Complete TypeScript + Zig lexer core
- **Day 5**: Integration, testing, documentation

## Notes
- Prioritize correctness over performance initially
- Add optimizations after correctness verified
- Consider SIMD for character scanning
- Profile memory usage regularly

---

**Phase 2 represents the core language implementation milestone, establishing the pattern for all future language support.**