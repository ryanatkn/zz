# Primitives Evolution: Unified Language Tooling Architecture

## Executive Summary

This document outlines the evolution of zz's primitive system from a parser-centric design to a comprehensive language tooling framework. The new architecture introduces six foundational modules that work together to provide semantic understanding, powerful queries, safe transformations, real-time processing, rich diagnostics, and seamless tool integration.

## Vision

Transform zz from a collection of utilities into a **unified language tooling platform** where:
- Any language construct can be queried uniformly
- Transformations are safe, composable, and reversible
- Processing is incremental and streaming by default
- Diagnostics are rich and actionable
- Integration with editors and tools is first-class

## Core Design Principles

1. **Primitive Orthogonality**: Each primitive type serves a distinct purpose with minimal overlap
2. **Composability**: Primitives combine naturally to enable complex operations
3. **Incrementality**: All operations support incremental updates
4. **Language Agnosticism**: Core primitives work across all languages
5. **Performance First**: Zero-allocation operations where possible
6. **Type Safety**: Compile-time validation of operations

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     Application Layer                        │
│         (CLI Commands, Language Servers, Tools)              │
└────────────────────┬────────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────────┐
│                      Query Engine                            │
│         (Unified queries across all primitives)              │
└────────────────────┬────────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────────┐
│                   Primitive Layer                            │
│  ┌──────────┬──────────┬──────────┬──────────┬──────────┐  │
│  │Semantic  │  Query   │  Effect  │Streaming │Diagnostic │  │
│  │Primitives│Primitives│Primitives│Primitives│Primitives │  │
│  └──────────┴──────────┴──────────┴──────────┴──────────┘  │
└────────────────────┬────────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────────┐
│                  Foundation Layer                            │
│        (Facts, Spans, Tokens, AST, Predicates)              │
└──────────────────────────────────────────────────────────────┘
```

## Module Specifications

### 1. Semantic Module (`src/lib/semantic/`)

**Purpose**: Provide language-agnostic semantic understanding

**Core Primitives**:

```zig
pub const Symbol = struct {
    id: SymbolId,
    name: []const u8,
    kind: SymbolKind,  // function, variable, type, etc.
    scope: ScopeId,
    span: Span,
    attributes: SymbolAttributes,
};

pub const Scope = struct {
    id: ScopeId,
    parent: ?ScopeId,
    kind: ScopeKind,  // global, module, function, block
    symbols: SymbolTable,
    span: Span,
};

pub const Type = struct {
    id: TypeId,
    kind: TypeKind,  // primitive, struct, union, function, etc.
    name: ?[]const u8,
    definition: TypeDefinition,
    constraints: []TypeConstraint,
};

pub const Reference = struct {
    id: ReferenceId,
    symbol: SymbolId,
    span: Span,
    kind: ReferenceKind,  // read, write, call, type_use
    confidence: f32,
};
```

**Key Capabilities**:
- Symbol resolution across scopes
- Type inference and checking
- Reference tracking and renaming
- Cross-file symbol indexing
- Import/export analysis

### 2. Query Module (`src/lib/query/`)

**Purpose**: Unified querying across all primitive types

**Core Primitives**:

```zig
pub const Pattern = struct {
    kind: PatternKind,
    matcher: Matcher,
    bindings: []Binding,
    constraints: []Constraint,
};

pub const Selector = struct {
    path: []PathSegment,
    filters: []Filter,
    modifiers: []Modifier,  // :first, :last, :nth
};

pub const Filter = struct {
    predicate: Predicate,
    operand: Operand,
    operator: Operator,  // =, !=, <, >, contains, matches
};

pub const Projection = struct {
    fields: []Field,
    transformations: []Transform,
    aggregations: []Aggregation,
};
```

**Query Interface**:

```zig
pub const Query = struct {
    pub fn select(comptime T: type) QueryBuilder(T);
    pub fn where(field: Field, op: Operator, value: Value) *Query;
    pub fn orderBy(field: Field, direction: Direction) *Query;
    pub fn limit(n: usize) *Query;
    pub fn project(fields: []const Field) *Query;
    pub fn execute(self: *Query) !QueryResult;
};
```

**Example Queries**:
- "Find all functions > 50 lines that reference symbol X"
- "Select all TODO comments in modified files"
- "Get type definitions imported but never used"

### 3. Effect Module (`src/lib/effect/`)

**Purpose**: Safe, composable code transformations

**Core Primitives**:

```zig
pub const Effect = struct {
    id: EffectId,
    kind: EffectKind,
    target: Target,
    preconditions: []Condition,
    operations: []Operation,
    postconditions: []Condition,
};

pub const Edit = struct {
    span: Span,
    old_text: []const u8,
    new_text: []const u8,
    preserves: []Property,  // whitespace, comments, etc.
};

pub const Rename = struct {
    symbol: SymbolId,
    old_name: []const u8,
    new_name: []const u8,
    scope: RenameScope,  // local, file, project
};

pub const ChangeSet = struct {
    effects: []Effect,
    dependencies: DependencyGraph,
    conflicts: []Conflict,
    
    pub fn validate(self: *ChangeSet) ValidationResult;
    pub fn apply(self: *ChangeSet) !void;
    pub fn undo(self: *ChangeSet) !void;
};
```

**Key Features**:
- Transactional changes with rollback
- Conflict detection and resolution
- Effect composition and sequencing
- Dry-run validation
- Undo/redo history

### 4. Streaming Module (`src/lib/streaming/`)

**Purpose**: Incremental and streaming processing

**Core Primitives**:

```zig
pub const Stream = struct {
    pub fn next(self: *Stream) !?Item;
    pub fn peek(self: *Stream) ?Item;
    pub fn skip(self: *Stream, n: usize) !void;
    pub fn take(self: *Stream, n: usize) ![]Item;
    pub fn close(self: *Stream) void;
};

pub const Chunk = struct {
    id: ChunkId,
    data: []const u8,
    position: Position,
    metadata: ChunkMetadata,
};

pub const Delta = struct {
    generation: Generation,
    added: []Item,
    removed: []Item,
    modified: []Modification,
    
    pub fn merge(self: Delta, other: Delta) Delta;
    pub fn apply(self: Delta, target: *Target) !void;
};

pub const Cursor = struct {
    stream: *Stream,
    position: usize,
    mark: ?usize,
    
    pub fn advance(self: *Cursor) !void;
    pub fn rewind(self: *Cursor) !void;
    pub fn bookmark(self: *Cursor) void;
};
```

**Stream Combinators**:
```zig
pub fn map(comptime T: type, comptime U: type, 
          stream: Stream(T), f: fn(T) U) Stream(U);
pub fn filter(comptime T: type, 
             stream: Stream(T), pred: fn(T) bool) Stream(T);
pub fn merge(comptime T: type, 
            streams: []Stream(T)) Stream(T);
pub fn batch(comptime T: type, 
            stream: Stream(T), size: usize) Stream([]T);
```

### 5. Diagnostic Module (`src/lib/diagnostic/`)

**Purpose**: Rich error reporting and quick fixes

**Core Primitives**:

```zig
pub const Diagnostic = struct {
    id: DiagnosticId,
    severity: Severity,  // error, warning, info, hint
    code: DiagnosticCode,
    message: []const u8,
    span: Span,
    context: Context,
    fixes: []Fix,
    related: []RelatedInfo,
};

pub const Fix = struct {
    id: FixId,
    description: []const u8,
    edits: []Edit,
    confidence: Confidence,  // safe, probable, possible
    
    pub fn preview(self: Fix) []const u8;
    pub fn apply(self: Fix) !void;
};

pub const Context = struct {
    lines_before: []const u8,
    lines_after: []const u8,
    highlights: []Highlight,
    annotations: []Annotation,
};
```

**Diagnostic Pipeline**:
```zig
pub const DiagnosticEngine = struct {
    pub fn analyze(source: Source) ![]Diagnostic;
    pub fn suggest_fixes(diagnostic: Diagnostic) ![]Fix;
    pub fn format(diagnostic: Diagnostic, style: Style) []const u8;
    pub fn group(diagnostics: []Diagnostic) []DiagnosticGroup;
};
```

### 6. Protocol Module (`src/lib/protocol/`)

**Purpose**: Editor and tool integration

**Core Primitives**:

```zig
pub const Message = struct {
    jsonrpc: []const u8 = "2.0",
    id: ?MessageId,
    method: ?[]const u8,
    params: ?json.Value,
    result: ?json.Value,
    @"error": ?Error,
};

pub const Request = struct {
    id: MessageId,
    method: Method,
    params: Params,
    
    pub fn respond(self: Request, result: anytype) Message;
    pub fn reject(self: Request, err: Error) Message;
};

pub const Capability = struct {
    name: []const u8,
    version: Version,
    options: json.Value,
};

pub const Position = struct {
    line: u32,
    character: u32,
    
    pub fn toOffset(self: Position, doc: Document) usize;
    pub fn fromOffset(offset: usize, doc: Document) Position;
};
```

**Handler Interface**:
```zig
pub const Handler = struct {
    pub fn handle(request: Request) !Response;
    pub fn register(method: []const u8, handler: HandlerFn) void;
};
```

## Primitive Relationships

### Cross-Primitive Operations

1. **Fact → Symbol**: Facts about symbol definitions/references
2. **Symbol → Query**: Query symbols by properties
3. **Query → Effect**: Generate effects from query results
4. **Effect → Diagnostic**: Validate effects, report issues
5. **Diagnostic → Fix**: Generate fixes from diagnostics
6. **Stream → All**: Stream any primitive for incremental processing

### Unified Index

All primitives feed into a unified index:

```zig
pub const UnifiedIndex = struct {
    facts: FactIndex,
    symbols: SymbolIndex,
    types: TypeIndex,
    diagnostics: DiagnosticCache,
    
    pub fn query(self: *UnifiedIndex, q: Query) QueryResult;
    pub fn update(self: *UnifiedIndex, delta: Delta) !void;
    pub fn snapshot(self: *UnifiedIndex) Snapshot;
};
```

## Implementation Phases

### Phase 1: Foundation (Weeks 1-2)
- Add core primitive types
- Define interfaces
- Create basic module structure
- Write unit tests

### Phase 2: Semantic Layer (Weeks 3-4)
- Implement Symbol, Scope, Type primitives
- Build symbol resolution
- Add type inference basics
- Create symbol index

### Phase 3: Query Engine (Weeks 5-6)
- Implement query primitives
- Build query planner
- Add cross-primitive queries
- Optimize query execution

### Phase 4: Effects & Streaming (Weeks 7-8)
- Implement effect system
- Add streaming primitives
- Build incremental processing
- Create undo/redo

### Phase 5: Diagnostics & Protocol (Weeks 9-10)
- Implement diagnostic engine
- Add quick fixes
- Build protocol layer
- Create LSP handlers

### Phase 6: Integration (Weeks 11-12)
- Wire everything together
- Performance optimization
- Documentation
- Example applications

## Success Metrics

### Performance Targets
- Symbol lookup: <100μs
- Query execution: <10ms for typical queries
- Effect validation: <5ms
- Stream processing: >100K items/second
- Diagnostic generation: <1ms per diagnostic

### Quality Metrics
- Zero-allocation primitives where possible
- 100% safe transformations (no data loss)
- <5% memory overhead for indices
- >90% test coverage
- <0.1% crash rate

### Usability Metrics
- Single unified API for all operations
- <10 lines of code for common tasks
- Rich documentation with examples
- Editor integration within 100ms response time

## Migration Strategy

### Backward Compatibility
- All existing modules remain unchanged
- New primitives extend, don't replace
- Gradual adoption path
- Feature flags for new capabilities

### Incremental Adoption
1. Start with semantic primitives in parser
2. Add query layer on top of existing facts
3. Implement effects for safe refactoring
4. Enable streaming for large files
5. Add diagnostics to existing linters
6. Provide LSP protocol adapter

## Example: Unified Rename Operation

```zig
// 1. Query for symbol
const query = Query.select(Symbol)
    .where(.name, .equals, "oldFunction")
    .where(.kind, .equals, .function);
const symbols = try query.execute();

// 2. Find all references
const refs = try semantic.findReferences(symbols[0].id);

// 3. Create rename effect
const effect = Rename{
    .symbol = symbols[0].id,
    .old_name = "oldFunction",
    .new_name = "newFunction",
    .scope = .project,
};

// 4. Validate the change
const validation = try effect.validate();
if (validation.hasConflicts()) {
    // 5. Generate diagnostics
    const diagnostics = validation.toDiagnostics();
    for (diagnostics) |diag| {
        try reporter.emit(diag);
    }
    return error.RenameConflict;
}

// 6. Apply the change
const changeset = try effect.toChangeSet();
try changeset.apply();

// 7. Stream updates to editor
var stream = changeset.toEventStream();
while (try stream.next()) |event| {
    try protocol.notify("textDocument/didChange", event);
}
```

## Future Extensions

### Potential Additions
1. **AI/ML Integration**: Primitives for model-based suggestions
2. **Debugging Primitives**: Breakpoints, stack traces, variables
3. **Performance Primitives**: Profiling, optimization hints
4. **Security Primitives**: Taint analysis, vulnerability detection
5. **Documentation Primitives**: Doc generation, examples

### Ecosystem Integration
1. **Package Managers**: Dependency analysis primitives
2. **Build Systems**: Compilation unit primitives
3. **Version Control**: Diff and merge primitives
4. **Testing Frameworks**: Test discovery and execution
5. **CI/CD**: Pipeline and artifact primitives

## Conclusion

This primitive evolution transforms zz from a parser-focused tool into a comprehensive language tooling platform. By introducing semantic understanding, powerful queries, safe transformations, streaming processing, rich diagnostics, and protocol support, we create a foundation for building any language tool imaginable.

The modular design ensures each component can evolve independently while the unified index and query engine provide coherent access to all language information. This architecture positions zz as a foundational library for the next generation of development tools.