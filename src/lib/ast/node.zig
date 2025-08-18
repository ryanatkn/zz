const std = @import("std");

/// Generic AST node that can represent any parsed structure
pub const Node = struct {
    /// The rule name that generated this node
    rule_name: []const u8,

    /// The type of this node
    node_type: NodeType,

    /// Source text that this node represents
    text: []const u8,

    /// Start position in the original input
    start_position: usize,

    /// End position in the original input
    end_position: usize,

    /// Child nodes
    children: []Node,

    /// Optional attributes for language-specific metadata
    attributes: ?std.StringHashMap([]const u8),

    /// Parent reference for upward navigation (optional)
    parent: ?*Node,

    const Self = @This();

    pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
        // Recursively deinit children
        for (self.children) |child| {
            child.deinit(allocator);
        }
        allocator.free(self.children);

        // Deinit attributes if present
        if (self.attributes) |attrs| {
            var mutable_attrs = attrs;
            mutable_attrs.deinit();
        }
    }

    /// Get the length of text this node represents
    pub fn length(self: Self) usize {
        return self.end_position - self.start_position;
    }

    /// Check if this is a leaf node (no children)
    pub fn isLeaf(self: Self) bool {
        return self.children.len == 0;
    }

    /// Get first child, if any
    pub fn firstChild(self: Self) ?Node {
        if (self.children.len > 0) return self.children[0];
        return null;
    }

    /// Get last child, if any
    pub fn lastChild(self: Self) ?Node {
        if (self.children.len > 0) return self.children[self.children.len - 1];
        return null;
    }

    /// Find a child with specific rule name
    pub fn findChild(self: Self, rule_name: []const u8) ?Node {
        for (self.children) |child| {
            if (std.mem.eql(u8, child.rule_name, rule_name)) {
                return child;
            }
        }
        return null;
    }

    /// Find all children with specific rule name
    pub fn findChildren(self: Self, allocator: std.mem.Allocator, rule_name: []const u8) ![]Node {
        var result = std.ArrayList(Node).init(allocator);
        defer result.deinit();

        for (self.children) |child| {
            if (std.mem.eql(u8, child.rule_name, rule_name)) {
                try result.append(child);
            }
        }

        return result.toOwnedSlice();
    }

    /// Get attribute value by key
    pub fn getAttribute(self: Self, key: []const u8) ?[]const u8 {
        if (self.attributes) |attrs| {
            return attrs.get(key);
        }
        return null;
    }

    /// Set parent references for all children recursively
    pub fn setParentReferences(self: *Self) void {
        for (self.children) |*child| {
            child.parent = self;
            child.setParentReferences();
        }
    }
};

/// Type of AST node for semantic categorization
pub const NodeType = enum {
    /// Terminal node - represents literal text
    terminal,

    /// Internal node - represents a grammar rule
    rule,

    /// List node - represents repeated elements
    list,

    /// Optional node - represents optional content
    optional,

    /// Error node - represents parse errors
    error_recovery,
};

/// Builder for constructing AST nodes
pub const NodeBuilder = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) NodeBuilder {
        return .{ .allocator = allocator };
    }

    /// Create a new AST node
    pub fn createNode(
        self: NodeBuilder,
        rule_name: []const u8,
        node_type: NodeType,
        text: []const u8,
        start_pos: usize,
        end_pos: usize,
        children: []Node,
    ) !Node {
        const owned_children = try self.allocator.dupe(Node, children);

        return Node{
            .rule_name = rule_name,
            .node_type = node_type,
            .text = text,
            .start_position = start_pos,
            .end_position = end_pos,
            .children = owned_children,
            .attributes = null,
            .parent = null,
        };
    }

    /// Create a leaf node (terminal)
    pub fn createLeafNode(
        self: NodeBuilder,
        rule_name: []const u8,
        text: []const u8,
        start_pos: usize,
        end_pos: usize,
    ) !Node {
        return self.createNode(
            rule_name,
            .terminal,
            text,
            start_pos,
            end_pos,
            &[_]Node{},
        );
    }

    /// Create a node with attributes
    pub fn createNodeWithAttributes(
        self: NodeBuilder,
        rule_name: []const u8,
        node_type: NodeType,
        text: []const u8,
        start_pos: usize,
        end_pos: usize,
        children: []Node,
        attributes: std.StringHashMap([]const u8),
    ) !Node {
        var node = try self.createNode(rule_name, node_type, text, start_pos, end_pos, children);
        node.attributes = attributes;
        return node;
    }
};

/// Convenience functions for creating nodes
pub fn createNode(
    allocator: std.mem.Allocator,
    rule_name: []const u8,
    node_type: NodeType,
    text: []const u8,
    start_pos: usize,
    end_pos: usize,
    children: []Node,
) !Node {
    const builder = NodeBuilder.init(allocator);
    return builder.createNode(rule_name, node_type, text, start_pos, end_pos, children);
}

pub fn createLeafNode(
    allocator: std.mem.Allocator,
    rule_name: []const u8,
    text: []const u8,
    start_pos: usize,
    end_pos: usize,
) !Node {
    const builder = NodeBuilder.init(allocator);
    return builder.createLeafNode(rule_name, text, start_pos, end_pos);
}
