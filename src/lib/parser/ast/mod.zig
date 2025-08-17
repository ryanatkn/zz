// Re-export of the main AST module for parser usage
pub usingnamespace @import("../../ast/mod.zig");

// Additional types needed by the stratified parser
pub const AST = struct {
    root: ASTNode,
    allocator: std.mem.Allocator,
    
    pub fn deinit(self: *AST) void {
        // Free the AST tree
        self.root.deinit(self.allocator);
    }
};

pub const ASTNode = Node;
pub const NodeKind = NodeType;

const std = @import("std");
const Node = @import("../../ast/mod.zig").Node;
const NodeType = @import("../../ast/mod.zig").NodeType;