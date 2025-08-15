const std = @import("std");
const Node = @import("../../tree_sitter/node.zig").Node;
const ExtractionContext = @import("../../tree_sitter/visitor.zig").ExtractionContext;

/// AST-based extraction visitor for HTML
/// Returns true to continue recursion, false to skip children
pub fn visitor(context: *ExtractionContext, node: *const Node) !bool {
    // Extract based on node type and flags - use else-if to avoid duplicates
    if (context.flags.signatures and !context.flags.structure and !context.flags.types) {
        // Extract only opening tags for signatures
        if (std.mem.eql(u8, node.kind, "start_tag") or 
            std.mem.eql(u8, node.kind, "self_closing_tag")) {
            try context.appendNode(node);
            return false; // Skip children for signatures
        }
    } else if (context.flags.structure) {
        // Extract complete HTML structure - only the root document to avoid duplicates
        if (std.mem.eql(u8, node.kind, "document")) {
            try context.appendNode(node);
            return false; // Skip children - we have the full document
        }
    } else if (context.flags.types and !context.flags.signatures and !context.flags.structure) {
        // Extract element types and attributes
        if (isElementNode(node.kind)) {
            try context.appendNode(node);
        }
    } else if (context.flags.imports and !context.flags.structure and !context.flags.signatures and !context.flags.types) {
        // Extract script src, link href, etc.
        if (isImportNode(node.kind)) {
            try context.appendNode(node);
        }
    } else if (context.flags.docs and !context.flags.structure and !context.flags.signatures and !context.flags.types) {
        // Extract HTML comments
        if (isCommentNode(node.kind)) {
            try context.appendNode(node);
        }
    } else if (context.flags.full) {
        // For full extraction, only append the root document node to avoid duplication
        if (std.mem.eql(u8, node.kind, "document")) {
            try context.result.appendSlice(node.text);
            return false; // Skip children - we already have full content
        }
    }

    return true; // Continue recursion by default
}

/// Check if node represents HTML structure
pub fn isStructuralNode(kind: []const u8) bool {
    return std.mem.eql(u8, kind, "element") or
        std.mem.eql(u8, kind, "start_tag") or
        std.mem.eql(u8, kind, "end_tag") or
        std.mem.eql(u8, kind, "attribute") or
        std.mem.eql(u8, kind, "doctype") or
        std.mem.eql(u8, kind, "text");
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
        "area", "base", "br",    "col",    "embed", "hr",  "img", "input",
        "link", "meta", "param", "source", "track", "wbr",
    };

    for (void_elements) |element| {
        if (std.mem.indexOf(u8, tag, element) != null) {
            return true;
        }
    }
    return false;
}
