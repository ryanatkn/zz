# Pure Zig Grammar Implementation - Concrete Next Steps

## Current State (2025-08-17)

### ✅ What We Have Working
- **Test Framework**: Complete with `MatchResult`, `TestContext`, helpers
- **Rule System**: Terminal, Sequence, Choice, Optional, Repeat, Repeat1  
- **Grammar Builder**: ✅ Fluent API with rule references
- **Module Architecture**: ✅ Clean separation (grammar.zig, builder.zig, mod.zig)
- **Validation System**: ✅ Undefined reference detection, circular dependency detection
- **Rule Resolution**: ✅ Converting ExtendedRules to basic Rules
- **Parser System**: ✅ Recursive descent parser that generates AST from Grammar
- **AST Infrastructure**: ✅ Generic nodes with visitor pattern and tree walking
- **Validated Examples**: Arithmetic with references, JSON objects, nested structures
- **60+ passing tests** across all modules

### 📍 Where We Are
**Major milestone achieved!** Complete grammar-to-AST pipeline working. Ready for real-world applications like JSON parsing and CLI argument parsing.

### ⚠️ Known Issues
- Memory leaks in nested rule allocation (needs refinement for production)

## 🚀 Next Phase: Stratified Parser Architecture

### Transition Strategy
The current recursive descent parser serves as our **Phase 0 Foundation**. We're now transitioning to a sophisticated **Stratified Parser Architecture** designed for <1ms editor interactions.

**See TODO_PURE_ZIG_PLAN.md for complete 24-week implementation roadmap**

### Why Stratified Parser?
- **Performance**: <1ms latency for critical operations (vs current 10-50ms)
- **Incremental**: Zero-copy differential updates
- **Predictive**: Speculative execution for instant response
- **Editor-Optimized**: Designed for real-time code editing

### Migration Path
1. **Keep current parser working** (fallback option)
2. **Build stratified parser in parallel** (new modules)
3. **Test with CLI argument parser** (dogfooding)
4. **Gradual command migration** (one at a time)
5. **Performance validation** (benchmarks required)

## Immediate Next Steps (Week 1)

### ✅ Step 1: Grammar Builder API [COMPLETED]
**Result**: Fluent API with rule references working

#### ✅ 1.1 Created `src/lib/grammar/builder.zig`
```zig
// Working implementation:
var builder = Grammar.builder(allocator);
_ = try builder.define("digit", choice(&.{"0", "1", "2", ...}));
_ = try builder.define("number", repeat1(&ref("digit")));
_ = builder.start("expression");
var grammar = try builder.build();
```

**Decisions Made**:
- ✅ Rule reference syntax: `ref("name")` 
- ✅ Memory management: Grammar owns compiled rules
- ✅ Error handling: Returns errors for undefined references

#### ✅ 1.2 Grammar Validation [COMPLETED]
- ✅ Detect undefined rule references
- ✅ Detect circular dependencies (disallowed)
- ✅ Validate start rule exists

### ✅ Step 2: AST Infrastructure [COMPLETED]
**Goal**: Generic AST structure with traversal capabilities

#### ✅ 2.1 Created `src/lib/ast/node.zig` [COMPLETED]
```zig
pub const Node = struct {
    rule_name: []const u8,
    node_type: NodeType,
    text: []const u8,
    start_position: usize,
    end_position: usize,
    children: []Node,
    attributes: ?std.StringHashMap([]const u8),
    parent: ?*Node,
};
```

**Decisions Made**:
- ✅ Generic nodes work for any grammar
- ✅ Parent pointers for upward navigation
- ✅ Attributes for language-specific metadata
- ✅ Arena allocator per parse tree

#### ✅ 2.2 AST Traversal [COMPLETED]
- ✅ Visitor pattern implemented
- ✅ Walker utilities (pre-order, post-order, breadth-first)
- ✅ Tree navigation (find, search, path utilities)
- ✅ Comprehensive test suite

### ✅ Step 3: Parser Implementation [COMPLETED]
**Goal**: Recursive descent parser that generates AST

#### ✅ 3.1 Created `src/lib/parser/parser.zig` [COMPLETED]
```zig
pub const Parser = struct {
    allocator: std.mem.Allocator,
    grammar: Grammar,
    
    pub fn parse(self: Parser, input: []const u8) !ParseResult {
        // Uses recursive descent algorithm
        // Returns AST or detailed error information
    }
};
```

**Decisions Made**:
- ✅ Error reporting with position information
- ✅ Parse all input (no partial parsing yet)
- ✅ Detailed parse context with backtracking
- ✅ Memory management via arena allocators

## Week 2: JSON as Proof of Concept

### Step 4: Complete JSON Grammar
**Goal**: Real-world grammar to validate system

#### 4.1 Create `src/lib/languages/json/grammar.zig`
Full JSON spec implementation:
- Object, Array, String, Number, Boolean, Null
- Proper string escape sequences
- Number formats (int, float, scientific)
- Whitespace handling

**Key Decisions Needed**:
- [ ] How to handle string parsing (regex vs manual)
- [ ] Number parsing strategy
- [ ] Unicode handling

#### 4.2 JSON-specific AST Nodes
```zig
pub const JsonNode = union(enum) {
    object: HashMap([]const u8, JsonNode),
    array: []JsonNode,
    string: []const u8,
    number: f64,
    boolean: bool,
    null,
};
```

**Key Decisions Needed**:
- [ ] Convert generic AST to typed or parse directly to typed?
- [ ] Validation during parse or separate pass?

### Step 5: JSON Formatter
**Goal**: Prove AST-based formatting works

#### 5.1 Create `src/lib/languages/json/formatter.zig`
- Pretty print with indentation
- Minified output option
- Compare with existing JSON formatter

**Success Criteria**:
- Identical output to existing formatter
- Performance within 2x of current

## Week 3: Performance & Optimization

### Step 6: Benchmarking Infrastructure
**Goal**: Measure to guide optimization

#### 6.1 Create `src/lib/grammar/benchmark.zig`
- Parse time for various input sizes
- Memory usage tracking
- Comparison with tree-sitter baseline

**Metrics to Track**:
- Parse time per KB
- Memory usage ratio to input size
- Cache hit rates (when added)

### Step 7: Initial Optimizations
**Goal**: Address obvious performance issues

**Potential Optimizations** (measure first):
- [ ] String interning for rule names
- [ ] Arena allocator per parse
- [ ] Rule result caching (memoization)

**Key Decisions Needed**:
- [ ] When to optimize vs maintain simplicity
- [ ] Acceptable performance targets

## Week 4: Zig Language Subset

### Step 8: Minimal Zig Grammar
**Goal**: Start replacing tree-sitter incrementally

#### 8.1 Start with Declarations Only
```zig
const x = 5;
pub const y: u32 = 10;
```

**Incremental Additions**:
1. Variable declarations
2. Function declarations (no body)
3. Function bodies (simple statements)
4. Control flow
5. Expressions with precedence

**Key Decisions Needed**:
- [ ] How to handle Zig's complex grammar features
- [ ] Precedence climbing vs other approaches
- [ ] Comment attachment strategy

### Step 9: Zig Formatter Parity
**Goal**: Match existing formatter output

**Test Strategy**:
- Run against existing test suite
- A/B test on real code
- Performance comparison

## Decision Points & Open Questions

### Architectural Decisions Pending

1. **Memory Management**
   - Arena per parse vs reference counting vs manual
   - String ownership and lifetime
   - AST node allocation strategy

2. **Error Handling**
   - Parse errors vs panics
   - Error recovery strategy
   - Diagnostic quality vs performance

3. **Grammar Definition Style**
   - External DSL vs Zig code
   - Runtime vs compile-time grammar construction
   - How to handle precedence and associativity

4. **Parser Algorithm**
   - Continue with recursive descent
   - Move to table-driven (LR/LALR)
   - Packrat with memoization
   - Parser combinators

5. **AST Design**
   - Generic nodes vs language-specific
   - Trivia attachment
   - Parent pointers vs pure tree
   - Immutable vs mutable

### Performance Targets (Tentative)

| Metric | Target | Acceptable |
|--------|--------|------------|
| JSON parse speed | < 100ms/MB | < 200ms/MB |
| Memory usage | < 3x input | < 5x input |
| Zig parse speed | < 200ms/MB | < 500ms/MB |
| Format speed | < 50ms/MB | < 100ms/MB |

### Risk Mitigations

| Risk | Mitigation Strategy |
|------|-------------------|
| Performance too slow | Keep tree-sitter, optimize critical path only |
| Grammar too complex | Start with subset, expand gradually |
| Memory usage too high | Arena allocators, streaming where possible |
| Maintainability | Keep simple implementation as reference |

## Success Criteria for Moving Forward

### After Week 1 (Builder + Simple Parser)
- [ ] Can define grammars declaratively
- [ ] Can parse and build AST for arithmetic/JSON examples
- [ ] Tests passing, clean API

### After Week 2 (JSON Complete)
- [ ] Full JSON grammar working
- [ ] JSON formatter producing correct output
- [ ] Performance baseline established

### After Week 3 (Optimization)
- [ ] Performance within 5x of tree-sitter
- [ ] Memory usage acceptable
- [ ] Clear optimization paths identified

### After Week 4 (Zig Subset)
- [ ] Basic Zig constructs parsing correctly
- [ ] Formatter output matches for simple files
- [ ] Path clear for full Zig grammar

## Next Document Trigger

Create `TODO_PURE_ZIG_INTEGRATION.md` when:
- JSON is fully working with acceptable performance
- Zig subset is parsing and formatting correctly
- Ready to plan tree-sitter replacement strategy

---

*This document represents concrete, testable steps. Each step has clear deliverables and decision points marked for later resolution.*