const std = @import("std");
const Node = @import("../../tree_sitter/node.zig").Node;
const ExtractionContext = @import("../../tree_sitter/visitor.zig").ExtractionContext;

/// AST-based extraction visitor for TypeScript
pub fn visitor(context: *ExtractionContext, node: *const Node) !void {
    const node_type = node.kind;

    // Functions and methods
    if (context.flags.signatures) {
        if (std.mem.eql(u8, node_type, "function_declaration") or
            std.mem.eql(u8, node_type, "method_definition") or
            std.mem.eql(u8, node_type, "arrow_function") or
            std.mem.eql(u8, node_type, "function_expression"))
        {
            try context.appendNode(node);
            return;
        }
    }

    // Types and interfaces
    if (context.flags.types) {
        if (std.mem.eql(u8, node_type, "interface_declaration") or
            std.mem.eql(u8, node_type, "type_alias_declaration") or
            std.mem.eql(u8, node_type, "class_declaration") or
            std.mem.eql(u8, node_type, "enum_declaration"))
        {
            try context.appendNode(node);
            return;
        }
    }

    // Imports and exports
    if (context.flags.imports) {
        if (std.mem.eql(u8, node_type, "import_statement") or
            std.mem.eql(u8, node_type, "export_statement"))
        {
            try context.appendNode(node);
            return;
        }
    }

    // Tests
    if (context.flags.tests) {
        if (std.mem.eql(u8, node_type, "call_expression")) {
            const text = node.text;
            if (std.mem.startsWith(u8, text, "test(") or
                std.mem.startsWith(u8, text, "it(") or
                std.mem.startsWith(u8, text, "describe("))
            {
                try context.appendNode(node);
                return;
            }
        }
    }

    // Full source
    if (context.flags.full) {
        try context.appendNode(node);
    }
}
