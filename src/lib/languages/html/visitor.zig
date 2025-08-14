const std = @import("std");
const Node = @import("../../tree_sitter/node.zig").Node;
const ExtractionContext = @import("../../tree_sitter/visitor.zig").ExtractionContext;

/// AST-based extraction visitor for HTML
pub fn visitor(context: *ExtractionContext, node: *const Node) !void {
    // Extract based on node type and flags
    if (context.flags.structure or context.flags.types) {
        // Extract HTML elements, attributes, and structure
        if (isStructuralNode(node.kind)) {
            try context.appendNode(node);
        }
    }
    
    if (context.flags.signatures) {
        // Extract element definitions and attributes
        if (isElementNode(node.kind)) {
            try context.appendNode(node);
        }
    }
    
    if (context.flags.imports) {
        // Extract script src, link href, etc.
        if (isImportNode(node.kind)) {
            try context.appendNode(node);
        }
    }
    
    if (context.flags.docs) {
        // Extract HTML comments
        if (isCommentNode(node.kind)) {
            try context.appendNode(node);
        }
    }
}

/// Check if node represents HTML structure
pub fn isStructuralNode(kind: []const u8) bool {
    return std.mem.eql(u8, kind, "element") or
           std.mem.eql(u8, kind, "start_tag") or
           std.mem.eql(u8, kind, "end_tag") or
           std.mem.eql(u8, kind, "attribute");
}

/// Check if node is an HTML element
pub fn isElementNode(kind: []const u8) bool {
    return std.mem.eql(u8, kind, "element") or
           std.mem.eql(u8, kind, "start_tag") or
           std.mem.eql(u8, kind, "self_closing_tag");
}

/// Check if node represents imports (scripts, links, etc.)
pub fn isImportNode(kind: []const u8) bool {
    return std.mem.eql(u8, kind, "script_element") or
           std.mem.eql(u8, kind, "style_element") or
           std.mem.eql(u8, kind, "link_element");
}

/// Check if node is a comment
pub fn isCommentNode(kind: []const u8) bool {
    return std.mem.eql(u8, kind, "comment");
}

/// Check if element is a void element (self-closing)
pub fn isVoidElement(tag: []const u8) bool {
    const void_elements = [_][]const u8{
        "area", "base", "br", "col", "embed", "hr", "img", "input",
        "link", "meta", "param", "source", "track", "wbr",
    };
    
    for (void_elements) |element| {
        if (std.mem.indexOf(u8, tag, element) != null) {
            return true;
        }
    }
    return false;
}