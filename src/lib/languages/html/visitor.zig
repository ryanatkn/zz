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
            try appendNormalizedHtmlDocument(context, node);
            return false; // Skip children - we have the full document
        }
    } else if (context.flags.types and !context.flags.signatures and !context.flags.structure) {
        // Extract element types and attributes
        if (isElementNode(node.kind)) {
            try context.appendNode(node);
        }
    } else if (context.flags.imports and !context.flags.structure and !context.flags.signatures and !context.flags.types) {
        // Extract script src, link href, and event handler attributes
        if (isImportNode(node.kind)) {
            try context.appendNode(node);
        } else if (isEventHandlerAttribute(node)) {
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

/// Check if node is an event handler attribute (starts with 'on')
pub fn isEventHandlerAttribute(node: *const Node) bool {
    // Check if it's an attribute node
    if (!std.mem.eql(u8, node.kind, "attribute")) {
        return false;
    }
    
    // Check if the attribute text starts with an event handler (on...)
    const text = std.mem.trim(u8, node.text, " \t\n\r");
    
    // Common event handlers
    const event_handlers = [_][]const u8{
        "onclick=", "onmouseover=", "onmouseout=", "onload=", "onunload=",
        "onsubmit=", "onchange=", "onfocus=", "onblur=", "onkeydown=",
        "onkeyup=", "onkeypress=", "onmousedown=", "onmouseup=", "onmousemove=",
    };
    
    for (event_handlers) |handler| {
        if (std.mem.startsWith(u8, text, handler)) {
            return true;
        }
    }
    
    return false;
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

/// Helper function to normalize HTML document for structure extraction
/// Removes all indentation to match test expectations
fn appendNormalizedHtmlDocument(context: *ExtractionContext, node: *const Node) !void {
    var lines = std.mem.splitScalar(u8, node.text, '\n');
    var normalized = std.ArrayList(u8).init(context.allocator);
    defer normalized.deinit();
    
    while (lines.next()) |line| {
        // Remove leading whitespace (indentation) from each line
        const trimmed_start = std.mem.trimLeft(u8, line, " \t");
        
        // Only append if not empty after trimming
        if (trimmed_start.len > 0) {
            try normalized.appendSlice(trimmed_start);
            try normalized.append('\n');
        }
    }
    
    // Remove trailing newline if present
    if (normalized.items.len > 0 and normalized.items[normalized.items.len - 1] == '\n') {
        _ = normalized.pop();
    }
    
    // Append the normalized content
    try context.result.appendSlice(normalized.items);
    if (!std.mem.endsWith(u8, normalized.items, "\n")) {
        try context.result.append('\n');
    }
}
