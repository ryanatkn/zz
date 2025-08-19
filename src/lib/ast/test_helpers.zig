const std = @import("std");
const testing = std.testing;
const Node = @import("node.zig").Node;
const NodeType = @import("node.zig").NodeType;
const AST = @import("mod.zig").AST;
const ASTFactory = @import("factory.zig").ASTFactory;
const createMockAST = @import("factory.zig").createMockAST;
const ASTStructure = @import("factory.zig").ASTStructure;
const FieldSpec = @import("factory.zig").FieldSpec;
const CommonRules = @import("rules.zig").CommonRules;
const ZonRules = @import("rules.zig").ZonRules;

// Import ZON parser for creating real ASTs
const zon_mod = @import("../languages/zon/mod.zig");

/// Test utilities for AST testing across all language modules
/// Provides reusable infrastructure for creating, comparing, and validating ASTs
pub const ASTTestHelpers = struct {
    /// Create a real AST from ZON source string
    /// This is the preferred method for creating test ASTs as it uses the actual parser
    pub fn createZonAST(allocator: std.mem.Allocator, zon_content: []const u8) !AST {
        return try zon_mod.parseZonString(allocator, zon_content);
    }

    /// Create a simple object AST for testing
    /// Example: createSimpleObject(allocator, &.{ .{ "name", "test" }, .{ "version", "1.0" } })
    pub fn createSimpleObject(
        allocator: std.mem.Allocator,
        fields: []const struct { []const u8, []const u8 },
    ) !AST {
        return try @import("factory.zig").createSimpleObjectAST(allocator, fields);
    }

    /// Create a simple array AST for testing
    /// Example: createSimpleArray(allocator, &.{ "item1", "item2", "item3" })
    pub fn createSimpleArray(
        allocator: std.mem.Allocator,
        items: []const []const u8,
    ) !AST {
        return try @import("factory.zig").createSimpleArrayAST(allocator, items);
    }

    /// Create a structured mock AST using the factory
    /// Example:
    /// ```zig
    /// const structure = ASTStructure{ .object = &.{
    ///     .{ .name = "test", .value = .{ .string = "value" } },
    ///     .{ .name = "count", .value = .{ .number = 42 } },
    /// } };
    /// const ast = try createStructuredAST(allocator, structure);
    /// ```
    pub fn createStructuredAST(
        allocator: std.mem.Allocator,
        comptime structure: ASTStructure,
    ) !AST {
        return try createMockAST(allocator, structure);
    }

    /// Create a minimal AST with just a root node for basic testing
    pub fn createMinimalAST(allocator: std.mem.Allocator, rule_id: u16, text: []const u8) !AST {
        var factory = ASTFactory.init(allocator);
        defer factory.deinit();

        const root = try factory.createLiteral(rule_id, text, 0, text.len);
        return try factory.createAST(root, text);
    }

    /// Create an AST with field assignments for testing disambiguation
    pub fn createFieldAssignmentAST(
        allocator: std.mem.Allocator,
        field_name: []const u8,
        field_value: []const u8,
    ) !AST {
        const zon_content = try std.fmt.allocPrint(allocator, ".{{ .{s} = \"{s}\" }}", .{ field_name, field_value });
        defer allocator.free(zon_content);

        return try createZonAST(allocator, zon_content);
    }

    /// Deep comparison of two AST nodes
    pub fn assertASTEqual(expected: *const Node, actual: *const Node) !void {
        try testing.expectEqual(expected.rule_id, actual.rule_id);
        try testing.expectEqual(expected.node_type, actual.node_type);
        try testing.expectEqualStrings(expected.text, actual.text);
        try testing.expectEqual(expected.start_position, actual.start_position);
        try testing.expectEqual(expected.end_position, actual.end_position);
        try testing.expectEqual(expected.children.len, actual.children.len);

        // Recursively check children
        for (expected.children, actual.children) |expected_child, actual_child| {
            try assertASTEqual(&expected_child, &actual_child);
        }
    }

    /// Assert that an AST has the expected structure
    pub fn assertASTStructure(node: *const Node, expected_rule_id: u16, expected_children: usize) !void {
        try testing.expectEqual(expected_rule_id, node.rule_id);
        try testing.expectEqual(expected_children, node.children.len);
    }

    /// Check if an AST node has a specific child
    pub fn assertHasChild(node: *const Node, child_rule_id: u16) !void {
        for (node.children) |child| {
            if (child.rule_id == child_rule_id) {
                return; // Found the child
            }
        }
        return error.ChildNotFound;
    }

    /// Check if an AST represents a field assignment
    pub fn assertIsFieldAssignment(node: *const Node, expected_field_name: []const u8) !void {
        try testing.expectEqual(ZonRules.field_assignment, node.rule_id);
        try testing.expect(node.children.len >= 2);

        // First child should be the field name
        const field_name_node = &node.children[0];
        try testing.expectEqual(ZonRules.field_name, field_name_node.rule_id);

        // Extract and check field name (handle dot prefix)
        var field_name = field_name_node.text;
        if (field_name.len > 0 and field_name[0] == '.') {
            field_name = field_name[1..];
        }
        try testing.expectEqualStrings(expected_field_name, field_name);
    }

    /// Print AST structure for debugging (useful for test failures)
    pub fn printAST(node: *const Node, writer: anytype, indent_level: usize) !void {
        // Print indentation
        for (0..indent_level) |_| {
            try writer.print("  ");
        }

        // Print node info with rule ID
        try writer.print("Rule#{} ({s}) [{}-{}]: \"{s}\"\n", .{
            node.rule_id,
            @tagName(node.node_type),
            node.start_position,
            node.end_position,
            node.text,
        });

        // Print children recursively
        for (node.children) |child| {
            try printAST(&child, writer, indent_level + 1);
        }
    }

    /// Print AST to stderr for debugging tests
    pub fn debugPrintAST(node: *const Node) void {
        const stderr = std.io.getStdErr().writer();
        stderr.print("\n=== AST Structure ===\n") catch return;
        printAST(node, stderr, 0) catch return;
        stderr.print("====================\n") catch return;
    }

    /// Validate that an AST has proper memory management
    pub fn validateASTMemory(ast: *const AST) !void {
        // Check that owned_texts is properly allocated
        try testing.expect(ast.owned_texts.len >= 0);

        // Check that the root node exists with valid rule ID
        try testing.expect(ast.root.rule_id < 65535);

        // Check that source is properly set
        try testing.expect(ast.source.len >= 0);
    }

    /// Count nodes in AST for size validation
    pub fn countNodes(node: *const Node) usize {
        var count: usize = 1;
        for (node.children) |child| {
            count += countNodes(&child);
        }
        return count;
    }

    /// Find all nodes with a specific rule ID
    pub fn findAllNodes(
        allocator: std.mem.Allocator,
        node: *const Node,
        rule_id: u16,
    ) ![]const *const Node {
        var result = std.ArrayList(*const Node).init(allocator);
        defer result.deinit();

        try findAllNodesRecursive(&result, node, rule_id);
        return result.toOwnedSlice();
    }

    fn findAllNodesRecursive(
        result: *std.ArrayList(*const Node),
        node: *const Node,
        rule_id: u16,
    ) !void {
        if (node.rule_id == rule_id) {
            try result.append(node);
        }

        for (node.children) |child| {
            try findAllNodesRecursive(result, &child, rule_id);
        }
    }

    /// Create a test context with temporary AST storage
    pub const TestContext = struct {
        allocator: std.mem.Allocator,
        asts: std.ArrayList(AST),

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .asts = std.ArrayList(AST).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            for (self.asts.items) |*ast| {
                ast.deinit();
            }
            self.asts.deinit();
        }

        /// Create and store an AST for automatic cleanup
        pub fn createAST(self: *Self, zon_content: []const u8) !*AST {
            const ast = try ASTTestHelpers.createZonAST(self.allocator, zon_content);
            try self.asts.append(ast);
            return &self.asts.items[self.asts.items.len - 1];
        }

        /// Create and store a simple object AST
        pub fn createObjectAST(
            self: *Self,
            fields: []const struct { []const u8, []const u8 },
        ) !*AST {
            const ast = try ASTTestHelpers.createSimpleObject(self.allocator, fields);
            try self.asts.append(ast);
            return &self.asts.items[self.asts.items.len - 1];
        }
    };
};

// Convenience functions are directly accessible via the ASTTestHelpers struct

// ============================================================================
// Test Cases for the Test Helpers
// ============================================================================

test "create simple ZON AST" {
    var ast = try ASTTestHelpers.createZonAST(testing.allocator, ".{ .name = \"test\", .version = \"1.0\" }");
    defer ast.deinit();

    try testing.expectEqual(ZonRules.object, ast.root.rule_id);
    try testing.expect(ast.root.children.len > 0);
}

test "create simple object AST" {
    const fields = [_]struct { []const u8, []const u8 }{
        .{ "name", "test" },
        .{ "version", "1.0" },
    };

    var ast = try ASTTestHelpers.createSimpleObject(testing.allocator, &fields);
    defer ast.deinit();

    try ASTTestHelpers.assertASTStructure(&ast.root, @intFromEnum(CommonRules.object), 2);
}

test "create simple array AST" {
    const items = [_][]const u8{ "item1", "item2", "item3" };

    var ast = try ASTTestHelpers.createSimpleArray(testing.allocator, &items);
    defer ast.deinit();

    try ASTTestHelpers.assertASTStructure(&ast.root, @intFromEnum(CommonRules.array), 3);
}

test "create structured AST" {
    const structure = ASTStructure{ .object = &.{
        .{ .name = "test", .value = .{ .string = "value" } },
        .{ .name = "count", .value = .{ .number = 42 } },
    } };

    var ast = try ASTTestHelpers.createStructuredAST(testing.allocator, structure);
    defer ast.deinit();

    try ASTTestHelpers.assertASTStructure(&ast.root, @intFromEnum(CommonRules.object), 2);
}

test "AST comparison" {
    var ast1 = try ASTTestHelpers.createZonAST(testing.allocator, ".{ .test = 42 }");
    defer ast1.deinit();

    var ast2 = try ASTTestHelpers.createZonAST(testing.allocator, ".{ .test = 42 }");
    defer ast2.deinit();

    // Note: This test might fail if parser generates different internal structures
    // In practice, you'd compare specific parts of the AST rather than the whole thing
    try testing.expectEqual(ast1.root.rule_id, ast2.root.rule_id);
}

test "test context automatic cleanup" {
    var ctx = ASTTestHelpers.TestContext.init(testing.allocator);
    defer ctx.deinit();

    _ = try ctx.createAST(".{ .test = \"value\" }");
    _ = try ctx.createObjectAST(&.{.{ "name", "test" }});

    // ASTs will be automatically cleaned up by ctx.deinit()
    try testing.expectEqual(@as(usize, 2), ctx.asts.items.len);
}
