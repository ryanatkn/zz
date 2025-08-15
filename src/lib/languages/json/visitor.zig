const std = @import("std");
const Node = @import("../../tree_sitter/node.zig").Node;
const ExtractionContext = @import("../../tree_sitter/visitor.zig").ExtractionContext;

/// AST-based extraction visitor for JSON
pub fn visitor(context: *ExtractionContext, node: *const Node) !void {
    
    // Extract based on node type and flags
    if (context.flags.structure or context.flags.types) {
        // Extract JSON structure (objects, arrays, pairs)
        if (isStructuralNode(node.kind)) {
            try context.appendNode(node);
        }
    }

    if (context.flags.signatures) {
        // Extract object keys only
        if (isKey(node.kind)) {
            try context.appendNode(node);
        }
    }

    if (context.flags.types) {
        // Extract type information (arrays, objects, primitives)
        if (isTypedValue(node.kind)) {
            try context.appendNode(node);
        }
    }

    if (context.flags.full) {
        // For full extraction, only append the root document node to avoid duplication
        if (std.mem.eql(u8, node.kind, "document")) {
            try context.result.appendSlice(node.text);
        }
    }
}

// JSON node type checking functions
pub fn isStructuralNode(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "object") or
        std.mem.eql(u8, node_type, "array") or
        std.mem.eql(u8, node_type, "pair") or
        std.mem.eql(u8, node_type, "document");
}

pub fn isKey(node_type: []const u8) bool {
    return std.mem.eql(u8, node_type, "string");
    // TODO: Add context checking to distinguish keys from values
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
