# TODO: Unified AST Architecture - The Foundation for Everything

## Vision

Build a **single, unified AST system** that powers all code intelligence features:
- **Formatting**: Structure-aware, context-preserving
- **Linting**: Semantic analysis, pattern detection
- **Code Generation**: AST transformations, macro expansion
- **Extraction**: Intelligent code selection for LLMs
- **Refactoring**: Safe code transformations
- **Analysis**: Dependency graphs, complexity metrics

The key insight: **The AST should be our single source of truth**, not an afterthought.

## Current State: The Impedance Mismatch

### What We Have
```
tree-sitter AST → Our Code → Text Manipulation → Output
     ↓                ↓              ↓
  Black Box      Partial Use    Lost Context
```

### The Problems
1. **tree-sitter AST is opaque**: C structs we can't extend or deeply integrate
2. **Information loss**: AST → text → manipulation loses structure
3. **Multiple parsers**: Formatter parses differently than linter
4. **No unified model**: Each feature reimplements parsing logic
5. **Grammar lock-in**: Can't fix grammar bugs or add features

## Three Architectural Paths

### Option A: Pure Zig Implementation (Full Control)

**Replace tree-sitter entirely with Zig-native parsing**

```zig
// Our own grammar definition system
pub const Grammar = struct {
    rules: []Rule,
    precedence: []Precedence,
    conflicts: []Conflict,
    
    pub fn compile(self: Grammar) Parser {
        // Generate optimized parser at comptime
    }
};

// Our own AST that we fully control
pub const AST = struct {
    kind: NodeKind,
    source_range: SourceRange,
    
    // Rich metadata for all use cases
    trivia: Trivia,           // Comments, whitespace
    semantic: SemanticInfo,   // Types, scopes, bindings
    formatting: FormatHints,  // Original formatting choices
    synthetic: bool,          // Generated vs source code
    
    // Flexible child storage
    children: union(enum) {
        list: []AST,
        named: std.StringHashMap(AST),
        token: Token,
    },
};
```

**Pros:**
- Complete control over parsing and AST structure
- Can optimize for our specific use cases
- Single language (pure Zig) reduces complexity
- Can innovate on grammar features
- Comptime parser generation possible

**Cons:**
- Massive implementation effort (10,000+ lines per language)
- Need to maintain grammar compatibility
- Lose tree-sitter ecosystem benefits
- Performance risk vs mature C implementation

### Option B: Tree-Sitter + Rich Overlay (Hybrid)

**Keep tree-sitter for parsing, build rich overlay on top**

```zig
// Wrap tree-sitter AST with our rich metadata
pub const UnifiedNode = struct {
    // Original tree-sitter node
    ts_node: ts.Node,
    
    // Our additions
    id: NodeId,                    // Unique identifier for caching
    parent: ?*UnifiedNode,          // Bidirectional tree
    metadata: NodeMetadata,         // Our rich data
    
    // Lazy-computed caches
    semantic_cache: ?SemanticInfo,
    format_cache: ?FormatSpec,
    lint_cache: ?[]LintViolation,
    
    pub const NodeMetadata = struct {
        // Preserved source information
        leading_trivia: []Trivia,
        trailing_trivia: []Trivia,
        original_formatting: FormatChoices,
        
        // Semantic information
        scope: ?*Scope,
        type_info: ?TypeInfo,
        symbol: ?Symbol,
        
        // Cross-references
        references: []NodeId,
        definitions: []NodeId,
        dependencies: []NodeId,
    };
};

// Unified interface over tree-sitter
pub const UnifiedAST = struct {
    root: UnifiedNode,
    source: []const u8,
    language: Language,
    
    // Rich indexes for fast queries
    symbol_table: SymbolTable,
    scope_tree: ScopeTree,
    type_graph: TypeGraph,
    
    // Modification tracking
    dirty_nodes: std.AutoHashMap(NodeId, void),
    version: u64,
    
    pub fn from_tree_sitter(tree: ts.Tree, source: []const u8) !UnifiedAST {
        // Build our rich overlay
        var ast = UnifiedAST{
            .root = try build_unified_node(tree.root()),
            .source = source,
        };
        
        // Build indexes in single pass
        try ast.build_indexes();
        
        return ast;
    }
    
    // Query API that hides tree-sitter details
    pub fn query(self: UnifiedAST, pattern: QueryPattern) QueryResult {
        // Use tree-sitter queries internally but return our nodes
    }
    
    // Modification API for transformations
    pub fn transform(self: *UnifiedAST, node: NodeId, transform: Transform) !void {
        // Track changes for incremental updates
        try self.dirty_nodes.put(node, {});
        self.version += 1;
    }
};
```

**Pros:**
- Leverages mature tree-sitter parsing
- Can be implemented incrementally
- Maintains compatibility with tree-sitter ecosystem
- Lower implementation cost
- Can still innovate on top

**Cons:**
- Two-layer complexity
- Some impedance mismatch remains
- Memory overhead of dual representation
- Can't fix tree-sitter grammar bugs

### Option C: Custom Grammar → Tree-Sitter Backend (Best of Both)

**Define grammars in Zig, compile to tree-sitter at build time**

```zig
// Define grammar in Zig
pub const ZigGrammar = Grammar{
    .rules = .{
        .source_file = seq(
            repeat(.top_level_decl),
            eof(),
        ),
        
        .top_level_decl = choice(
            .function_decl,
            .struct_decl,
            .const_decl,
            .test_decl,
        ),
        
        .function_decl = seq(
            optional(.visibility_modifier),
            keyword("fn"),
            field("name", .identifier),
            field("parameters", .parameter_list),
            optional(field("return_type", .type_expression)),
            field("body", .block),
        ),
        
        // ... more rules
    },
    
    .precedence = .{
        // Operator precedence
        .{ .left, 1, .logical_or },
        .{ .left, 2, .logical_and },
        .{ .left, 3, .equality },
        .{ .left, 4, .comparison },
        .{ .left, 5, .addition },
        .{ .left, 6, .multiplication },
        .{ .right, 7, .unary },
        .{ .left, 8, .call },
        .{ .left, 9, .member_access },
    },
};

// Build-time compilation
pub fn build(b: *std.Build) !void {
    // Compile our Zig grammar to tree-sitter grammar.js
    const grammar_step = b.addExecutable(.{
        .name = "grammar_compiler",
        .root_source_file = .{ .path = "tools/grammar_compiler.zig" },
    });
    
    grammar_step.addRunStep(.{
        .args = &.{
            "src/grammars/zig_grammar.zig",
            "deps/tree-sitter-zig/grammar.js",
        },
    });
    
    // Then use tree-sitter-cli to generate parser.c
    const tree_sitter_generate = b.addSystemCommand(&.{
        "tree-sitter", "generate",
        "--no-bindings",
        "deps/tree-sitter-zig/grammar.js",
    });
}

// Runtime: Unified AST that fully leverages tree-sitter
pub const UnifiedAST = struct {
    // We control the grammar, so we know exactly what nodes exist
    root: Node,
    source: SourceFile,
    
    pub const Node = union(enum) {
        // Generated from our grammar definition
        source_file: SourceFile,
        function_decl: FunctionDecl,
        struct_decl: StructDecl,
        // ...
        
        // Common interface
        pub fn range(self: Node) SourceRange {
            return switch (self) {
                inline else => |n| n.range,
            };
        }
        
        pub fn format(self: Node, ctx: *FormatContext) !void {
            switch (self) {
                .function_decl => |f| try f.format(ctx),
                .struct_decl => |s| try s.format(ctx),
                // ...
            }
        }
        
        pub fn lint(self: Node, ctx: *LintContext) !void {
            switch (self) {
                .function_decl => |f| try f.lint(ctx),
                // ...
            }
        }
    };
    
    pub const FunctionDecl = struct {
        range: SourceRange,
        trivia: Trivia,
        
        // Strongly typed fields from grammar
        visibility: ?VisibilityModifier,
        name: Identifier,
        parameters: []Parameter,
        return_type: ?TypeExpression,
        body: Block,
        
        // Computed properties
        semantic: struct {
            symbol: Symbol,
            scope: *Scope,
            calls_graph: []FunctionRef,
            complexity: u32,
        },
        
        pub fn format(self: FunctionDecl, ctx: *FormatContext) !void {
            // Format with full context
            if (self.visibility) |vis| {
                try ctx.write(vis.text());
                try ctx.space();
            }
            
            try ctx.write("fn");
            try ctx.space();
            try ctx.write(self.name.text);
            
            // Format parameters based on length
            const params_width = self.parameters_width();
            if (params_width > ctx.remaining_width()) {
                try self.format_parameters_multiline(ctx);
            } else {
                try self.format_parameters_inline(ctx);
            }
            
            // ...
        }
        
        pub fn lint(self: FunctionDecl, ctx: *LintContext) !void {
            // Function-specific lints
            if (self.name.text[0] != std.ascii.toUpper(self.name.text[0])) {
                try ctx.report(.{
                    .rule = "function-naming",
                    .message = "Function names should be PascalCase",
                    .range = self.name.range,
                });
            }
            
            if (self.semantic.complexity > 10) {
                try ctx.report(.{
                    .rule = "complexity",
                    .message = "Function is too complex",
                });
            }
        }
    };
};
```

**Pros:**
- **Best of both worlds**: Our grammar design, tree-sitter's parsing
- **Single source of truth**: Grammar generates both parser and AST types
- **Type safety**: Comptime-known node types
- **Extensible**: Can add custom node types and fields
- **Tooling**: Can generate docs, schemas, LSP definitions from grammar

**Cons:**
- Complex build process
- Need to write grammar compiler
- Still dependent on tree-sitter runtime

## Recommended Architecture: Option C with Staged Implementation

### Phase 1: Grammar-First Design (Weeks 1-2)

Create Zig-native grammar definitions that compile to tree-sitter:

```zig
// src/grammar/base.zig
pub const Grammar = struct {
    name: []const u8,
    rules: []Rule,
    extras: []Rule,      // Whitespace, comments
    conflicts: [][]Rule, // Known ambiguities
    precedences: []Precedence,
    
    // Compile to tree-sitter grammar.js
    pub fn compile_to_tree_sitter(self: Grammar) ![]const u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        var writer = buffer.writer();
        
        try writer.print("module.exports = grammar({{\n", .{});
        try writer.print("  name: '{s}',\n", .{self.name});
        
        try writer.print("  rules: {{\n", .{});
        for (self.rules) |rule| {
            try self.compile_rule(writer, rule);
        }
        try writer.print("  }},\n", .{});
        
        // ... compile other sections
        
        try writer.print("}});\n", .{});
        return buffer.toOwnedSlice();
    }
};

// src/grammar/zig.zig
pub const zig_grammar = Grammar{
    .name = "zig",
    .rules = &.{
        rule("source_file", repeat(ref("declaration"))),
        
        rule("declaration", choice(.{
            ref("function_declaration"),
            ref("const_declaration"),
            ref("struct_declaration"),
        })),
        
        rule("function_declaration", seq(.{
            optional(ref("visibility")),
            keyword("fn"),
            field("name", ref("identifier")),
            field("params", ref("parameter_list")),
            optional(field("return_type", ref("type"))),
            field("body", ref("block")),
        })),
    },
};
```

### Phase 2: AST Generation (Weeks 3-4)

Generate strongly-typed AST from grammar:

```zig
// tools/ast_generator.zig
pub fn generate_ast(grammar: Grammar) !void {
    // Generate node types from grammar rules
    for (grammar.rules) |rule| {
        try generate_node_type(rule);
    }
}

// Generated: src/ast/zig_nodes.zig
pub const FunctionDeclaration = struct {
    base: NodeBase,
    visibility: ?Visibility,
    name: Identifier,
    params: ParameterList,
    return_type: ?Type,
    body: Block,
    
    // Generated visitor pattern
    pub fn accept(self: *FunctionDeclaration, visitor: anytype) !void {
        try visitor.visit_function_declaration(self);
    }
};
```

### Phase 3: Unified Interface (Weeks 5-6)

Build the unified API over tree-sitter + our AST:

```zig
// src/ast/unified.zig
pub const UnifiedAST = struct {
    tree: ts.Tree,
    source: Source,
    nodes: NodeStorage,
    indexes: Indexes,
    
    pub fn parse(source: []const u8, language: Language) !UnifiedAST {
        // Use tree-sitter for parsing
        const parser = try Parser.init(language);
        const tree = try parser.parse(source);
        
        // Build our overlay
        var ast = UnifiedAST{
            .tree = tree,
            .source = Source.init(source),
            .nodes = NodeStorage.init(allocator),
            .indexes = Indexes.init(allocator),
        };
        
        // Single pass to build all indexes
        try ast.build_overlay(tree.root());
        
        return ast;
    }
    
    // High-level API hides tree-sitter details
    pub fn format(self: *UnifiedAST, options: FormatOptions) ![]const u8 {
        var formatter = Formatter.init(self, options);
        return formatter.format();
    }
    
    pub fn lint(self: *UnifiedAST, rules: []LintRule) ![]Diagnostic {
        var linter = Linter.init(self, rules);
        return linter.run();
    }
    
    pub fn transform(self: *UnifiedAST, transformation: Transformation) !void {
        var transformer = Transformer.init(self);
        try transformer.apply(transformation);
    }
};
```

### Phase 4: Feature Implementation (Weeks 7-8)

Implement features on unified AST:

```zig
// src/features/formatter.zig
pub const Formatter = struct {
    ast: *UnifiedAST,
    options: FormatOptions,
    
    pub fn format(self: *Formatter) ![]const u8 {
        // Work with unified AST, not text
        var ctx = FormatContext.init(self.options);
        try self.visit_node(self.ast.root, &ctx);
        return ctx.render();
    }
    
    fn visit_function(self: *Formatter, func: *FunctionDeclaration, ctx: *FormatContext) !void {
        // Format with full AST context
        try ctx.write_keyword("fn");
        try ctx.space();
        try ctx.write(func.name.text);
        
        // Decide multiline based on AST, not text
        if (func.params.count() > 3 or func.total_width() > ctx.line_width) {
            try self.format_params_multiline(func.params, ctx);
        } else {
            try self.format_params_inline(func.params, ctx);
        }
    }
};

// src/features/linter.zig
pub const Linter = struct {
    ast: *UnifiedAST,
    rules: []LintRule,
    
    pub fn run(self: *Linter) ![]Diagnostic {
        var diagnostics = std.ArrayList(Diagnostic).init(allocator);
        
        // Walk AST once, apply all rules
        var visitor = LintVisitor{
            .ast = self.ast,
            .rules = self.rules,
            .diagnostics = &diagnostics,
        };
        
        try self.ast.walk(&visitor);
        return diagnostics.toOwnedSlice();
    }
};
```

## Implementation Roadmap

### Stage 1: Foundation (Month 1)
- [ ] Week 1-2: Design and implement grammar DSL in Zig
- [ ] Week 3-4: Build grammar → tree-sitter compiler

### Stage 2: AST System (Month 2)
- [ ] Week 5-6: Generate AST types from grammar
- [ ] Week 7-8: Build unified AST overlay

### Stage 3: Features (Month 3)
- [ ] Week 9-10: Reimplement formatter on unified AST
- [ ] Week 11-12: Implement linter on unified AST

### Stage 4: Advanced (Month 4)
- [ ] Week 13-14: Add code generation features
- [ ] Week 15-16: Add refactoring support

## Benefits of Unified AST

### For Formatting
- No more text manipulation
- Context-aware decisions
- Preserve structure perfectly
- Comment attachment solved

### For Linting
- Single AST walk for all rules
- Semantic analysis built-in
- Cross-reference analysis
- Type-aware rules

### For Code Generation
- AST transformations
- Macro expansion
- Code synthesis
- Template instantiation

### For LLM Integration
- Semantic extraction
- Context-aware prompts
- Code understanding
- Intelligent completion

## Comparison Matrix

| Feature | Current | Pure Zig | Hybrid | Grammar-First |
|---------|---------|----------|--------|---------------|
| Implementation effort | - | High | Medium | Medium-High |
| Control | Low | Full | Medium | High |
| tree-sitter compat | Full | None | Full | Full |
| Type safety | Low | High | Medium | High |
| Performance | Good | Unknown | Good | Good |
| Maintainability | Poor | High | Medium | High |
| Innovation potential | Low | High | Medium | High |

## Success Metrics

1. **Single AST**: All features use same AST
2. **Performance**: < 100ms for 10K LOC file
3. **Memory**: < 10x source size
4. **Correctness**: 100% test pass rate
5. **Features**: Format + Lint + Generate working
6. **Extensibility**: New language < 1 week

## Technical Decisions

### Why Keep tree-sitter?
- **Maturity**: Battle-tested parser generator
- **Performance**: Highly optimized C code
- **Incremental**: Supports incremental parsing
- **Error recovery**: Excellent error recovery
- **Ecosystem**: Query system, highlights, etc.

### Why Not Pure tree-sitter?
- **Limited AST**: Can't extend with our metadata
- **C Interface**: FFI overhead and complexity
- **No customization**: Can't fix grammar issues
- **Text-based**: Loses structure for formatting

### Why Grammar-First?
- **Single source of truth**: Grammar defines everything
- **Type safety**: Comptime-known node types
- **Tooling**: Can generate docs, types, schemas
- **Evolution**: Can evolve grammar over time
- **Control**: We own the design

### Zig Design Principles
- **Idiomatic Zig**: Use comptime, no hidden allocations, explicit error handling
- **Efficiency first**: Arena allocators, COW where sensible, zero-copy parsing
- **Good taste**: Clean interfaces, obvious code, no clever tricks
- **Learn from deps**: Study zig-tree-sitter for FFI patterns, zig-spec for language rules
- **Practical**: Ship working code over perfect abstractions

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Grammar compiler complexity | High | Start with subset, expand incrementally |
| tree-sitter version changes | Medium | Pin version, test extensively |
| Performance regression | Medium | Benchmark continuously |
| AST size/memory | Medium | Use COW, lazy fields, arena allocation |
| Grammar design mistakes | High | Study successful grammars (Roslyn, Swift) |

## Prior Art & References

### Roslyn (C#)
- Unified "Syntax Tree" for all features
- Rich nodes with trivia
- Immutable with red-green trees
- Powers IDE, compiler, analyzers

### Swift Syntax
- Generated from grammar
- Strongly typed nodes
- Used by formatter, linter, refactoring
- SwiftSyntaxBuilder for codegen

### rust-analyzer
- Own parser, not tree-sitter
- Unified HIR for all analysis
- Incremental computation
- Powers IDE features

### Our References (in deps/)
- **tree-sitter**: Core parsing engine we're building on
- **tree-sitter-{css,html,json,svelte,typescript,zig}**: Language grammars to study/extend
- **zig-tree-sitter**: Zig bindings showing idiomatic FFI patterns
- **zig-spec**: Authoritative Zig language specification
- **webref**: Web standards for HTML/CSS correctness

## Recommendation

**Proceed with Option C: Grammar-First with tree-sitter backend**

This gives us:
1. Control over grammar design
2. Strongly typed AST
3. tree-sitter's parsing performance
4. Unified AST for all features
5. Clear migration path

Start with Zig language as proof of concept, then expand to TypeScript once proven.

## Next Steps

1. **Prototype grammar DSL** (1 week)
2. **Build grammar compiler** (1 week)  
3. **Generate Zig AST types** (1 week)
4. **Implement formatter on unified AST** (1 week)
5. **Evaluate and decide on full implementation**

The key insight: **We need to own our AST design** while leveraging tree-sitter's parsing expertise. This unified AST becomes the foundation for all code intelligence features.