const std = @import("std");
const Node = @import("node.zig").Node;
const NodeType = @import("node.zig").NodeType;
const AST = @import("mod.zig").AST;

/// AST Factory for programmatic construction of AST nodes
/// Provides memory-safe node creation with proper owned_texts tracking
pub const ASTFactory = struct {
    allocator: std.mem.Allocator,
    owned_texts: std.ArrayList([]const u8),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .owned_texts = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.owned_texts.items) |text| {
            self.allocator.free(text);
        }
        self.owned_texts.deinit();
    }

    /// Create a complete AST with a root node
    pub fn createAST(self: *Self, root: Node, source: []const u8) !AST {
        return AST{
            .root = root,
            .allocator = self.allocator,
            .owned_texts = try self.owned_texts.toOwnedSlice(),
            .source = try self.allocator.dupe(u8, source),
        };
    }

    /// Create a terminal node (leaf) with text content
    pub fn createLiteral(
        self: *Self,
        rule_name: []const u8,
        text: []const u8,
        start_pos: usize,
        end_pos: usize,
    ) !Node {
        const owned_rule_name = try self.allocator.dupe(u8, rule_name);
        const owned_text = try self.allocator.dupe(u8, text);

        try self.owned_texts.append(owned_rule_name);
        try self.owned_texts.append(owned_text);

        return Node{
            .rule_name = owned_rule_name,
            .node_type = .terminal,
            .text = owned_text,
            .start_position = start_pos,
            .end_position = end_pos,
            .children = &[_]Node{},
            .attributes = null,
            .parent = null,
        };
    }

    /// Create a rule node with children
    pub fn createRule(
        self: *Self,
        rule_name: []const u8,
        text: []const u8,
        start_pos: usize,
        end_pos: usize,
        children: []const Node,
    ) !Node {
        const owned_rule_name = try self.allocator.dupe(u8, rule_name);
        const owned_text = try self.allocator.dupe(u8, text);
        const owned_children = try self.allocator.dupe(Node, children);

        try self.owned_texts.append(owned_rule_name);
        try self.owned_texts.append(owned_text);

        return Node{
            .rule_name = owned_rule_name,
            .node_type = .rule,
            .text = owned_text,
            .start_position = start_pos,
            .end_position = end_pos,
            .children = owned_children,
            .attributes = null,
            .parent = null,
        };
    }

    /// Create an object node (commonly used for configuration files)
    pub fn createObject(
        self: *Self,
        text: []const u8,
        start_pos: usize,
        end_pos: usize,
        fields: []const Node,
    ) !Node {
        return try self.createRule("object", text, start_pos, end_pos, fields);
    }

    /// Create an array node
    pub fn createArray(
        self: *Self,
        text: []const u8,
        start_pos: usize,
        end_pos: usize,
        items: []const Node,
    ) !Node {
        return try self.createRule("array", text, start_pos, end_pos, items);
    }

    /// Create a field assignment node (field = value)
    pub fn createFieldAssignment(
        self: *Self,
        field_name: []const u8,
        value_node: Node,
        start_pos: usize,
        end_pos: usize,
    ) !Node {
        const field_node = try self.createLiteral("field_name", field_name, start_pos, start_pos + field_name.len);

        // Create equals token node
        const equals_node = try self.createLiteral("equals", "=", start_pos + field_name.len + 1, start_pos + field_name.len + 2);

        const children = [_]Node{ field_node, equals_node, value_node };
        const full_text = try std.fmt.allocPrint(self.allocator, "{s} = {s}", .{ field_name, value_node.text });
        try self.owned_texts.append(full_text);

        return try self.createRule("field_assignment", full_text, start_pos, end_pos, &children);
    }

    /// Create a string literal node
    pub fn createString(
        self: *Self,
        value: []const u8,
        start_pos: usize,
        end_pos: usize,
    ) !Node {
        const quoted_text = try std.fmt.allocPrint(self.allocator, "\"{s}\"", .{value});
        try self.owned_texts.append(quoted_text);

        return try self.createLiteral("string_literal", quoted_text, start_pos, end_pos);
    }

    /// Create a number literal node
    pub fn createNumber(
        self: *Self,
        value: anytype,
        start_pos: usize,
        end_pos: usize,
    ) !Node {
        const number_text = try std.fmt.allocPrint(self.allocator, "{}", .{value});
        try self.owned_texts.append(number_text);

        return try self.createLiteral("number_literal", number_text, start_pos, end_pos);
    }

    /// Create a boolean literal node
    pub fn createBoolean(
        self: *Self,
        value: bool,
        start_pos: usize,
        end_pos: usize,
    ) !Node {
        const bool_text = if (value) "true" else "false";
        return try self.createLiteral("boolean_literal", bool_text, start_pos, end_pos);
    }

    /// Create a null literal node
    pub fn createNull(
        self: *Self,
        start_pos: usize,
        end_pos: usize,
    ) !Node {
        return try self.createLiteral("null_literal", "null", start_pos, end_pos);
    }

    /// Create an identifier node
    pub fn createIdentifier(
        self: *Self,
        name: []const u8,
        start_pos: usize,
        end_pos: usize,
    ) !Node {
        return try self.createLiteral("identifier", name, start_pos, end_pos);
    }

    /// Create an expression node (binary operation)
    pub fn createExpression(
        self: *Self,
        operator: []const u8,
        left: Node,
        right: Node,
        start_pos: usize,
        end_pos: usize,
    ) !Node {
        const op_node = try self.createLiteral("operator", operator, left.end_position, left.end_position + operator.len);
        const children = [_]Node{ left, op_node, right };

        const expr_text = try std.fmt.allocPrint(self.allocator, "{s} {s} {s}", .{ left.text, operator, right.text });
        try self.owned_texts.append(expr_text);

        return try self.createRule("expression", expr_text, start_pos, end_pos, &children);
    }

    /// Create a comment node
    pub fn createComment(
        self: *Self,
        comment_text: []const u8,
        start_pos: usize,
        end_pos: usize,
    ) !Node {
        return try self.createLiteral("comment", comment_text, start_pos, end_pos);
    }
};

// ============================================================================
// Convenience Functions for Common Patterns
// ============================================================================

/// Create a simple object AST from key-value pairs
pub fn createSimpleObjectAST(
    allocator: std.mem.Allocator,
    fields: []const struct { []const u8, []const u8 },
) !AST {
    var factory = ASTFactory.init(allocator);
    errdefer factory.deinit();

    var field_nodes = std.ArrayList(Node).init(allocator);
    defer field_nodes.deinit();

    var pos: usize = 1; // Start after opening brace
    for (fields) |field| {
        const field_name = field[0];
        const field_value = field[1];

        const value_node = try factory.createString(field_value, pos + field_name.len + 4, pos + field_name.len + 4 + field_value.len + 2);
        const field_node = try factory.createFieldAssignment(field_name, value_node, pos, value_node.end_position);
        try field_nodes.append(field_node);

        pos = value_node.end_position + 2; // Account for comma and space
    }

    const object_text = try std.fmt.allocPrint(allocator, "{{ /* object with {} fields */ }}", .{fields.len});
    defer allocator.free(object_text);

    const root = try factory.createObject(object_text, 0, object_text.len, field_nodes.items);

    return try factory.createAST(root, object_text);
}

/// Create a simple array AST from string values
pub fn createSimpleArrayAST(
    allocator: std.mem.Allocator,
    items: []const []const u8,
) !AST {
    var factory = ASTFactory.init(allocator);
    errdefer factory.deinit();

    var item_nodes = std.ArrayList(Node).init(allocator);
    defer item_nodes.deinit();

    var pos: usize = 1; // Start after opening bracket
    for (items) |item| {
        const item_node = try factory.createString(item, pos, pos + item.len + 2); // +2 for quotes
        try item_nodes.append(item_node);
        pos = item_node.end_position + 2; // Account for comma and space
    }

    const array_text = try std.fmt.allocPrint(allocator, "[ /* array with {} items */ ]", .{items.len});
    defer allocator.free(array_text);

    const root = try factory.createArray(array_text, 0, array_text.len, item_nodes.items);

    return try factory.createAST(root, array_text);
}

/// Create a mock AST for testing with configurable structure
pub fn createMockAST(
    allocator: std.mem.Allocator,
    comptime structure: ASTStructure,
) !AST {
    var factory = ASTFactory.init(allocator);
    errdefer factory.deinit();

    const root = try createMockNode(&factory, structure, 0);
    const mock_source = try std.fmt.allocPrint(allocator, "/* Mock AST: {} */", .{structure});

    return try factory.createAST(root, mock_source);
}

/// Structure specification for mock ASTs
pub const ASTStructure = union(enum) {
    object: []const FieldSpec,
    array: []const ASTStructure,
    string: []const u8,
    number: i64,
    boolean: bool,
    null_value,
    identifier: []const u8,
};

pub const FieldSpec = struct {
    name: []const u8,
    value: ASTStructure,
};

fn createMockNode(factory: *ASTFactory, structure: ASTStructure, start_pos: usize) !Node {
    switch (structure) {
        .object => |fields| {
            var field_nodes = std.ArrayList(Node).init(factory.allocator);
            defer field_nodes.deinit();

            var pos = start_pos + 1;
            for (fields) |field| {
                const value_node = try createMockNode(factory, field.value, pos + field.name.len + 3);
                const field_node = try factory.createFieldAssignment(field.name, value_node, pos, value_node.end_position);
                try field_nodes.append(field_node);
                pos = value_node.end_position + 2;
            }

            return try factory.createObject("{ ... }", start_pos, pos + 1, field_nodes.items);
        },
        .array => |items| {
            var item_nodes = std.ArrayList(Node).init(factory.allocator);
            defer item_nodes.deinit();

            var pos = start_pos + 1;
            for (items) |item| {
                const item_node = try createMockNode(factory, item, pos);
                try item_nodes.append(item_node);
                pos = item_node.end_position + 2;
            }

            return try factory.createArray("[ ... ]", start_pos, pos + 1, item_nodes.items);
        },
        .string => |value| return try factory.createString(value, start_pos, start_pos + value.len + 2),
        .number => |value| return try factory.createNumber(value, start_pos, start_pos + 8), // Approximate
        .boolean => |value| {
            const len: usize = if (value) 4 else 5;
            return try factory.createBoolean(value, start_pos, start_pos + len);
        },
        .null_value => return try factory.createNull(start_pos, start_pos + 4),
        .identifier => |name| return try factory.createIdentifier(name, start_pos, start_pos + name.len),
    }
}
