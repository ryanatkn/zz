# TODO_PARSER - Complete Language Tooling Implementation Plan

**Status**: Pure Zig Stratified Parser Complete | Tree-sitter Removed | 527/546 tests passing (96.5%)  
**Goal**: Full parsing, formatting, and linting for Zig, TypeScript, CSS, HTML, JSON, Svelte  
**Last Updated**: 2025-08-17 - Test fixes completed, parser stabilized

## 🔍 Current State Assessment

### Test Status
- **527/546 tests passing** (96.5% pass rate) 
- **19 test failures** primarily in:
  - State machine transition table (needs token text matching, not just TokenKind)
  - Format config tests (ZON parsing issues)
  - Dependency manager tests
  - Some memory leaks in test cleanup

### Architecture Achievements
✅ **Pure Zig Stratified Parser** - Three-layer system complete:
- Layer 0 (Lexical): <0.1ms viewport tokenization (✅ Fixed tokenization, scanner, brackets)
- Layer 1 (Structural): <1ms boundary detection (⚠️ State machine needs token text matching)
- Layer 2 (Detailed): <10ms detailed parsing

✅ **Tree-sitter Removal** - Complete elimination of C dependencies

✅ **Foundation Infrastructure**:
- Fact-based intermediate representation
- Language detection system (7 languages)
- Extraction flags for prompt generation
- Basic formatters for JSON, CSS, HTML
- Memory management improvements (fixed double free, segfaults)

⚠️ **Incomplete Areas**:
- Language-specific grammars not fully implemented
- Format system has placeholder implementations
- No linting system
- State machine transitions need refinement

## 🎯 Integration Approaches

### Approach 1: Grammar-First Architecture (Recommended)
**Philosophy**: Define grammars in a DSL, generate parser code

```
src/lib/grammar/
├── dsl.zig                 # Grammar definition language
├── generator.zig           # Grammar → Parser code generation
└── languages/
    ├── zig.grammar         # Zig language grammar
    ├── typescript.grammar  # TypeScript grammar
    ├── css.grammar        # CSS grammar
    ├── html.grammar       # HTML grammar
    ├── json.grammar       # JSON grammar
    └── svelte.grammar     # Svelte multi-language grammar
```

**Benefits**:
- Single source of truth for language syntax
- Easy to add new languages
- Consistent parsing behavior
- Can generate both parser and formatter from same grammar

**Integration with Stratified Parser**:
```zig
// Layer 0: Use grammar for token classification
const token_type = grammar.classifyToken(lexeme);

// Layer 1: Use grammar for boundary patterns
const boundaries = grammar.getBoundaryPatterns();

// Layer 2: Use grammar for detailed parsing rules
const ast = grammar.parseWithRules(tokens, boundaries);
```

### Approach 2: Direct Integration Architecture
**Philosophy**: Implement language-specific parsers directly in stratified layers

```
src/lib/languages/
├── zig/
│   ├── lexical.zig        # Zig-specific tokenization
│   ├── structural.zig     # Zig boundary detection
│   ├── detailed.zig       # Zig AST construction
│   ├── formatter.zig      # Zig formatting rules
│   └── linter.zig         # Zig linting rules
├── typescript/
│   └── ... (same structure)
└── [other languages]/
```

**Benefits**:
- Maximum performance (no indirection)
- Language-specific optimizations
- Direct control over parsing behavior
- Easier debugging

**Integration with Stratified Parser**:
```zig
// Each layer delegates to language-specific implementation
pub const LanguageParser = union(enum) {
    zig: ZigParser,
    typescript: TypeScriptParser,
    css: CSSParser,
    // ...
    
    pub fn tokenize(self: LanguageParser, input: []const u8) ![]Token {
        return switch (self) {
            .zig => |p| p.tokenize(input),
            .typescript => |p| p.tokenize(input),
            // ...
        };
    }
};
```

### Approach 3: Hybrid Architecture (Balanced)
**Philosophy**: Common grammar infrastructure with language-specific extensions

```
src/lib/parser/
├── grammar/
│   ├── common.zig          # Shared grammar patterns
│   ├── c_like.zig         # C-like language patterns
│   └── markup.zig         # Markup language patterns
├── languages/
│   ├── zig/
│   │   ├── grammar.zig    # Zig-specific grammar rules
│   │   ├── extensions.zig # Zig-specific extensions
│   │   └── semantics.zig  # Zig semantic analysis
│   └── [others]/
└── integration/
    ├── stratified.zig      # Stratified parser integration
    ├── formatter.zig       # Unified formatter interface
    └── linter.zig         # Unified linter interface
```

**Benefits**:
- Reuse common patterns (operators, brackets, etc.)
- Language-specific customization where needed
- Good balance of maintainability and performance
- Progressive enhancement possible

## 🔧 Lessons Learned from Test Fixes

### Critical Issues Resolved

1. **Memory Management**
   - **Issue**: Double free in FactPool when release called twice
   - **Fix**: Removed duplicate release calls in tests
   - **Lesson**: RAII patterns need careful defer placement

2. **Lexical Scanner**  
   - **Issue**: Character classification didn't include hex_alpha for identifiers
   - **Fix**: Added hex_alpha check to isIdentifierStart/Char
   - **Lesson**: Character tables need complete coverage for all valid chars

3. **Pattern Matching**
   - **Issue**: Substring matching caused "my_node_modules" to match "node_modules"
   - **Fix**: Added path component boundary checking
   - **Lesson**: Path patterns must respect directory boundaries

4. **Token Delimiters**
   - **Issue**: isMatchingPair checked if types were equal instead of complementary
   - **Fix**: Explicit matching (open_paren → close_paren)
   - **Lesson**: Bracket matching needs explicit pair definitions

5. **State Machine Limitations**
   - **Issue**: Transition table uses TokenKind enum index, can't distinguish "fn" from "struct"
   - **Fix**: Would need token text matching or separate token types
   - **Lesson**: State machines need finer-grained token discrimination

### Architectural Insights

1. **TokenDelta Memory Model**
   - Static empty slices shouldn't be freed
   - Test data needs proper allocation when using deinit
   - Consider arena allocator for delta operations

2. **Error Recovery Complexity**
   - Recovery points allocation causes memory leaks
   - Simplified to empty slices for now
   - Need proper ownership model for error regions

3. **Bracket Depth Tracking**
   - Should use stack size, not passed parameter
   - Max depth needs to track actual nesting
   - Consider using bracket stack for better accuracy

4. **ZON Parser Stub**
   - Current stub always returns hardcoded values
   - Needs proper parsing or better error detection
   - Consider using std.json as interim solution

## 📋 Module Implementation Plan

### Phase 1: Parser Stability (✅ COMPLETED)
**Goal**: Fix all memory management and test failures

#### 1.1 Memory Management Fixes (✅ DONE)
```zig
// src/lib/parser/foundation/collections/pools.zig
✅ Fixed double free in FactPool.release()
✅ Removed duplicate release calls
✅ Validated allocator usage patterns

// src/lib/parser/lexical/mod.zig
✅ Fixed segfault in deinit() - check slice length before free
✅ Proper cleanup order established
✅ Added checks for static empty slices
```

#### 1.2 Lexical Layer Fixes (✅ DONE)
```zig
// src/lib/parser/lexical/tokenizer.zig
✅ Basic tokenization working (tokens properly generated)

// src/lib/parser/lexical/brackets.zig
✅ Fixed nested bracket depth tracking (use stack size)
✅ Correct max depth calculation

// src/lib/parser/lexical/scanner.zig
✅ Fixed identifier scanning (includes all valid chars)
✅ Fixed character classification tables (hex_alpha support)
```

#### 1.3 Foundation Type Fixes (✅ DONE)
```zig
// src/lib/parser/foundation/types/token.zig
✅ Fixed delimiter matching logic (explicit pair matching)
✅ isMatchingPair() works correctly

// src/lib/parser/structural/parser.zig
✅ Added error recovery (detects mismatched brackets)
✅ Improved error boundary detection
```

#### 1.4 Remaining Issues (🔄 IN PROGRESS)
- State machine needs token text matching (not just TokenKind)
- ZON parser needs real implementation
- Some test memory leaks need cleanup
- Format config tests failing

### Phase 2: Language Grammar Implementation (Week 2-3)

#### 2.1 Grammar Infrastructure
```zig
// src/lib/grammar/dsl.zig
pub const Grammar = struct {
    rules: []Rule,
    tokens: []TokenDef,
    precedence: []Precedence,
    
    pub fn compile(self: Grammar) !Parser {
        // Generate parser from grammar
    }
};

// src/lib/grammar/rule.zig
pub const Rule = struct {
    name: []const u8,
    pattern: Pattern,
    action: ?Action,
};
```

#### 2.2 Zig Language Grammar
```zig
// src/lib/languages/zig/grammar.zig
pub const zig_grammar = Grammar{
    .tokens = &.{
        .{ .name = "fn", .pattern = "fn" },
        .{ .name = "pub", .pattern = "pub" },
        .{ .name = "const", .pattern = "const" },
        .{ .name = "struct", .pattern = "struct" },
        // ...
    },
    .rules = &.{
        .{ .name = "function", .pattern = seq("pub?", "fn", "identifier", "params", "type?", "body") },
        .{ .name = "struct", .pattern = seq("struct", "{", "fields*", "}") },
        // ...
    },
};

// src/lib/languages/zig/parser.zig
pub fn parseZig(tokens: []Token) !AST {
    // Use stratified parser with Zig grammar
    const lexical = try Lexical.tokenize(tokens);
    const structural = try Structural.detectBoundaries(lexical);
    const detailed = try Detailed.parseWithGrammar(structural, zig_grammar);
    return detailed.toAST();
}
```

#### 2.3 TypeScript Language Grammar
```zig
// src/lib/languages/typescript/grammar.zig
pub const typescript_grammar = Grammar{
    .tokens = &.{
        .{ .name = "function", .pattern = "function" },
        .{ .name = "class", .pattern = "class" },
        .{ .name = "interface", .pattern = "interface" },
        .{ .name = "type", .pattern = "type" },
        // ...
    },
    .rules = &.{
        .{ .name = "function", .pattern = choice("function_decl", "arrow_function") },
        .{ .name = "class", .pattern = seq("class", "identifier", "extends?", "implements?", "body") },
        .{ .name = "interface", .pattern = seq("interface", "identifier", "extends?", "{", "members*", "}") },
        // ...
    },
};
```

#### 2.4 CSS Language Grammar
```zig
// src/lib/languages/css/grammar.zig
pub const css_grammar = Grammar{
    .tokens = &.{
        .{ .name = "selector", .pattern = regex("[.#]?[a-zA-Z][a-zA-Z0-9-]*") },
        .{ .name = "property", .pattern = regex("[a-z-]+") },
        .{ .name = "value", .pattern = regex("[^;]+") },
        // ...
    },
    .rules = &.{
        .{ .name = "rule", .pattern = seq("selector+", "{", "declaration*", "}") },
        .{ .name = "declaration", .pattern = seq("property", ":", "value", ";?") },
        .{ .name = "media", .pattern = seq("@media", "query", "{", "rule*", "}") },
        // ...
    },
};
```

#### 2.5 HTML Language Grammar
```zig
// src/lib/languages/html/grammar.zig
pub const html_grammar = Grammar{
    .tokens = &.{
        .{ .name = "tag_open", .pattern = regex("<[a-zA-Z][a-zA-Z0-9]*") },
        .{ .name = "tag_close", .pattern = regex("</[a-zA-Z][a-zA-Z0-9]*>") },
        .{ .name = "attribute", .pattern = regex("[a-zA-Z][a-zA-Z0-9-]*") },
        // ...
    },
    .rules = &.{
        .{ .name = "element", .pattern = seq("tag_open", "attributes*", ">", "content*", "tag_close") },
        .{ .name = "self_closing", .pattern = seq("tag_open", "attributes*", "/>") },
        // ...
    },
};
```

#### 2.6 JSON Language Grammar
```zig
// src/lib/languages/json/grammar.zig
pub const json_grammar = Grammar{
    .tokens = &.{
        .{ .name = "string", .pattern = regex("\"[^\"]*\"") },
        .{ .name = "number", .pattern = regex("-?[0-9]+\\.?[0-9]*") },
        .{ .name = "true", .pattern = "true" },
        .{ .name = "false", .pattern = "false" },
        .{ .name = "null", .pattern = "null" },
        // ...
    },
    .rules = &.{
        .{ .name = "value", .pattern = choice("object", "array", "string", "number", "boolean", "null") },
        .{ .name = "object", .pattern = seq("{", "pair*", "}") },
        .{ .name = "array", .pattern = seq("[", "value*", "]") },
        // ...
    },
};
```

#### 2.7 Svelte Language Grammar (Multi-language)
```zig
// src/lib/languages/svelte/grammar.zig
pub const svelte_grammar = Grammar{
    .embedded = &.{
        .{ .region = "script", .grammar = typescript_grammar },
        .{ .region = "style", .grammar = css_grammar },
        .{ .region = "template", .grammar = html_grammar },
    },
    .tokens = &.{
        .{ .name = "directive", .pattern = regex("\\{#[a-z]+") },
        .{ .name = "expression", .pattern = regex("\\{[^}]+\\}") },
        // ...
    },
    .rules = &.{
        .{ .name = "component", .pattern = seq("script?", "style?", "template") },
        .{ .name = "if_block", .pattern = seq("{#if", "expression", "}", "content*", "{/if}") },
        // ...
    },
};
```

### Phase 3: Formatter Implementation (Week 4)

#### 3.1 Unified Formatter Interface
```zig
// src/lib/formatting/formatter.zig
pub const Formatter = struct {
    language: Language,
    options: FormatOptions,
    
    pub fn format(self: Formatter, ast: AST) ![]const u8 {
        return switch (self.language) {
            .zig => formatZig(ast, self.options),
            .typescript => formatTypeScript(ast, self.options),
            .css => formatCSS(ast, self.options),
            .html => formatHTML(ast, self.options),
            .json => formatJSON(ast, self.options),
            .svelte => formatSvelte(ast, self.options),
            else => error.UnsupportedLanguage,
        };
    }
};
```

#### 3.2 Language-Specific Formatters
```zig
// src/lib/formatting/languages/zig.zig
pub fn formatZig(ast: AST, options: FormatOptions) ![]const u8 {
    var formatter = ZigFormatter.init(options);
    try ast.accept(&formatter);
    return formatter.getOutput();
}

// src/lib/formatting/languages/typescript.zig
pub fn formatTypeScript(ast: AST, options: FormatOptions) ![]const u8 {
    var formatter = TypeScriptFormatter.init(options);
    // Handle specific TypeScript formatting rules
    // - Arrow functions
    // - Type annotations
    // - Interfaces
    return formatter.format(ast);
}
```

### Phase 4: Linter Implementation (Week 5)

#### 4.1 Linting Infrastructure
```zig
// src/lib/analysis/linting/linter.zig
pub const Linter = struct {
    rules: []Rule,
    severity: SeverityConfig,
    
    pub fn lint(self: Linter, ast: AST) ![]Diagnostic {
        var diagnostics = ArrayList(Diagnostic).init(allocator);
        for (self.rules) |rule| {
            const violations = try rule.check(ast);
            try diagnostics.appendSlice(violations);
        }
        return diagnostics.toOwnedSlice();
    }
};

// src/lib/analysis/linting/rule.zig
pub const Rule = struct {
    name: []const u8,
    description: []const u8,
    severity: Severity,
    checker: *const fn (ast: AST) anyerror![]Violation,
};
```

#### 4.2 Language-Specific Rules
```zig
// src/lib/analysis/linting/languages/zig_rules.zig
pub const zig_rules = &.{
    Rule{
        .name = "unused-variable",
        .description = "Variable is declared but never used",
        .severity = .warning,
        .checker = checkUnusedVariables,
    },
    Rule{
        .name = "naming-convention",
        .description = "Names should follow Zig naming conventions",
        .severity = .warning,
        .checker = checkNamingConventions,
    },
    Rule{
        .name = "error-handling",
        .description = "Errors should be handled explicitly",
        .severity = .error,
        .checker = checkErrorHandling,
    },
};

// src/lib/analysis/linting/languages/typescript_rules.zig
pub const typescript_rules = &.{
    Rule{
        .name = "no-any",
        .description = "Avoid using 'any' type",
        .severity = .warning,
        .checker = checkNoAny,
    },
    Rule{
        .name = "prefer-const",
        .description = "Use const for values that are never reassigned",
        .severity = .info,
        .checker = checkPreferConst,
    },
};
```

### Phase 5: Integration & Testing (Week 6)

#### 5.1 CLI Integration
```zig
// src/main.zig - Add new commands
const commands = .{
    .parse = parseCommand,    // zz parse <file> --language=auto
    .format = formatCommand,   // zz format <file> --write
    .lint = lintCommand,      // zz lint <file> --fix
    .check = checkCommand,    // zz check <project> (parse + format + lint)
};
```

#### 5.2 Test Suite Enhancement
```zig
// src/test/language_tests.zig
test "complete language pipeline" {
    for (supported_languages) |lang| {
        const source = try getTestSource(lang);
        
        // Parse
        const ast = try Parser.parse(source, lang);
        try testing.expect(ast.isValid());
        
        // Format
        const formatted = try Formatter.format(ast);
        const reparsed = try Parser.parse(formatted, lang);
        try testing.expectEqual(ast, reparsed); // Round-trip test
        
        // Lint
        const diagnostics = try Linter.lint(ast);
        try testing.expect(diagnostics.len == 0); // Clean test code
    }
}
```

#### 5.3 Performance Benchmarks
```zig
// src/benchmark/language_benchmarks.zig
pub fn benchmarkLanguages() !void {
    for (supported_languages) |lang| {
        const large_file = try getLargeTestFile(lang); // 10,000+ lines
        
        // Benchmark parsing
        const parse_time = try benchmark("parse", lang, .{
            .fn = Parser.parse,
            .input = large_file,
        });
        try testing.expect(parse_time < 100 * time.ns_per_ms); // <100ms
        
        // Benchmark formatting
        const format_time = try benchmark("format", lang, .{
            .fn = Formatter.format,
            .input = parsed_ast,
        });
        try testing.expect(format_time < 50 * time.ns_per_ms); // <50ms
        
        // Benchmark linting
        const lint_time = try benchmark("lint", lang, .{
            .fn = Linter.lint,
            .input = parsed_ast,
        });
        try testing.expect(lint_time < 200 * time.ns_per_ms); // <200ms
    }
}
```

## 📊 Success Metrics

### Performance Targets
- **Parsing**: <10ms for 1000 lines (all languages)
- **Formatting**: <5ms for 1000 lines
- **Linting**: <20ms for 1000 lines with all rules
- **Memory**: <10MB for 10,000 line file
- **Cache Hit Rate**: >95% for repeated operations

### Quality Targets
- **Test Coverage**: 100% of public APIs
- **Test Pass Rate**: >99.5% (545/546 minimum)
- **Round-trip Success**: Format → Parse → Format = identical
- **Language Coverage**: Full support for all 6 core languages

### User Experience Targets
- **CLI Response**: <100ms for all commands
- **Error Messages**: Clear, actionable diagnostics
- **Configuration**: Intuitive .zon config for all features
- **Documentation**: Complete guide for each language

## 🚀 Advanced Features (Future)

### Language Server Protocol (LSP)
```zig
// src/lsp/server.zig
pub const LanguageServer = struct {
    parser: StratifiedParser,
    formatter: Formatter,
    linter: Linter,
    
    pub fn handleRequest(self: *LanguageServer, request: Request) !Response {
        return switch (request.method) {
            "textDocument/formatting" => self.format(request.params),
            "textDocument/hover" => self.hover(request.params),
            "textDocument/completion" => self.complete(request.params),
            // ...
        };
    }
};
```

### Transform System
```zig
// src/transform/transformer.zig
pub const Transformer = struct {
    rules: []TransformRule,
    
    pub fn transform(self: Transformer, ast: AST) !AST {
        var modified = ast;
        for (self.rules) |rule| {
            modified = try rule.apply(modified);
        }
        return modified;
    }
};

// Example: Convert callbacks to async/await
const modernize_js = TransformRule{
    .name = "callbacks-to-async",
    .pattern = findCallbackPattern,
    .replacement = convertToAsync,
};
```

### Plugin Architecture
```zig
// src/plugin/interface.zig
pub const Plugin = struct {
    name: []const u8,
    version: []const u8,
    languages: []Language,
    
    // Hooks
    onParse: ?*const fn (ast: AST) anyerror!AST,
    onFormat: ?*const fn (source: []const u8) anyerror![]const u8,
    onLint: ?*const fn (ast: AST) anyerror![]Diagnostic,
};

// src/plugin/loader.zig
pub fn loadPlugin(path: []const u8) !Plugin {
    const lib = try std.DynLib.open(path);
    const init_fn = lib.lookup("plugin_init", *const fn () Plugin) orelse return error.InvalidPlugin;
    return init_fn();
}
```

## 📅 Timeline Summary

**Week 1**: Parser Stability
- Fix all memory management issues
- Resolve test failures
- Achieve 99.5% test pass rate

**Week 2-3**: Language Grammars
- Implement grammar infrastructure
- Complete all 6 language grammars
- Integrate with stratified parser

**Week 4**: Formatters
- Complete formatter implementations
- Achieve round-trip formatting
- Fix remaining format tests

**Week 5**: Linters
- Implement linting infrastructure
- Add basic rules for all languages
- Create lint CLI command

**Week 6**: Integration
- Polish CLI experience
- Complete documentation
- Performance validation
- Release preparation

## 🎯 Decision Points

1. **Grammar Architecture**: Choose between Grammar-First, Direct, or Hybrid approach
2. **Parser Integration**: Decide how to integrate grammars with existing stratified parser
3. **Configuration Format**: Finalize .zon schema for formatting/linting options
4. **Plugin API**: Determine if/how to support third-party language plugins
5. **LSP Priority**: Decide if LSP should be part of initial release or future enhancement

## ✅ Definition of Done

- [ ] All 546 tests passing (100% pass rate)
- [ ] Complete parsing for Zig, TypeScript, CSS, HTML, JSON, Svelte
- [ ] Formatting works for all supported languages
- [ ] Basic linting rules implemented
- [ ] Performance targets met
- [ ] Documentation complete
- [ ] CLI commands intuitive and fast
- [ ] Memory leaks fixed
- [ ] Ready for production use

---

*This document consolidates and replaces:*
- *TODO_LANGUAGES.md (formatter architecture)*
- *TODO_PURE_ZIG_PARSER_STATUS.md (parser implementation)*  
- *TREE_SITTER_REMOVAL_COMPLETE.md (migration status)*

*Last Updated: 2025-08-17*