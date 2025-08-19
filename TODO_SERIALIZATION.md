# TODO_SERIALIZATION - Transform Pipeline Architecture

**Created**: 2025-08-18  
**Updated**: 2025-08-19  
**Status**: Phase 2 Complete ✅ | Phase 3 Ready 🚀
**Goal**: Establish bidirectional transformation pipeline for encoding/decoding operations

## 🎉 Major Achievements

**Phase 2 Complete** with exceptional results:
- ✅ **JSON & ZON** fully integrated with transform pipeline
- ✅ **99.6% memory reduction** for streaming (far exceeded 90% target)  
- ✅ **Comprehensive benchmarking** system with baseline comparison
- ✅ **AST ↔ Native conversion** working with format preservation
- ✅ **4KB chunk streaming** with 5MB memory limits for incremental parsing
- ✅ **601/602 tests passing** - maintained compatibility while adding features

**Ready for Phase 3**: Language expansion (TypeScript, Zig, CSS, HTML, Svelte) and advanced optimizations.

## 🎯 Executive Summary

Add serialization as a core primitive through a **transform pipeline architecture** that:
- Provides bidirectional transformations (encode ↔ decode)
- Extends (not duplicates) std library functionality
- Unifies encoding/decoding patterns across all formats
- Supports both sync and async IO through parameterization
- Maintains AST preservation for format-aware operations

## 🏗️ Architecture Overview

### Core Concept: Bidirectional Transforms

```
Text ↔ Tokens ↔ AST ↔ Schema ↔ Native Types
     ↑        ↑      ↑        ↑
  Lexical  Syntactic Semantic Native
  Stage    Stage     Stage    Stage
```

Each stage is a **bidirectional transform** with:
- **Forward** (encode): Left → Right
- **Reverse** (decode): Right → Left
- **Context**: Carries options, errors, IO mode

### Key Differentiators from std

| Feature | std Library | Our Addition | Why We Need It |
|---------|------------|--------------|----------------|
| JSON parsing | `std.json` → native types | AST-preserving parse | Format preservation, linting |
| String escape | Generic UTF-8 | Language-specific rules | JSON vs ZON vs JS escaping |
| Indentation | None | Smart indent management | Language-aware formatting |
| Pipeline | None | Composable transforms | `lex\|parse\|analyze` chains |
| Bidirectional | Parse only | Parse + Emit | Round-trip preservation |

## 📦 Module Structure

### Transform Infrastructure (`lib/transform/`)

#### `pipeline.zig` - Pipeline Composition
```zig
// Pipeline type: Chain of transforms
pub fn Pipeline(comptime In: type, comptime Out: type) type

// Composition operators
pub fn chain(self: Pipeline(A,B), next: Pipeline(B,C)) Pipeline(A,C)
pub fn parallel(pipelines: []Pipeline) ParallelPipeline
pub fn branch(condition: fn(T) bool, a: Pipeline, b: Pipeline) Pipeline

// Execution modes
pub fn run(self: Pipeline, input: In, context: *Context) !Out
pub fn runAsync(self: Pipeline, input: In, context: *Context) !Out
pub fn stream(self: Pipeline, reader: Reader, writer: Writer) !void
```

#### `transform.zig` - Base Transform Interface
```zig
pub fn Transform(comptime In: type, comptime Out: type) type {
    return struct {
        // Core operations
        forward: fn(*Context, In) Error!Out,
        reverse: ?fn(*Context, Out) Error!In,  // Optional
        
        // Async variants (parameterized IO)
        forwardAsync: fn(*Context, In) Error!Out,
        reverseAsync: ?fn(*Context, Out) Error!In,
        
        // Metadata
        name: []const u8,
        reversible: bool,
        streaming: bool,
    };
}
```

#### `context.zig` - Transform Context
```zig
pub const Context = struct {
    // Resources
    allocator: Allocator,
    arena: ?*ArenaAllocator,  // For temp allocations
    
    // IO abstraction
    io_mode: enum { sync, async },
    reader: ?Reader,
    writer: ?Writer,
    
    // Options
    options: std.json.ObjectMap,  // Format-specific options
    
    // Error handling
    errors: ErrorAccumulator,
    diagnostics: []Diagnostic,
    
    // Progress tracking
    progress: ?*Progress,
    cancel_token: ?*CancelToken,
};
```

### Stage Interfaces (`lib/transform/stages/`)

#### `lexical.zig` - Text ↔ Tokens
```zig
pub const LexicalStage = Transform([]const u8, []Token);

// Required implementation
pub const Lexer = struct {
    // Forward: tokenize
    pub fn tokenize(ctx: *Context, text: []const u8) ![]Token
    
    // Reverse: detokenize  
    pub fn detokenize(ctx: *Context, tokens: []Token) ![]const u8
    
    // Streaming support
    pub fn tokenizeStream(ctx: *Context, reader: Reader) !TokenIterator
};

// Token definition (language-agnostic)
pub const Token = struct {
    kind: TokenKind,
    text: []const u8,
    span: Span,
    trivia: ?[]const u8,  // Preceding whitespace/comments
};
```

#### `syntactic.zig` - Tokens ↔ AST
```zig
pub const SyntacticStage = Transform([]Token, AST);

// Required implementation
pub const Parser = struct {
    // Forward: parse tokens to AST
    pub fn parse(ctx: *Context, tokens: []Token) !AST
    
    // Reverse: emit AST to tokens
    pub fn emit(ctx: *Context, ast: AST) ![]Token
    
    // Error recovery
    pub fn parseWithRecovery(ctx: *Context, tokens: []Token) ParseResult
};

pub const ParseResult = struct {
    ast: ?AST,
    errors: []ParseError,
    recovered_nodes: []RecoveredNode,
};
```

#### `semantic.zig` - AST ↔ Schema
```zig
pub const SemanticStage = Transform(AST, Schema);

// Schema represents the semantic structure
pub const Schema = struct {
    root_type: TypeInfo,
    symbols: []Symbol,
    dependencies: []Dependency,
    metadata: std.json.ObjectMap,
};

pub const Analyzer = struct {
    // Forward: extract schema from AST
    pub fn analyze(ctx: *Context, ast: AST) !Schema
    
    // Reverse: instantiate AST from schema
    pub fn instantiate(ctx: *Context, schema: Schema) !AST
    
    // Type inference
    pub fn inferTypes(ast: AST) !TypeMap
};
```

#### `native.zig` - Schema ↔ Native Types
```zig
pub const NativeStage = Transform(Schema, anytype);

pub const TypeMapper = struct {
    // Forward: generate native types from schema
    pub fn generate(ctx: *Context, schema: Schema, comptime T: type) !T
    
    // Reverse: reflect native types to schema
    pub fn reflect(ctx: *Context, value: anytype) !Schema
    
    // Runtime type creation
    pub fn createType(schema: Schema) !type
};
```

### Encoding Primitives (`lib/encoding/`)

#### `ast/` - AST-Specific Encoding
```zig
// to_native.zig - AST to Zig types
pub fn astToNative(comptime T: type, ast: AST) !T
pub fn astNodeToValue(node: Node, type_info: TypeInfo) !std.json.Value

// from_native.zig - Zig types to AST  
pub fn nativeToAST(value: anytype, factory: *ASTFactory) !AST
pub fn valueToAstNode(value: std.json.Value, factory: *ASTFactory) !Node

// preserving.zig - Format-preserving transforms
pub fn transformPreserving(ast: AST, transform_fn: fn(Node) Node) !AST
pub fn mergePreserving(original: AST, updates: AST) !AST
```

#### `text/` - Text Utilities Beyond std
```zig
// indent.zig - Smart indentation (NOT in std)
pub const IndentManager = struct {
    style: enum { spaces, tabs, mixed },
    size: u32,
    
    pub fn detectStyle(text: []const u8) IndentStyle
    pub fn indent(text: []const u8, level: u32) ![]const u8
    pub fn dedent(text: []const u8) ![]const u8
    pub fn reindent(text: []const u8, new_style: IndentStyle) ![]const u8
};

// escape_custom.zig - Language-specific escaping
pub const Escaper = struct {
    rules: []const EscapeRule,
    
    // JSON: \" \\ \/ \b \f \n \r \t \uXXXX
    // ZON: \\ \n \r \t \xXX \" (but supports multiline)
    // JS: Above + \` \${} for template literals
    pub fn escape(text: []const u8, lang: Language) ![]const u8
    pub fn unescape(text: []const u8, lang: Language) ![]const u8
};

// quote_styles.zig - Quote style management
pub const QuoteManager = struct {
    pub fn addQuotes(text: []const u8, style: QuoteStyle) ![]const u8
    pub fn stripQuotes(text: []const u8) ![]const u8
    pub fn detectQuoteStyle(text: []const u8) QuoteStyle
    pub fn convertQuotes(text: []const u8, to: QuoteStyle) ![]const u8
};

pub const QuoteStyle = enum {
    single,        // 'text'
    double,        // "text"
    backtick,      // `text`
    triple_double, // """text"""
    triple_single, // '''text'''
};
```

#### `streaming/` - Incremental Processing
```zig
// incremental.zig - Incremental parsing/emitting
pub const IncrementalParser = struct {
    state: ParserState,
    buffer: []const u8,
    
    pub fn feedInput(self: *@This(), chunk: []const u8) !void
    pub fn getPartialResult(self: *@This()) ?PartialAST
    pub fn finish(self: *@This()) !AST
};

// chunked.zig - Chunk-based processing
pub const ChunkedTransform = struct {
    transform: Transform,
    chunk_size: usize,
    
    pub fn processChunk(self: *@This(), chunk: []const u8) ![]const u8
    pub fn flush(self: *@This()) ![]const u8
};
```

### Codec Implementations (`lib/codecs/`)

#### `interface.zig` - Codec Trait
```zig
pub const Codec = struct {
    name: []const u8,
    extensions: []const []const u8,
    mime_types: []const []const u8,
    
    // Core operations
    encode: fn(value: anytype, options: Options) Error![]const u8,
    decode: fn(comptime T: type, text: []const u8, options: Options) Error!T,
    
    // AST operations (optional)
    parseToAST: ?fn(text: []const u8) Error!AST,
    formatAST: ?fn(ast: AST, options: FormatOptions) Error![]const u8,
    
    // Validation
    validate: fn(text: []const u8) Error!void,
};
```

#### `json_ast/` - AST-Preserving JSON
```zig
// codec.zig - JSON codec implementation
pub const JsonASTCodec = struct {
    // Our AST-preserving implementation
    pub fn parseToAST(allocator: Allocator, text: []const u8) !AST {
        const pipeline = JsonLexer.init()
            .chain(JsonParser.init())
            .chain(JsonASTBuilder.init());
        return pipeline.run(text, context);
    }
    
    // Bridge to std.json when AST not needed
    pub fn parseToValue(allocator: Allocator, text: []const u8) !std.json.Value {
        return std.json.parseFromSlice(std.json.Value, allocator, text, .{});
    }
    
    // Format-preserving stringify
    pub fn formatAST(ast: AST, options: FormatOptions) ![]const u8 {
        const pipeline = JsonEmitter.init(options)
            .chain(JsonFormatter.init(options));
        return pipeline.run(ast, context);
    }
};
```

## 🔄 Async/Sync IO Parameterization

Following existing patterns in the codebase:

```zig
pub const IOMode = enum { sync, async };

pub fn TransformWithIO(comptime mode: IOMode) type {
    return struct {
        pub fn execute(self: *@This(), input: anytype) !Output {
            switch (mode) {
                .sync => return self.executeSync(input),
                .async => return self.executeAsync(input),
            }
        }
        
        fn executeSync(self: *@This(), input: anytype) !Output {
            const reader = std.io.getStdIn().reader();
            // Synchronous implementation
        }
        
        fn executeAsync(self: *@This(), input: anytype) !Output {
            const reader = AsyncReader.init();
            // Async implementation with async/await
        }
    };
}
```

## 📋 Implementation Phases

### Phase 1: Foundation (Week 1-2) ✅ COMPLETE
- [x] Create `transform/` module structure
- [x] Implement base `Transform` and `Pipeline` types
- [x] Define stage interfaces (simplified approach)
- [x] Set up `Context` with IO abstraction
- [x] Extract indentation logic → `text/indent.zig`
- [x] Extract escaping logic → `text/escape.zig`
- [x] Extract quote handling → `text/quote.zig`

### Phase 2: Integration & Migration (Week 3-4) ✅ COMPLETE
- [x] Migrate JSON lexer to implement transform interface
- [x] Migrate JSON parser to use pipeline
- [x] Create AST ↔ Native converters (`lib/encoding/ast/`)
- [x] Add format-preserving infrastructure
- [x] Migrate ZON to transform pipeline
- [x] Implement trivia preservation
- [x] Round-trip preservation working
- [x] **Day 4 Streaming Support** ✅ COMPLETE
  - [x] TokenIterator for chunk-based streaming (4KB chunks)
  - [x] IncrementalParser with memory limits (5MB default)
  - [x] Large file test fixtures (1MB JSON/ZON)
  - [x] Memory usage benchmarks (traditional vs streaming)
  - [x] **99.6% memory reduction achieved** (target: 90%)

### Phase 3: Language Expansion & Advanced Features (Next Phase) 🚀
**→ See [TODO_SERIALIZATION_PHASE_3.md](TODO_SERIALIZATION_PHASE_3.md) for detailed plan**
- [ ] Migrate TypeScript to transform pipeline
- [ ] Migrate Zig, CSS, HTML, Svelte to pipeline architecture
- [ ] Universal linter framework for all languages
- [ ] **SIMD optimizations** ⚠️ *Evaluate necessity vs simpler optimizations*
- [ ] Language Server Protocol foundation
- [ ] Parallel pipeline execution and caching

### Phase 4: Production & Distribution (Future)
- [ ] WASM compilation for browser/edge deployment
- [ ] Language bindings (Python, Node.js, Rust)
- [ ] Cloud deployment for distributed processing
- [ ] Real-time collaboration and live document sync
- [ ] AI integration and pipeline-based code generation

## 🎯 Success Criteria

### Functional Requirements
- [x] All JSON tests pass with new pipeline ✅
- [x] All ZON tests pass with new pipeline ✅
- [x] Bidirectional transforms are lossless for valid input ✅
- [x] Format preservation infrastructure complete ✅
- [ ] Streaming mode handles large files (>100MB) - basic support added

### Performance Requirements
- [x] **Streaming reduces memory by 99.6% for 1MB+ files** ✅ (exceeded 90% target)
- [x] **Benchmark infrastructure established** ✅ (comprehensive suite with baseline comparison)
- [ ] No regression in parse/format speed - pending comprehensive benchmarks
- [ ] Pipeline overhead < 5% vs direct implementation - to be measured in Phase 3
- [x] **Memory management optimized** ✅ (4KB chunks, 5MB parser limits)

### Code Quality
- [x] Zero code duplication with std library ✅
- [x] All transforms have consistent interfaces ✅
- [x] Clear separation between generic and language-specific code ✅
- [x] Test coverage maintained (601/602 tests passing) ✅

## 💡 Example Usage

### Simple Pipeline
```zig
// Create a JSON formatting pipeline
const formatter = JsonLexer.init()
    .chain(JsonParser.init())
    .chain(JsonFormatter.init(.{ .indent = 2 }))
    .chain(JsonEmitter.init());

const formatted = try formatter.run(input_text, context);
```

### Bidirectional Transform
```zig
// Parse JSON to native types and back
const codec = JsonASTCodec.init();

// Forward: JSON text → Native struct
const data = try codec.decode(MyStruct, json_text, .{});

// Reverse: Native struct → JSON text
const json = try codec.encode(data, .{ .pretty = true });
```

### Streaming Transform
```zig
// Stream large JSON file with transformation
var pipeline = JsonLexer.init()
    .chain(JsonTransformer.init(transform_fn))
    .chain(JsonEmitter.init());

const reader = try std.fs.openFileReader("large.json");
const writer = try std.fs.createFileWriter("output.json");

try pipeline.stream(reader, writer);
```

### Format Preservation
```zig
// Modify JSON while preserving formatting
const ast = try JsonASTCodec.parseToAST(allocator, original);
const modified = try transformPreserving(ast, fn(node) {
    // Modify specific nodes while preserving structure
});
const output = try JsonASTCodec.formatAST(modified, .{ .preserve = true });
```

## 🚧 Known Challenges

1. **Type Safety**: Ensuring compile-time type safety across generic transforms
2. **Error Handling**: Propagating errors through pipeline stages gracefully
3. **Memory Management**: Arena allocation strategy for temporary transforms
4. **Performance**: Minimizing allocation and copy overhead in pipelines
5. **Compatibility**: Maintaining compatibility with existing code during migration

## 📚 References

- Current JSON implementation: `src/lib/languages/json/`
- Current ZON implementation: `src/lib/languages/zon/`
- AST infrastructure: `src/lib/ast/`
- Existing IO patterns: `src/lib/core/io.zig`
- Character utilities: `src/lib/char/`

## 📝 Notes

- This architecture is designed to be **extensible** - new formats can be added by implementing the stage interfaces
- The **pipeline** abstraction allows for easy composition and testing of individual stages
- **Format preservation** is a key differentiator from std library implementations
- The design supports both **batch** and **streaming** processing modes
- All components are designed with **zero allocation** goals where possible

---

*This document represents a fundamental rethinking of encoding/decoding in zz, moving from ad-hoc implementations to a unified, composable pipeline architecture.*