const std = @import("std");
const Node = @import("../../tree_sitter/node.zig").Node;
const ExtractionContext = @import("../../tree_sitter/visitor.zig").ExtractionContext;

/// AST-based extraction visitor for CSS
pub fn visitor(context: *ExtractionContext, node: *const Node) !void {
    const node_type = node.kind;

    // Selectors (for signatures flag)
    if (context.flags.signatures) {
        if (std.mem.eql(u8, node_type, "rule_set") or
            std.mem.eql(u8, node_type, "selector") or
            std.mem.eql(u8, node_type, "media_query") or
            std.mem.startsWith(u8, node_type, "selector_"))
        {
            try context.appendNode(node);
            return;
        }
    }

    // At-rules and imports
    if (context.flags.imports) {
        if (std.mem.eql(u8, node_type, "import_statement") or
            std.mem.eql(u8, node_type, "at_rule") or
            std.mem.startsWith(u8, node_type, "import_"))
        {
            try context.appendNode(node);
            return;
        }
    }

    // Structure elements (media queries, keyframes) and types (selectors, properties)
    if (context.flags.structure or context.flags.types) {
        if (std.mem.eql(u8, node_type, "media_statement") or
            std.mem.eql(u8, node_type, "keyframes_statement") or
            std.mem.eql(u8, node_type, "supports_statement") or
            std.mem.eql(u8, node_type, "property_name") or
            std.mem.eql(u8, node_type, "custom_property_name") or
            std.mem.eql(u8, node_type, "rule_set") or
            std.mem.eql(u8, node_type, "class_selector") or
            std.mem.eql(u8, node_type, "id_selector") or
            std.mem.eql(u8, node_type, "pseudo_class_selector") or
            std.mem.eql(u8, node_type, "at_rule") or
            std.mem.eql(u8, node_type, "declaration") or
            std.mem.eql(u8, node_type, "import_statement"))
        {
            try context.appendNode(node);
            return;
        }
    }

    // Comments for docs
    if (context.flags.docs) {
        if (std.mem.eql(u8, node_type, "comment")) {
            try context.appendNode(node);
            return;
        }
    }

    // Full source
    if (context.flags.full) {
        // For full extraction, only append the root stylesheet node to avoid duplication
        if (std.mem.eql(u8, node_type, "stylesheet")) {
            try context.result.appendSlice(node.text);
        }
    }
}
