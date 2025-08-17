const std = @import("std");

/// Simple AST node representation for basic parsing needs
pub const AstNode = struct {
    node_type: []const u8,
    text: []const u8,
    start: usize,
    end: usize,
    children: []AstNode,
    
    pub fn deinit(self: AstNode, allocator: std.mem.Allocator) void {
        for (self.children) |child| {
            child.deinit(allocator);
        }
        allocator.free(self.children);
    }
};

/// Simple AST builder for compatibility
pub const AstBuilder = struct {
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) AstBuilder {
        return .{ .allocator = allocator };
    }
    
    pub fn createNode(self: *AstBuilder, node_type: []const u8, text: []const u8, start: usize, end: usize) !AstNode {
        return AstNode{
            .node_type = try self.allocator.dupe(u8, node_type),
            .text = try self.allocator.dupe(u8, text),
            .start = start,
            .end = end,
            .children = &[_]AstNode{},
        };
    }
    
    pub fn addChild(self: *AstBuilder, parent: *AstNode, child: AstNode) !void {
        const new_children = try self.allocator.realloc(parent.children, parent.children.len + 1);
        new_children[new_children.len - 1] = child;
        parent.children = new_children;
    }
};

test "basic AST operations" {
    const testing = std.testing;
    
    var builder = AstBuilder.init(testing.allocator);
    var root = try builder.createNode("root", "test", 0, 4);
    defer root.deinit(testing.allocator);
    
    const child = try builder.createNode("identifier", "test", 0, 4);
    try builder.addChild(&root, child);
    
    try testing.expectEqualStrings("root", root.node_type);
    try testing.expect(root.children.len == 1);
}