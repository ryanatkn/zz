const std = @import("std");
const Node = @import("../../tree_sitter/node.zig").Node;
const ExtractionContext = @import("../../tree_sitter/visitor.zig").ExtractionContext;
const visitor_utils = @import("../../tree_sitter/visitor.zig");

/// AST-based extraction visitor for JSON
/// Returns true to continue recursion, false to skip children
pub fn visitor(context: *ExtractionContext, node: *const Node) !bool {
    // Use unified visitor dispatch with language-specific handlers
    return visitor_utils.dispatchByPattern(context, node, .{
        .structure_only = handleStructure,
        .types_only = handleTypes,
        .signatures_only = handleSignatures,
        .full_content = handleFullContent,
    });
}

// =============================================================================
// Handler Functions for Unified Visitor Dispatch
// =============================================================================

fn handleStructure(context: *ExtractionContext, node: *const Node) !bool {
    // Extract JSON structure (objects, arrays, pairs)
    if (isStructuralNode(node.kind)) {
        try context.appendNode(node);
        return false; // Skip children - we've captured the structure
    }
    return true;
}

fn handleTypes(context: *ExtractionContext, node: *const Node) !bool {
    // Extract type information (arrays, objects, primitives)
    if (isTypedValue(node.kind)) {
        try context.appendNode(node);
        return false; // Skip children - we've captured the typed value
    }
    return true;
}

fn handleSignatures(context: *ExtractionContext, node: *const Node) !bool {
    // Extract object key-value pairs (pairs contain keys)
    if (isPairNode(node.kind)) {
        try context.appendNode(node);
        return false; // Skip children - we've captured the pair
    }
    return true;
}

fn handleFullContent(context: *ExtractionContext, node: *const Node) !bool {
    // For full extraction, only append the root document node to avoid duplication
    if (std.mem.eql(u8, node.kind, "document")) {
        try context.result.appendSlice(node.text);
        return false; // Skip children - we already have full content
    }
    return true;
}

// =============================================================================
// JSON node type checking functions
// =============================================================================
pub fn isStructuralNode(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "object") or
        std.mem.eql(u8, node_type, "array") or
        std.mem.eql(u8, node_type, "pair") or
        std.mem.eql(u8, node_type, "document");
}

pub fn isPairNode(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "pair");
}

pub fn isTypedValue(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "string") or
        std.mem.eql(u8, node_type, "number") or
        std.mem.eql(u8, node_type, "true") or
        std.mem.eql(u8, node_type, "false") or
        std.mem.eql(u8, node_type, "null") or
        std.mem.eql(u8, node_type, "object") or
        std.mem.eql(u8, node_type, "array");
}
