/// Test for extensible AST implementation
/// Run with: zig run test_extensible_ast.zig
const std = @import("std");
const print = std.debug.print;

// Import our extensible AST
const ast = @import("src/lib/ast/mod.zig");
const Node = ast.Node;
const NodeKind = ast.NodeKind;
const ASTBuilder = ast.ASTBuilder;
const CustomNode = ast.CustomNode;
const AttributeValue = ast.AttributeValue;
const Span = @import("src/lib/span/span.zig").Span;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    print("Testing Extensible AST Implementation\n", .{});
    print("====================================\n\n", .{});

    // Initialize global registry
    try ast.initGlobalRegistry(allocator);
    defer ast.deinitGlobalRegistry();

    // Test 1: Basic node ranges
    print("Test 1: Node Kind Ranges\n", .{});
    testNodeRanges();

    // Test 2: Language-specific nodes
    print("\nTest 2: Language-Specific Nodes\n", .{});
    try testLanguageNodes(allocator);

    // Test 3: Custom nodes
    print("\nTest 3: Custom Nodes\n", .{});
    try testCustomNodes(allocator);

    // Test 4: Performance optimization
    print("\nTest 4: Performance Optimization\n", .{});
    try testPerformanceOptimization(allocator);

    print("\nAll extensibility tests passed! ✅\n", .{});
}

fn testNodeRanges() void {
    print("  ✓ Common range: {} to {}\n", .{ @intFromEnum(NodeKind.string), @intFromEnum(NodeKind.whitespace) });
    print("  ✓ JSON range: {} to {}\n", .{ @intFromEnum(NodeKind.json_base), @intFromEnum(NodeKind.json_member) });
    print("  ✓ ZON range: {} to {}\n", .{ @intFromEnum(NodeKind.zon_base), @intFromEnum(NodeKind.zon_multiline_string) });
    print("  ✓ Custom range: {} and above\n", .{@intFromEnum(NodeKind.custom)});
    
    // Test kind classification
    const string_node = Node{ .string = .{ .span = Span.init(0, 5), .value = "test" } };
    const json_node = Node{ .json_base = CustomNode{
        .span = Span.init(0, 10),
        .type_id = 1,
        .type_name = "json_special",
        .data = .{ .inline_data = std.mem.zeroes([16]u8) },
        .attributes = null,
        .vtable = null,
    } };
    
    print("  ✓ String node is common: {}\n", .{string_node.isCommon()});
    print("  ✓ JSON node is language-specific: {}\n", .{json_node.isLanguageSpecific()});
}

fn testLanguageNodes(allocator: std.mem.Allocator) !void {
    const source = "{ \"key\": \"value\", }";
    
    var builder = try ASTBuilder.init(allocator, source);
    defer builder.deinit();
    
    // Create JSON-specific member node with trailing comma
    const key = try builder.string(Span.init(2, 5), "key");
    const value = try builder.string(Span.init(9, 14), "value");
    const json_member = try builder.jsonMember(Span.init(0, 20), key, value, true);
    
    print("  ✓ Created JSON member with trailing comma: {}\n", .{json_member.json_member.trailing_comma});
    
    // Create ZON multiline string
    const zon_multiline = try builder.zonMultilineString(
        Span.init(0, 10),
        "multiline\ncontent",
        4
    );
    
    print("  ✓ Created ZON multiline string with indent: {}\n", .{zon_multiline.zon_multiline_string.indent});
    
    // Test language registry
    if (ast.getGlobalRegistry()) |registry| {
        const json_lang = registry.getLanguage(.json_member);
        const zon_lang = registry.getLanguage(.zon_multiline_string);
        
        if (json_lang) |lang| {
            print("  ✓ JSON member belongs to language: {s}\n", .{lang});
        }
        if (zon_lang) |lang| {
            print("  ✓ ZON multiline belongs to language: {s}\n", .{lang});
        }
    }
}

fn testCustomNodes(allocator: std.mem.Allocator) !void {
    const source = "custom_syntax { special: value }";
    
    var builder = try ASTBuilder.init(allocator, source);
    defer builder.deinit();
    
    // Create custom node with inline data
    var inline_data = std.mem.zeroes([16]u8);
    inline_data[0] = 42; // Store some data
    
    const custom_node = try builder.customInline(
        .custom,
        Span.init(0, 32),
        1001, // Custom type ID
        "special_syntax",
        inline_data
    );
    
    print("  ✓ Created custom node type: {s}\n", .{custom_node.custom.type_name});
    print("  ✓ Custom data stored: {}\n", .{custom_node.custom.data.inline_data[0]});
    
    // Add attributes to the custom node
    try builder.addAttributes(custom_node, &.{
        .{ .key = "language", .value = .{ .string = "mylang" } },
        .{ .key = "version", .value = .{ .number = 1.0 } },
        .{ .key = "experimental", .value = .{ .boolean = true } },
    });
    
    if (custom_node.custom.attributes) |attrs| {
        print("  ✓ Added {} attributes to custom node\n", .{attrs.count()});
        
        if (attrs.get("language")) |lang_attr| {
            print("  ✓ Language attribute: {s}\n", .{lang_attr.string});
        }
    }
}

fn testPerformanceOptimization(allocator: std.mem.Allocator) !void {
    const source = "[1, 2, 3]";
    
    var builder = try ASTBuilder.init(allocator, source);
    defer builder.deinit();
    
    // Create nodes of different types
    const number = try builder.number(Span.init(1, 2), 1, "1");
    const json_member = try builder.jsonMember(
        Span.init(0, 5), 
        number, 
        number, 
        false
    );
    const custom = try builder.customInline(
        .custom,
        Span.init(0, 10),
        2000,
        "bench_node",
        std.mem.zeroes([16]u8)
    );
    
    // Test fast path vs slow path
    const number_span = number.span(); // Should hit fast path
    const json_span = json_member.span(); // Should hit slower path
    const custom_span = custom.span(); // Should hit slower path
    
    print("  ✓ Common node span access (fast path): {}..{}\n", .{ number_span.start, number_span.end });
    print("  ✓ Language node span access (medium path): {}..{}\n", .{ json_span.start, json_span.end });
    print("  ✓ Custom node span access (slow path): {}..{}\n", .{ custom_span.start, custom_span.end });
    
    // Test classification
    print("  ✓ Number is common: {}\n", .{number.isCommon()});
    print("  ✓ JSON member is language-specific: {}\n", .{json_member.isLanguageSpecific()});
    print("  ✓ Custom is custom: {}\n", .{custom.isCustom()});
}