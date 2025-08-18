// TODO delete this? see ../../ast/

// Re-export of the main AST module for parser usage
pub usingnamespace @import("../../ast/mod.zig");

// Additional types needed by the stratified parser
pub const AST = struct {
    root: ASTNode,
    allocator: std.mem.Allocator,
    /// Texts allocated during parsing that are owned by this AST
    owned_texts: []const []const u8,

    pub fn deinit(self: *AST) void {
        // Free the AST tree
        self.root.deinit(self.allocator);
        
        // Free all owned texts allocated during parsing
        for (self.owned_texts) |text| {
            self.allocator.free(text);
        }
        self.allocator.free(self.owned_texts);
    }
};

pub const ASTNode = Node;
pub const NodeKind = NodeType;

const std = @import("std");
const Node = @import("../../ast/mod.zig").Node;
const NodeType = @import("../../ast/mod.zig").NodeType;
