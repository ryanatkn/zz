# AST Module - Centralized AST Infrastructure

High-performance AST construction, manipulation, and analysis infrastructure shared across all language implementations.

## Architecture

**Design Philosophy:**
- **Memory Safety First:** All text ownership tracked through `owned_texts`
- **Performance Optimized:** Zero-allocation operations where possible
- **Language Agnostic:** Generic infrastructure works for all languages
- **Composable APIs:** Small, focused modules that work together

## Module Structure

```
src/lib/ast/
├── mod.zig              # Main exports and AST type definition
├── node.zig             # Core Node type and NodeType enum
├── factory.zig          # Programmatic AST construction
├── builder.zig          # Fluent DSL for building ASTs
├── utils.zig            # Common manipulation functions
├── test_helpers.zig     # Reusable test infrastructure
├── walker.zig           # Tree walking utilities
├── visitor.zig          # Visitor pattern implementation
├── traversal.zig        # Advanced traversal strategies
├── transformation.zig   # Immutable AST transformations
├── query.zig            # CSS selector-like AST queries
└── serialization.zig    # ZON-based persistence
```

## Core Components

### AST Type (`mod.zig`)
```zig
pub const AST = struct {
    root: Node,
    source: []const u8,
    owned_texts: [][]const u8,  // Memory management
};
```

### Node Type (`node.zig`)
```zig
pub const Node = struct {
    rule_name: []const u8,
    node_type: NodeType,
    text: []const u8,
    start_position: usize,
    end_position: usize,
    children: []Node,
    attributes: ?NodeAttributes,
    parent: ?*Node,
};
```

## Factory Pattern (`factory.zig`)

**Purpose:** Safe, programmatic AST construction with proper memory management

**Key Features:**
- Tracks all allocated strings in `owned_texts`
- Builder pattern for complex structures
- Helper functions for common patterns

**API:**
```zig
const factory = ASTFactory.init(allocator);
defer factory.deinit();

const node = try factory.createLiteral("string", "hello", 0, 5);
const ast = try factory.createAST(node, source);
```

## Builder DSL (`builder.zig`)

**Purpose:** Fluent interface for building complex AST structures

**Key Features:**
- Method chaining for readability
- Type-safe construction
- Automatic memory management

**Example:**
```zig
const ast = try builder
    .object()
    .field("name", "test")
    .field("version", 1)
    .array("deps")
        .item("std")
        .item("testing")
    .endArray()
    .build();
```

## Traversal (`traversal.zig`)

**Purpose:** Unified tree walking to replace manual patterns

**Traversal Strategies:**
- `depth_first_pre` - Visit node before children
- `depth_first_post` - Visit node after children  
- `breadth_first` - Level by level traversal

**API:**
```zig
const traversal = ASTTraversal.init(allocator);
try traversal.walk(root, visitor, context, .depth_first_pre);

const nodes = try traversal.findNodes(root, predicate);
const leaf_nodes = try traversal.getLeafNodes(root);
```

## Transformation (`transformation.zig`)

**Purpose:** Immutable AST modifications with copy-on-write

**Operations:**
- Replace nodes at paths
- Insert/remove nodes
- Filter by predicates
- Merge multiple ASTs

**API:**
```zig
const transformer = ASTTransformer.init(allocator);

// Replace node
const new_ast = try transformer.replaceNode(ast, "path.to.node", new_node);

// Filter nodes
const filtered = try transformer.filterNodes(ast, predicate);

// Merge ASTs
const merged = try transformer.mergeASTs(ast1, ast2, "merged_root");
```

## Query Language (`query.zig`)

**Purpose:** CSS selector-like queries for finding nodes

**Selector Types:**
- Rule name: `"function"`
- Text contains: `":contains(text)"`
- Position: `":first-child"`, `":last-child"`
- Universal: `"*"`

**Query Builder:**
```zig
var builder = QueryBuilder.init(allocator);
const nodes = try builder
    .whereRule("function")
    .whereHasChildren()
    .whereTextContains("test")
    .execute(query, root);
```

## Serialization (`serialization.zig`)

**Purpose:** AST persistence using native ZON format

**Features:**
- ZON serialization (not JSON - high performance Zig!)
- Pretty-print and compact modes
- Configurable depth and field inclusion
- Binary format planned

**API:**
```zig
// Serialize to ZON
const serializer = ASTSerializer.init(allocator, .{ .pretty = true });
const zon_string = try serializer.serialize(ast);

// Save/load from file
try saveASTToFile(allocator, ast, "ast.zon");
const loaded = try loadASTFromFile(allocator, "ast.zon");
```

## Test Helpers (`test_helpers.zig`)

**Purpose:** Reusable test infrastructure for all language modules

**Features:**
- Create ASTs from ZON source
- Deep AST comparison
- Structure assertions
- Automatic cleanup

**API:**
```zig
// Create real AST from ZON
const ast = try ASTTestHelpers.createZonAST(allocator, ".{ .test = 42 }");

// Assert structure
try ASTTestHelpers.assertASTStructure(&node, "object", 2);

// Test context with automatic cleanup
var ctx = ASTTestHelpers.TestContext.init(allocator);
defer ctx.deinit();
const ast = try ctx.createAST(".{ .field = 1 }");
```

## Performance Characteristics

- **Node Creation:** ~50ns per node with factory
- **Tree Walking:** ~1μs per 100 nodes
- **Query Execution:** ~5μs for simple queries
- **Transformation:** ~10μs for single node replacement
- **Serialization:** ~100μs for 1000 node AST

## Memory Management

**Ownership Rules:**
1. AST owns all text through `owned_texts` array
2. Factory tracks allocations during construction
3. Single `deinit()` cleans up entire AST
4. Transformations create new ASTs (immutable)

**Best Practices:**
- Use factory for all node creation
- Prefer arena allocators for temporary operations
- Always defer cleanup immediately after creation
- Use test helpers for consistent test patterns

## Integration with Languages

All language modules in `src/lib/languages/*/` use this infrastructure:

```zig
const ast = @import("../../ast/mod.zig");
const factory = @import("../../ast/factory.zig");
const traversal = @import("../../ast/traversal.zig");

// Parse source into AST
pub fn parse(source: []const u8) !ast.AST {
    var f = factory.ASTFactory.init(allocator);
    defer f.deinit();
    
    // Build AST using factory
    const root = try parseToNode(source, &f);
    return f.createAST(root, source);
}
```

## Migration from Legacy Code

**Before (manual AST creation):**
```zig
const node = Node{
    .rule_name = try allocator.dupe(u8, "test"),
    .children = try allocator.alloc(Node, 0),
    // Manual memory management...
};
```

**After (using factory):**
```zig
var factory = ASTFactory.init(allocator);
defer factory.deinit();
const node = try factory.createRule("test", "", 0, 0);
```

## Future Enhancements

1. **Incremental Updates:** Efficient AST patching for editor integration
2. **Lazy Loading:** Stream large ASTs without full memory load
3. **Parallel Processing:** Concurrent AST operations
4. **Schema Validation:** Type-safe AST structures per language
5. **Binary Format:** Ultra-fast serialization for caching

## Development Guidelines

1. **Always use factory** for node creation (memory safety)
2. **Prefer traversal module** over manual tree walking
3. **Use query module** for finding nodes (more maintainable)
4. **Test with test_helpers** for consistency
5. **Document memory ownership** in new functions

The AST module is the foundation of zz's language processing capabilities, providing a robust, performant, and maintainable infrastructure for all language implementations.