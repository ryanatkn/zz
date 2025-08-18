const std = @import("std");

// ============================================================================
// Core AST Types
// ============================================================================

/// Generic AST node that can represent any parsed structure
pub const Node = @import("node.zig").Node;

/// Alias for Node for compatibility
pub const ASTNode = Node;

/// Visitor pattern for AST traversal
pub const Visitor = @import("visitor.zig").Visitor;

/// Walker utilities for tree traversal
pub const Walker = @import("walker.zig").Walker;

// ============================================================================
// Node Creation and Management
// ============================================================================

pub const NodeBuilder = @import("node.zig").NodeBuilder;
pub const NodeType = @import("node.zig").NodeType;

// ============================================================================
// Utility Functions
// ============================================================================

pub const createNode = @import("node.zig").createNode;
pub const createLeafNode = @import("node.zig").createLeafNode;

// ============================================================================
// AST Structure
// ============================================================================

/// Complete AST structure with memory management
pub const AST = struct {
    root: ASTNode,
    allocator: std.mem.Allocator,
    /// Texts allocated during parsing that are owned by this AST
    owned_texts: []const []const u8,
    /// Original source text (optional)
    source: []const u8 = "",

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

/// Alias for AST compatibility
pub const NodeKind = NodeType;
