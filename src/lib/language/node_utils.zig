const std = @import("std");
// TODO: Convert to use Pure Zig AST instead of tree-sitter
// const ts = @import("tree-sitter");
const LineBuilder = @import("../parsing/formatter.zig").LineBuilder;

/// Tree-sitter node utilities - truly generic AST helpers that work across all languages
/// TODO: Convert to use Pure Zig AST instead of tree-sitter
pub const NodeUtils = struct {
    // Temporarily disabled while transitioning to Pure Zig parser
    // All functions below will be converted to work with our AST.Node type
    
    /*
    /// Extract text from tree-sitter node
    pub fn getNodeText(node: ts.Node, source: []const u8) []const u8 {
        const start = node.startByte();
        const end = node.endByte();
        if (end <= source.len and start <= end) {
            return source[start..end];
        }
        return "";
    }

    /// Append node text to LineBuilder
    pub fn appendNodeText(node: ts.Node, source: []const u8, builder: *LineBuilder) !void {
        const text = getNodeText(node, source);
        try builder.append(text);
    }

    /// Check if node matches specific type
    pub fn isNodeType(node: ts.Node, node_type: []const u8) bool {
        return std.mem.eql(u8, node.kind(), node_type);
    }

    /// Find child node of specific type
    pub fn getChildOfType(node: ts.Node, child_type: []const u8) ?ts.Node {
        const child_count = node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                if (isNodeType(child, child_type)) {
                    return child;
                }
            }
        }
        return null;
    }

    /// Find all children of specific type
    pub fn getChildrenOfType(allocator: std.mem.Allocator, node: ts.Node, child_type: []const u8) ![]ts.Node {
        var children = std.ArrayList(ts.Node).init(allocator);
        defer children.deinit();
        
        const child_count = node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                if (isNodeType(child, child_type)) {
                    try children.append(child);
                }
            }
        }
        
        return children.toOwnedSlice();
    }

    /// Count children of specific type
    pub fn countChildrenOfType(node: ts.Node, child_type: []const u8) u32 {
        const child_count = node.childCount();
        var count: u32 = 0;
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                if (isNodeType(child, child_type)) {
                    count += 1;
                }
            }
        }
        return count;
    }

    /// Get node by index (with bounds checking)
    pub fn getChildByIndex(node: ts.Node, index: u32) ?ts.Node {
        if (index < node.childCount()) {
            return node.child(index);
        }
        return null;
    }

    /// Get the first named child of a node
    pub fn getFirstNamedChild(node: ts.Node) ?ts.Node {
        const child_count = node.namedChildCount();
        if (child_count > 0) {
            return node.namedChild(0);
        }
        return null;
    }

    /// Get the last named child of a node
    pub fn getLastNamedChild(node: ts.Node) ?ts.Node {
        const child_count = node.namedChildCount();
        if (child_count > 0) {
            return node.namedChild(child_count - 1);
        }
        return null;
    }

    /// Check if node has any children
    pub fn hasChildren(node: ts.Node) bool {
        return node.childCount() > 0;
    }

    /// Check if node has any named children
    pub fn hasNamedChildren(node: ts.Node) bool {
        return node.namedChildCount() > 0;
    }

    /// Get node range as start/end byte positions
    pub fn getNodeRange(node: ts.Node) struct { start: u32, end: u32 } {
        return .{
            .start = node.startByte(),
            .end = node.endByte(),
        };
    }

    /// Check if node is a leaf (has no children)
    pub fn isLeafNode(node: ts.Node) bool {
        return node.childCount() == 0;
    }

    /// Walk all nodes in subtree and call visitor function
    pub fn walkTree(node: ts.Node, context: anytype, visitor: fn(@TypeOf(context), ts.Node) anyerror!void) !void {
        try visitor(context, node);
        
        const child_count = node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                try walkTree(child, context, visitor);
            }
        }
    }

    /// Find nodes matching a predicate function
    pub fn findNodes(allocator: std.mem.Allocator, node: ts.Node, predicate: fn(ts.Node) bool) ![]ts.Node {
        var results = std.ArrayList(ts.Node).init(allocator);
        defer results.deinit();
        
        try findNodesRecursive(node, predicate, &results);
        return results.toOwnedSlice();
    }

    /// Helper for findNodes
    fn findNodesRecursive(node: ts.Node, predicate: fn(ts.Node) bool, results: *std.ArrayList(ts.Node)) !void {
        if (predicate(node)) {
            try results.append(node);
        }
        
        const child_count = node.childCount();
        var i: u32 = 0;
        while (i < child_count) : (i += 1) {
            if (node.child(i)) |child| {
                try findNodesRecursive(child, predicate, results);
            }
        }
    }
    */
};