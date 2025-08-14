const std = @import("std");
const ts = @import("tree-sitter");

/// AST Node abstraction for both tree-sitter and synthetic nodes
pub const Node = struct {
    /// The actual tree-sitter node (if available)
    ts_node: ?ts.Node,
    /// Node type as string
    kind: []const u8,
    /// Source text for this node
    text: []const u8,
    /// Start/end byte offsets
    start_byte: u32,
    end_byte: u32,
    /// Line/column positions
    start_line: u32,
    start_column: u32,
    end_line: u32,
    end_column: u32,

    /// Create from tree-sitter node
    pub fn fromTsNode(node: ts.Node, source: []const u8) Node {
        const start = node.startByte();
        const end = node.endByte();
        const text = if (end <= source.len) source[start..end] else "";
        const start_point = node.startPoint();
        const end_point = node.endPoint();

        return Node{
            .ts_node = node,
            .kind = node.kind(),
            .text = text,
            .start_byte = start,
            .end_byte = end,
            .start_line = start_point.row,
            .start_column = start_point.column,
            .end_line = end_point.row,
            .end_column = end_point.column,
        };
    }

    /// Create synthetic node for text-based extraction
    pub fn synthetic(kind: []const u8, text: []const u8, start: u32, end: u32) Node {
        return Node{
            .ts_node = null,
            .kind = kind,
            .text = text,
            .start_byte = start,
            .end_byte = end,
            .start_line = 0,
            .start_column = 0,
            .end_line = 0,
            .end_column = 0,
        };
    }

    /// Check if node has error
    pub fn hasError(self: *const Node) bool {
        if (self.ts_node) |node| {
            return node.hasError();
        }
        return false;
    }

    /// Get child count
    pub fn childCount(self: *const Node) u32 {
        if (self.ts_node) |node| {
            return node.childCount();
        }
        return 0;
    }

    /// Get child at index
    pub fn child(self: *const Node, index: u32, source: []const u8) ?Node {
        if (self.ts_node) |node| {
            if (node.child(index)) |child_node| {
                return Node.fromTsNode(child_node, source);
            }
        }
        return null;
    }

    /// Get named child count
    pub fn namedChildCount(self: *const Node) u32 {
        if (self.ts_node) |node| {
            return node.namedChildCount();
        }
        return 0;
    }

    /// Get named child at index
    pub fn namedChild(self: *const Node, index: u32, source: []const u8) ?Node {
        if (self.ts_node) |node| {
            if (node.namedChild(index)) |child_node| {
                return Node.fromTsNode(child_node, source);
            }
        }
        return null;
    }

    /// Get next sibling
    pub fn nextSibling(self: *const Node, source: []const u8) ?Node {
        if (self.ts_node) |node| {
            if (node.nextSibling()) |sibling_node| {
                return Node.fromTsNode(sibling_node, source);
            }
        }
        return null;
    }

    /// Get previous sibling
    pub fn prevSibling(self: *const Node, source: []const u8) ?Node {
        if (self.ts_node) |node| {
            if (node.prevSibling()) |sibling_node| {
                return Node.fromTsNode(sibling_node, source);
            }
        }
        return null;
    }

    /// Check if node is named (not anonymous like punctuation)
    pub fn isNamed(self: *const Node) bool {
        if (self.ts_node) |node| {
            return node.isNamed();
        }
        return true; // Synthetic nodes are considered named
    }

    /// Check if node is missing (error recovery)
    pub fn isMissing(self: *const Node) bool {
        if (self.ts_node) |node| {
            return node.isMissing();
        }
        return false;
    }

    /// Get field name for child at index (if part of a named field)
    pub fn fieldNameForChild(self: *const Node, child_index: u32) ?[]const u8 {
        if (self.ts_node) |node| {
            return node.fieldNameForChild(child_index);
        }
        return null;
    }
};