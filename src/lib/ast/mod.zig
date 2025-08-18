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
