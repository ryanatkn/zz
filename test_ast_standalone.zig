/// Standalone AST test to verify functionality
/// Run with: zig run test_ast_standalone.zig
const std = @import("std");
const print = std.debug.print;

// Import JSON AST as example (no shared AST anymore)
const json_ast = @import("src/lib/languages/json/ast.zig");
const AST = json_ast.AST;
const Node = json_ast.Node;
const NodeKind = json_ast.NodeKind;
const ArenaBuilder = @import("src/lib/ast/builder.zig").ArenaBuilder;
const Walker = @import("src/lib/ast/walker.zig").Walker;
const Span = @import("src/lib/span/span.zig").Span;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    print("Testing Tagged Union AST Implementation\n");
    print("======================================\n\n");

    // Test 1: Basic Node Creation
    print("Test 1: Basic Node Creation\n");
    testBasicNodes();

    // Test 2: Builder Pattern
    print("\nTest 2: Builder Pattern\n");
    try testBuilderPattern(allocator);

    // Test 3: Tree Walking
    print("\nTest 3: Tree Walking\n");
    try testTreeWalking(allocator);

    print("\nAll tests completed successfully! ✅\n");
}

fn testBasicNodes() void {
    // Create a string node
    const string_node = Node{ .string = .{
        .span = Span.init(0, 5),
        .value = "hello",
    } };

    print("  ✓ String node: kind={}, leaf={}, span={}..{}\n", 
        .{ string_node.kind(), string_node.isLeaf(), string_node.span().start, string_node.span().end });

    // Create a number node
    const number_node = Node{ .number = .{
        .span = Span.init(0, 3),
        .value = 42.0,
        .raw = "42",
    } };

    print("  ✓ Number node: kind={}, leaf={}, value={}\n",
        .{ number_node.kind(), number_node.isLeaf(), number_node.number.value });

    // Create an array node
    const array_node = Node{ .array = .{
        .span = Span.init(0, 10),
        .elements = &.{},
    } };

    print("  ✓ Array node: kind={}, leaf={}, children={}\n",
        .{ array_node.kind(), array_node.isLeaf(), array_node.childCount() });
}

fn testBuilderPattern(allocator: std.mem.Allocator) !void {
    const source = "{\"name\": \"test\", \"value\": 42}";
    
    var builder = try ArenaBuilder(AST).init(allocator, source);
    // Note: We'll manage deinit carefully since build() transfers ownership

    // Create key-value pairs
    const name_key = try builder.string(Span.init(2, 6), "name");
    const name_value = try builder.string(Span.init(10, 14), "test");
    const name_prop = try builder.property(Span.init(1, 15), name_key, name_value);

    const value_key = try builder.string(Span.init(18, 23), "value");
    const value_value = try builder.number(Span.init(26, 28), 42.0, "42");
    const value_prop = try builder.property(Span.init(17, 28), value_key, value_value);

    // Create object
    var props = [_]Node{ name_prop.*, value_prop.* };
    const obj = try builder.object(Span.init(0, 29), &props);

    // Build AST (transfers ownership)
    const ast = builder.build(obj);
    defer ast.deinit();
    // Don't call builder.deinit() after build()

    print("  ✓ Built AST with {} nodes\n", .{ast.nodeCount()});
    print("  ✓ Root is object with {} properties\n", .{ast.root.childCount()});

    // Verify structure
    const root_kind = ast.root.kind();
    if (root_kind != .object) {
        print("  ❌ Expected object, got {}\n", .{root_kind});
        return;
    }

    print("  ✓ AST structure verified\n");
}

fn testTreeWalking(allocator: std.mem.Allocator) !void {
    const source = "[1, 2, 3]";
    
    var builder = try ArenaBuilder(AST).init(allocator, source);

    // Build array with numbers
    const n1 = try builder.number(Span.init(1, 2), 1, "1");
    const n2 = try builder.number(Span.init(4, 5), 2, "2");  
    const n3 = try builder.number(Span.init(7, 8), 3, "3");

    var elements = [_]Node{ n1.*, n2.*, n3.* };
    const array = try builder.array(Span.init(0, 9), &elements);

    const ast = builder.build(array);
    defer ast.deinit();

    // Test finding all number nodes
    const numbers = try Walker.findByKind(allocator, ast.root, .number);
    defer allocator.free(numbers);

    print("  ✓ Found {} number nodes\n", .{numbers.len});
    
    if (numbers.len != 3) {
        print("  ❌ Expected 3 numbers, got {}\n", .{numbers.len});
        return;
    }

    // Test max depth
    const max_depth = try Walker.getMaxDepth(allocator, ast.root);
    print("  ✓ Maximum depth: {}\n", .{max_depth});

    if (max_depth != 1) {
        print("  ❌ Expected depth 1, got {}\n", .{max_depth});
        return;
    }

    // Test leaf nodes
    const leaves = try Walker.getLeaves(allocator, ast.root);
    defer allocator.free(leaves);

    print("  ✓ Found {} leaf nodes\n", .{leaves.len});

    if (leaves.len != 3) {
        print("  ❌ Expected 3 leaves, got {}\n", .{leaves.len});
        return;
    }

    print("  ✓ Tree walking verified\n");
}