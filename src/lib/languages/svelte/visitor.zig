const std = @import("std");
const Node = @import("../../tree_sitter/node.zig").Node;
const ExtractionContext = @import("../../tree_sitter/visitor.zig").ExtractionContext;

/// AST-based extraction visitor for Svelte
pub fn visitor(context: *ExtractionContext, node: *const Node) !void {
    const node_type = node.kind;
    
    // Script sections (for signatures flag)
    if (context.flags.signatures) {
        if (std.mem.eql(u8, node_type, "script_element") or
            std.mem.eql(u8, node_type, "function_declaration") or
            std.mem.eql(u8, node_type, "variable_declaration") or
            std.mem.eql(u8, node_type, "export_statement") or
            std.mem.eql(u8, node_type, "arrow_function"))
        {
            try context.appendNode(node);
            return;
        }
    }
    
    // Style sections (for types flag)
    if (context.flags.types) {
        if (std.mem.eql(u8, node_type, "style_element") or
            std.mem.eql(u8, node_type, "rule_set") or
            std.mem.eql(u8, node_type, "selector") or
            std.mem.eql(u8, node_type, "property") or
            std.mem.eql(u8, node_type, "variable_declaration"))
        {
            try context.appendNode(node);
            return;
        }
    }
    
    // Template structure (for structure flag)
    if (context.flags.structure) {
        if (std.mem.eql(u8, node_type, "element") or
            std.mem.eql(u8, node_type, "start_tag") or
            std.mem.eql(u8, node_type, "end_tag") or
            std.mem.eql(u8, node_type, "attribute") or
            std.mem.eql(u8, node_type, "if_statement") or
            std.mem.eql(u8, node_type, "each_statement") or
            std.mem.eql(u8, node_type, "component"))
        {
            try context.appendNode(node);
            return;
        }
    }
    
    // Imports (for imports flag)
    if (context.flags.imports) {
        if (std.mem.eql(u8, node_type, "import_statement") or
            std.mem.eql(u8, node_type, "export_statement") or
            std.mem.startsWith(u8, node_type, "import_"))
        {
            try context.appendNode(node);
            return;
        }
    }
    
    // Comments for docs
    if (context.flags.docs) {
        if (std.mem.eql(u8, node_type, "comment") or
            std.mem.eql(u8, node_type, "html_comment"))
        {
            try context.appendNode(node);
            return;
        }
    }
    
    // Full source
    if (context.flags.full) {
        try context.appendNode(node);
    }
}