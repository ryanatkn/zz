const std = @import("std");
const Node = @import("../../tree_sitter/node.zig").Node;
const ExtractionContext = @import("../../tree_sitter/visitor.zig").ExtractionContext;

/// AST-based extraction visitor for CSS
/// Returns true to continue recursion, false to skip children
pub fn visitor(context: *ExtractionContext, node: *const Node) !bool {
    const node_type = node.kind;

    // Selectors (for signatures flag)
    if (context.flags.signatures and !context.flags.structure and !context.flags.types) {
        // Extract selectors and @media rules
        if (std.mem.eql(u8, node_type, "class_selector") or
            std.mem.eql(u8, node_type, "id_selector") or
            std.mem.eql(u8, node_type, "type_selector") or
            std.mem.eql(u8, node_type, "pseudo_class_selector") or
            std.mem.eql(u8, node_type, "attribute_selector"))
        {
            try context.appendNode(node);
            return false; // Skip children - we've captured the selector
        }
        // Also extract @media rules for signatures
        if (std.mem.eql(u8, node_type, "media_statement")) {
            // Extract only the @media query part, not the content
            try context.appendSignature(node);
            return false;
        }
    }

    // At-rules and imports
    if (context.flags.imports and !context.flags.structure and !context.flags.signatures and !context.flags.types) {
        if (std.mem.eql(u8, node_type, "import_statement") or
            std.mem.eql(u8, node_type, "at_rule") or
            std.mem.startsWith(u8, node_type, "import_"))
        {
            try context.appendNode(node);
            return false; // Skip children - we've captured the import
        }
    }

    // Structure elements - complete CSS structure
    if (context.flags.structure) {
        if (std.mem.eql(u8, node_type, "rule_set") or
            std.mem.eql(u8, node_type, "media_statement") or
            std.mem.eql(u8, node_type, "keyframes_statement") or
            std.mem.eql(u8, node_type, "supports_statement") or
            std.mem.eql(u8, node_type, "import_statement"))
        {
            try context.appendNode(node);
        }
    }

    // Types - CSS properties and selectors only  
    if (context.flags.types and !context.flags.structure and !context.flags.signatures) {
        if (std.mem.eql(u8, node_type, "property_name") or
            std.mem.eql(u8, node_type, "custom_property_name") or
            std.mem.eql(u8, node_type, "class_selector") or
            std.mem.eql(u8, node_type, "id_selector") or
            std.mem.eql(u8, node_type, "type_selector") or
            std.mem.eql(u8, node_type, "pseudo_class_selector"))
        {
            try context.appendNode(node);
            return false; // Skip children for types
        }
    }

    // Comments for docs
    if (context.flags.docs) {
        if (std.mem.eql(u8, node_type, "comment")) {
            try context.appendNode(node);
            return false; // Skip children
        }
    }

    // Full source
    if (context.flags.full) {
        // For full extraction, only append the root stylesheet node to avoid duplication
        if (std.mem.eql(u8, node_type, "stylesheet")) {
            try context.result.appendSlice(node.text);
            return false; // Skip children - we already have full content
        }
    }
    
    // Default: continue recursion to child nodes
    return true;
}
